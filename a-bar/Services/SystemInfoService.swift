import Carbon
import Combine
import CoreAudio
import Foundation
import IOKit.ps
import AppKit

/// Service for collecting system information (battery, CPU, memory, etc.)
class SystemInfoService: ObservableObject {
    static let shared = SystemInfoService()

    @Published private(set) var batteryInfo = BatteryInfo()
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryPressure: Double = 0
    @Published private(set) var gpuUsage: Double = 0
    @Published private(set) var networkStats = NetworkStats()
    @Published private(set) var wifiInfo = WifiInfo()
    @Published private(set) var volumeLevel: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var isMicMuted: Bool = false
    @Published private(set) var keyboardLayout: String = ""
    @Published private(set) var isCaffeinateActive: Bool = false
    private var caffeinateProcess: Process?
    private var caffeinateProcessKeepAlive: Process?
    
    // Disk I/O
    @Published private(set) var diskStats = DiskIOStats()
    private var previousDiskBytes: (read: UInt64, write: UInt64)?
    private var lastDiskCheckTime: Date?

    // Graph histories
    @Published var cpuHistory = GraphHistory(maxLength: 40)
    @Published var gpuHistory = GraphHistory(maxLength: 40)
    @Published var downloadHistory = GraphHistory(maxLength: 30)
    @Published var uploadHistory = GraphHistory(maxLength: 30)
    @Published var diskReadHistory = GraphHistory(maxLength: 30)
    @Published var diskWriteHistory = GraphHistory(maxLength: 30)

    private var refreshTimers: [String: Timer] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let settingsManager = SettingsManager.shared

    private var previousNetworkBytes: (rx: UInt64, tx: UInt64)?
    private var lastNetworkCheckTime: Date?

    // Storage volumes
    @Published private(set) var volumes: [StorageVolume] = []
    private var timer: Timer?

    /// Cached host port to avoid Mach port leaks.
    /// Each call to mach_host_self() creates a new send right that must be
    /// manually deallocated. Caching it once avoids leaking ~2,700 ports/hour
    /// which would exhaust the per-task port limit after ~1.5 days, causing
    /// system-wide input freeze (keyboard/mouse unresponsive).
    private let hostPort: mach_port_t = mach_host_self()

    private init() {
        setupKeyboardLayoutObserver()
        refreshVolumes()
        setupAutoRefresh()
        setupNotifications()
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        refreshBattery()
        refreshCPU()
        refreshMemory()
        refreshGPU()
        refreshNetworkStats()
        refreshDiskStats()
        refreshWifi()
        refreshVolume()
        refreshMic()
        refreshKeyboard()
        refreshCaffeinate()

        startTimers()
    }

    func stop() {
        refreshTimers.values.forEach { $0.invalidate() }
        refreshTimers.removeAll()
    }

    func refresh() {
        refreshBattery()
        refreshCPU()
        refreshMemory()
        refreshGPU()
        refreshNetworkStats()
        refreshDiskStats()
        refreshWifi()
        refreshVolume()
        refreshMic()
        refreshKeyboard()
        refreshCaffeinate()
    }

    func refreshBattery() {
        DispatchQueue.global(qos: .background).async {
            let info = self.getBatteryInfo()
            DispatchQueue.main.async {
                self.batteryInfo = info
            }
        }
    }

    private func getBatteryInfo() -> BatteryInfo {
        var info = BatteryInfo()
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty,
              let description = IOPSGetPowerSourceDescription(snapshot, sources[0])?.takeUnretainedValue() as? [String: Any]
        else {
            return info
        }

        if let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
           let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int {
            info.percentage = Int((Double(currentCapacity) / Double(maxCapacity)) * 100)
        }

        if let isCharging = description[kIOPSIsChargingKey as String] as? Bool {
            info.isCharging = isCharging
        } else if let powerSourceState = description[kIOPSPowerSourceStateKey as String] as? String {
            info.isCharging = (powerSourceState == kIOPSACPowerValue)
        }

        // Low Power Mode (macOS 12+)
        if #available(macOS 12.0, *) {
            info.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        return info
    }

    private var previousCPUTicks: [UInt64]?

    func refreshCPU() {
        Task {
            let usage = getCPUUsage()
            await MainActor.run {
                self.cpuUsage = usage
                self.cpuHistory.add(usage)
            }
        }
    }

    private func getCPUUsage() -> Double {
        var kr: kern_return_t
        var cpuInfo: processor_info_array_t?
        var numCPU: mach_msg_type_number_t = 0
        var numCPUsU: natural_t = 0
        let CPU_USAGE_USER = 0
        let CPU_USAGE_SYSTEM = 1
        let CPU_USAGE_IDLE = 2
        let CPU_STATE_MAX = 4

        kr = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCPU)
        guard kr == KERN_SUCCESS else { return 0 }
        guard let cpuInfoPtr = cpuInfo else { return 0 }

        let cpuInfoBuffer = UnsafeBufferPointer(start: cpuInfoPtr, count: Int(numCPU))
        var ticks: [UInt64] = []

        for cpu in 0..<Int(numCPUsU) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(cpuInfoBuffer[base + CPU_USAGE_USER])
            let system = UInt64(cpuInfoBuffer[base + CPU_USAGE_SYSTEM])
            let idle = UInt64(cpuInfoBuffer[base + CPU_USAGE_IDLE])
            let nice = UInt64(cpuInfoBuffer[base + 3])
            ticks.append(user)
            ticks.append(system)
            ticks.append(idle)
            ticks.append(nice)
        }

        var usage: Double = 0
        if let previous = previousCPUTicks, previous.count == ticks.count {
            var totalDiff: UInt64 = 0
            var idleDiff: UInt64 = 0
            for i in stride(from: 0, to: ticks.count, by: 4) {
                let userDiff = ticks[i] - previous[i]
                let systemDiff = ticks[i+1] - previous[i+1]
                let idleDiffCPU = ticks[i+2] - previous[i+2]
                let niceDiff = ticks[i+3] - previous[i+3]
                totalDiff += userDiff + systemDiff + idleDiffCPU + niceDiff
                idleDiff += idleDiffCPU
            }
            if totalDiff > 0 {
                // Overall CPU utilization across all cores as percentage 0-100
                usage = 100.0 * Double(totalDiff - idleDiff) / Double(totalDiff)
            }
        }
        previousCPUTicks = ticks

        // Deallocate the cpuInfo buffer
        let cpuInfoSize = Int(numCPU) * MemoryLayout<integer_t>.stride
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfoPtr), vm_size_t(cpuInfoSize))

        return usage
    }

    func refreshMemory() {
        let usage = getMemoryUsage()
        DispatchQueue.main.async {
            self.memoryPressure = usage
        }
    }

    private func getMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            print("Error getting VM statistics: \(result)")
            return 0
        }

        let pageSize = vm_kernel_page_size
        let active = Double(stats.active_count) * Double(pageSize)
        let wired = Double(stats.wire_count) * Double(pageSize)
        let compressed = Double(stats.compressor_page_count) * Double(pageSize)
        let free = Double(stats.free_count) * Double(pageSize)
        let inactive = Double(stats.inactive_count) * Double(pageSize)

        // Activity Monitor: Used = Wired + Active + Compressed; Available = Free + Inactive
        let used = active + wired + compressed
        let available = free + inactive
        let total = used + available
        guard total > 0 else { return 0 }
        return (used / total) * 100.0
    }

    func refreshGPU() {
        Task {
            let usage = await getGPUUsage()
            await MainActor.run {
                self.gpuUsage = usage
                self.gpuHistory.add(usage)
            }
        }
    }

    private func getGPUUsage() async -> Double {
        // Returns GPU usage as a percentage (0-100)
        // Note: This uses IOAccelerator's PerformanceStatistics, which measures
        // instantaneous renderer utilization. Tools like macmon use IOReport with
        // frequency residencies for a more accurate "effective utilization" metric.
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return 0 }

        var usage: Double = 0
        var found = false
        var service = IOIteratorNext(iterator)
        
        while service != 0 {
            defer { IOObjectRelease(service) }
            
            if let properties = getProperties(for: service),
               let perf = properties["PerformanceStatistics"] as? [String: Any] {
                
                // Use Renderer Utilization % (instantaneous renderer busy time)
                if let rendererUtil = perf["Renderer Utilization %"] as? Int {
                    usage = Double(rendererUtil)
                    found = true
                    break
                } else if let rendererUtilDouble = perf["Renderer Utilization %"] as? Double {
                    usage = rendererUtilDouble
                    found = true
                    break
                }
                // Fallback to Device Utilization (typically 3-4x higher than Activity Monitor)
                else if let deviceUtil = perf["Device Utilization %"] as? Int {
                    usage = Double(deviceUtil) / 3.5
                    found = true
                    break
                } else if let deviceUtilDouble = perf["Device Utilization %"] as? Double {
                    usage = deviceUtilDouble / 3.5
                    found = true
                    break
                }
            }
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        
        // Scale down to match Activity Monitor's "effective utilization" 
        // IOAccelerator reports instantaneous utilization, but doesn't account for
        // frequency scaling and idle time like IOReport-based tools (macmon, iStat Menus)
        return found ? usage * 0.4 : 0
    }

    private func getProperties(for service: io_service_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return props
    }

    func refreshNetworkStats() {
        Task {
            let stats = await getNetworkStats()
            await MainActor.run {
                self.networkStats = stats
                self.downloadHistory.add(Double(stats.download))
                self.uploadHistory.add(Double(stats.upload))
            }
        }
    }

    /// Get network statistics - uses shell command fallback for M4 compatibility
    private func getNetworkStats() async -> NetworkStats {
        // Try native approach first
        if let stats = getNetworkStatsNative() {
            return stats
        }
        
        // Fallback to netstat command for M4 Macs where native approach may fail
        return await getNetworkStatsViaNetstat()
    }
    
    /// Native sysctl-based network statistics (primary method)
    private func getNetworkStatsNative() -> NetworkStats? {
        var rxBytes: UInt64 = 0
        var txBytes: UInt64 = 0
        var foundInterfaces: [String] = []
        
        // Use sysctl to get interface statistics with proper 64-bit counters
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: size_t = 0
        
        // First call to get required buffer size
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else {
            print("[NetworkStats] sysctl size query failed")
            return nil
        }
        
        // Allocate buffer and fetch data
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        defer { buffer.deallocate() }
        
        guard sysctl(&mib, UInt32(mib.count), buffer, &len, nil, 0) == 0 else {
            print("[NetworkStats] sysctl data fetch failed")
            return nil
        }
        
        // Parse the buffer containing if_msghdr2 structures
        var offset = 0
        while offset < len {
            let msgHdr = buffer.advanced(by: offset).withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
            
            // Check if this is an interface info message
            if msgHdr.ifm_type == RTM_IFINFO2 {
                let ifm2 = buffer.advanced(by: offset).withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
                
                // Get interface name
                let ifIndex = Int(ifm2.ifm_index)
                if let ifName = getInterfaceName(index: ifIndex) {
                    let ifRx = ifm2.ifm_data.ifi_ibytes
                    let ifTx = ifm2.ifm_data.ifi_obytes
                    
                    if isValidDataInterface(ifName) {
                        foundInterfaces.append("\(ifName): rx=\(ifRx) tx=\(ifTx)")
                        rxBytes &+= ifRx
                        txBytes &+= ifTx
                    }
                }
            }
            
            // Move to next message
            let msgLen = Int(msgHdr.ifm_msglen)
            guard msgLen > 0 else { break }
            offset += msgLen
        }
        
        if foundInterfaces.isEmpty {
            print("[NetworkStats] No valid interfaces found via sysctl, falling back to netstat")
            return nil
        }
        
        let now = Date()
        
        if let previous = previousNetworkBytes,
           let lastTime = lastNetworkCheckTime {
            
            let delta = now.timeIntervalSince(lastTime)
            guard delta > 0 else { return NetworkStats() }
            
            // Handle counter wraparound gracefully
            let rxDiff = rxBytes >= previous.rx ? rxBytes - previous.rx : rxBytes
            let txDiff = txBytes >= previous.tx ? txBytes - previous.tx : txBytes
            
            let download = Double(rxDiff) / delta
            let upload = Double(txDiff) / delta
            
            previousNetworkBytes = (rxBytes, txBytes)
            lastNetworkCheckTime = now
            
            return NetworkStats(
                download: UInt64(max(0, download)),
                upload: UInt64(max(0, upload))
            )
        }
        
        previousNetworkBytes = (rxBytes, txBytes)
        lastNetworkCheckTime = now
        return NetworkStats()
    }
    
    /// Fallback method using netstat command
    private func getNetworkStatsViaNetstat() async -> NetworkStats {
        do {
            // Get interface stats using netstat
            let output = try await ShellExecutor.run("netstat -ibn | awk 'NR>1 && $1 !~ /lo/ {print $1,$7,$10}'")
            
            var rxBytes: UInt64 = 0
            var txBytes: UInt64 = 0
            
            // Parse output: interface_name rx_bytes tx_bytes
            let lines = output.split(separator: "\n")
            for line in lines {
                let parts = line.split(separator: " ")
                guard parts.count >= 3 else { continue }
                
                let ifName = String(parts[0])
                guard isValidDataInterface(ifName) else { continue }
                
                if let rx = UInt64(parts[1]), let tx = UInt64(parts[2]) {
                    rxBytes &+= rx
                    txBytes &+= tx
                }
            }
            
            let now = Date()
            
            if let previous = previousNetworkBytes,
               let lastTime = lastNetworkCheckTime {
                
                let delta = now.timeIntervalSince(lastTime)
                guard delta > 0 else { return NetworkStats() }
                
                // Handle counter wraparound
                let rxDiff = rxBytes >= previous.rx ? rxBytes - previous.rx : rxBytes
                let txDiff = txBytes >= previous.tx ? txBytes - previous.tx : txBytes
                
                let download = Double(rxDiff) / delta
                let upload = Double(txDiff) / delta
                
                previousNetworkBytes = (rxBytes, txBytes)
                lastNetworkCheckTime = now
                
                return NetworkStats(
                    download: UInt64(max(0, download)),
                    upload: UInt64(max(0, upload))
                )
            }
            
            previousNetworkBytes = (rxBytes, txBytes)
            lastNetworkCheckTime = now
            return NetworkStats()
            
        } catch {
            print("[NetworkStats] netstat fallback failed: \(error)")
            return NetworkStats()
        }
    }
    
    /// Get interface name from index using if_indextoname
    private func getInterfaceName(index: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        guard if_indextoname(UInt32(index), &buffer) != nil else {
            return nil
        }
        return String(cString: buffer)
    }

    /// Accepts only real data-carrying interfaces (consistent across all Mac models)
    private func isValidDataInterface(_ name: String) -> Bool {
        // Primary interfaces for actual network traffic
        return
            name.hasPrefix("en") ||      // Ethernet / Wi-Fi (en0, en1, etc.)
            name.hasPrefix("bridge") ||  // Network bridge interfaces
            name.hasPrefix("ap") ||      // Access point interfaces
            name.hasPrefix("awdl") ||    // Apple Wireless Direct Link
            name.hasPrefix("llw") ||     // Low Latency WLAN
            name.hasPrefix("utun") ||    // VPN / system tunnels
            name.hasPrefix("ipsec") ||   // IPSec tunnels
            name.hasPrefix("pdp_ip") ||  // iPhone tethering
            name.hasPrefix("ppp")        // Point-to-Point Protocol
    }
    
    func refreshDiskStats() {
        Task {
            let stats = await getDiskStats()
            await MainActor.run {
                self.diskStats = stats
                self.diskReadHistory.add(Double(stats.read))
                self.diskWriteHistory.add(Double(stats.write))
            }
        }
    }
    
    /// Get disk I/O statistics using IOKit (IOBlockStorageDriver)
    private func getDiskStats() async -> DiskIOStats {
        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0
        
        // Query IOBlockStorageDriver for accurate disk statistics
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return DiskIOStats() }
        
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            
            // Get properties for this storage driver
            var properties: Unmanaged<CFMutableDictionary>?
            let propsResult = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
            
            if propsResult == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] {
                // Get statistics from the driver
                if let stats = props["Statistics"] as? [String: Any] {
                    // Try different key formats - varies by macOS version
                    if let read = stats["Bytes (Read)"] as? UInt64 {
                        readBytes += read
                    } else if let read = stats["Bytes Read"] as? UInt64 {
                        readBytes += read
                    }
                    
                    if let write = stats["Bytes (Write)"] as? UInt64 {
                        writeBytes += write
                    } else if let write = stats["Bytes Written"] as? UInt64 {
                        writeBytes += write
                    }
                }
                
                // Alternative: Check for Operations statistics
                if readBytes == 0 && writeBytes == 0 {
                    if let stats = props["Statistics"] as? [String: Any] {
                        // Some systems report in sectors (512 bytes each)
                        if let readOps = stats["Operations (Read)"] as? UInt64,
                           let bytesPerRead = stats["Bytes per Read"] as? UInt64 {
                            readBytes += readOps * bytesPerRead
                        }
                        if let writeOps = stats["Operations (Write)"] as? UInt64,
                           let bytesPerWrite = stats["Bytes per Write"] as? UInt64 {
                            writeBytes += writeOps * bytesPerWrite
                        }
                    }
                }
            }
            
            service = IOIteratorNext(iterator)
        }
        
        let now = Date()
        
        // Calculate bytes per second
        if let previous = previousDiskBytes,
           let lastTime = lastDiskCheckTime,
           now.timeIntervalSince(lastTime) > 0 {
            let timeDelta = now.timeIntervalSince(lastTime)
            let readDelta = readBytes > previous.read ? readBytes - previous.read : 0
            let writeDelta = writeBytes > previous.write ? writeBytes - previous.write : 0
            
            let readPerSec = UInt64(Double(readDelta) / timeDelta)
            let writePerSec = UInt64(Double(writeDelta) / timeDelta)
            
            previousDiskBytes = (readBytes, writeBytes)
            lastDiskCheckTime = now
            
            return DiskIOStats(read: readPerSec, write: writePerSec)
        }
        
        previousDiskBytes = (readBytes, writeBytes)
        lastDiskCheckTime = now
        return DiskIOStats()
    }

    func refreshWifi() {
        Task {
            let info = await getWifiInfo()
            await MainActor.run {
                self.wifiInfo = info
            }
        }
    }

    private func getWifiInfo() async -> WifiInfo {
        var info = WifiInfo()
        let device = settingsManager.settings.widgets.wifi.networkDevice

        do {
            let statusOutput = try await ShellExecutor.run(
                "ifconfig \(device) | grep status | cut -c 10-")
            info.isActive = statusOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "active"

            if info.isActive {
                // Get SSID using airport command which is more reliable
                let ssidOutput = try await ShellExecutor.run(
                    "/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I | awk '/ SSID/ {print $2}'"
                )
                info.ssid = ssidOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Error getting WiFi info: \(error)")
        }

        return info
    }

    func refreshVolume() {
        let volume = getSystemVolume()
        let muted = isSystemMuted()

        DispatchQueue.main.async {
            self.volumeLevel = volume
            self.isMuted = muted
        }
    }

    /// Set system output volume (0.0 - 1.0) using CoreAudio and update published state. Best-effort, robust for all macOS devices.
    @discardableResult
    func setSystemVolume(_ level: Float) -> Bool {
        let clampedValue = min(max(level, 0.0), 1.0)
        var didSet = false
        DispatchQueue.global(qos: .userInitiated).async {
            var deviceID = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            guard AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            ) == noErr else {
                return
            }

            // Helper to set volume for a given element
            func setVolume(element: AudioObjectPropertyElement) -> Bool {
                var volume = clampedValue
                let propertySize = UInt32(MemoryLayout<Float32>.size)
                var volumeAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                                var isSettable: DarwinBoolean = false
                                guard AudioObjectHasProperty(deviceID, &volumeAddress),
                                            AudioObjectIsPropertySettable(deviceID, &volumeAddress, &isSettable) == noErr, isSettable != false,
                                            AudioObjectSetPropertyData(
                                                deviceID,
                                                &volumeAddress,
                                                0,
                                                nil,
                                                propertySize,
                                                &volume
                                            ) == noErr else {
                                        return false
                                }
                return true
            }

            // Try master volume
            if setVolume(element: kAudioObjectPropertyElementMain) {
                didSet = true
            } else {
                // Try left/right channels
                let leftSet  = setVolume(element: 1)
                let rightSet = setVolume(element: 2)
                didSet = leftSet || rightSet
            }

            if didSet {
                DispatchQueue.main.async {
                    self.volumeLevel = clampedValue
                    self.isMuted = self.isSystemMuted()
                }
            }
        }
        return didSet
    }

    /// Set system output mute state using CoreAudio and update published state.
    func setSystemMuted(_ muted: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            var defaultOutputDeviceID = AudioObjectID(kAudioObjectUnknown)
            var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &propertySize,
                &defaultOutputDeviceID
            )

            guard status == noErr else { return }

            var mutedValue: UInt32 = muted ? 1 : 0
            propertySize = UInt32(MemoryLayout<UInt32>.size)

            propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectSetPropertyData(defaultOutputDeviceID, &propertyAddress, 0, nil, propertySize, &mutedValue)

            DispatchQueue.main.async {
                self.isMuted = self.isSystemMuted()
                self.volumeLevel = self.getSystemVolume()
            }
        }
    }

    private func getSystemVolume() -> Float {
        // Robust, production-safe macOS output volume retrieval
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return 0
        }

        // Helper to read volume for a given element
        func readVolume(element: AudioObjectPropertyElement) -> Float? {
            var volume = Float32(0)
            var propertySize = UInt32(MemoryLayout<Float32>.size)
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(deviceID, &volumeAddress),
                  AudioObjectGetPropertyData(
                    deviceID,
                    &volumeAddress,
                    0,
                    nil,
                    &propertySize,
                    &volume
                  ) == noErr else {
                return nil
            }
            return volume
        }

        // Try master volume
        if let master = readVolume(element: kAudioObjectPropertyElementMain) {
            return master
        }
        // Try left/right channels
        let left = readVolume(element: 1)
        let right = readVolume(element: 2)
        switch (left, right) {
        case let (l?, r?):
            return (l + r) / 2
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return 0 // nil means not available, but for UI fallback to 0
        }
    }

    private func isSystemMuted() -> Bool {
        var defaultOutputDeviceID = AudioObjectID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )

        guard status == noErr else { return false }

        var muted: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)

        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &muted
        )

        return muted != 0
    }

    func refreshMic() {
        let level = getMicLevel()
        let muted = checkIfMicMuted()

        DispatchQueue.main.async {
            self.micLevel = level
            self.isMicMuted = muted
        }
    }

    private func getMicLevel() -> Float {
        var defaultInputDeviceID = AudioObjectID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultInputDeviceID
        )

        guard status == noErr else { return 0 }

        var volume: Float32 = 0
        propertySize = UInt32(MemoryLayout<Float32>.size)

        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            defaultInputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &volume
        )

        return volume
    }

    private func checkIfMicMuted() -> Bool {
        var defaultInputDeviceID = AudioObjectID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultInputDeviceID
        )

        guard status == noErr else { return false }

        var muted: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)

        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            defaultInputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &muted
        )

        return muted != 0
    }

    func refreshKeyboard() {
        let layout = getCurrentKeyboardLayout()
        DispatchQueue.main.async {
            self.keyboardLayout = layout
        }
    }

    private func getCurrentKeyboardLayout() -> String {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        {
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            return name
        }
        return "Unknown"
    }

    private func setupKeyboardLayoutObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshKeyboard()
        }
    }

    func refreshCaffeinate() {
        // Check both our managed process and any existing system-wide caffeinate
        DispatchQueue.global(qos: .background).async {
            let managedActive = self.caffeinateProcess?.isRunning ?? false
            let active: Bool
            if managedActive {
                active = true
            } else {
                // If our managed process isn't running, see if any caffeinate is already active on the system
                active = self.isAnyCaffeinateRunning()
            }
            DispatchQueue.main.async {
                self.isCaffeinateActive = active
            }
        }
    }

    func toggleCaffeinate(option: String = "") {
        if isCaffeinateActive {
            caffeinateProcess?.terminate()
            caffeinateProcess = nil
            caffeinateProcessKeepAlive = nil
            killAllCaffeinateProcesses()
        } else {
            // Kill all existing caffeinate processes before starting a new one
            killAllCaffeinateProcesses()
            let process = Process()
            process.launchPath = "/usr/bin/caffeinate"
            let args = caffeinateArguments(for: option)
            process.arguments = args
            process.standardOutput = nil
            process.standardError = nil
            process.qualityOfService = .userInitiated
            process.terminationHandler = { [weak self] proc in
                DispatchQueue.main.async {
                    self?.isCaffeinateActive = false
                }
            }
            caffeinateProcess = process
            caffeinateProcessKeepAlive = process
            do {
                try process.run()
                DispatchQueue.main.async {
                    self.isCaffeinateActive = true
                }
            } catch {
                caffeinateProcess = nil
                caffeinateProcessKeepAlive = nil
                DispatchQueue.main.async {
                    self.isCaffeinateActive = false
                }
            }
        }
        refreshCaffeinate()
    }

    private func caffeinateArguments(for option: String) -> [String] {
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "systemsleep":
            return ["-s"] // Prevent system sleep
        case "displaysleep":
            return ["-d"] // Prevent display sleep
        case "idlesleep":
            return ["-i"] // Prevent idle sleep
        case "user":
            return ["-u"] // Prevent sleep due to user inactivity
        case "displayidle":
            return ["-di"] // Prevent display and idle sleep
        case "all":
            return ["-dimu"] // Prevent all sleep types
        case "":
            return ["-di"] // Default: prevent display and idle sleep
        default:
            // If the option looks like a valid flag, use it; otherwise, fallback to default
            if trimmed.hasPrefix("-") {
                return [trimmed]
            } else {
                return ["-di"]
            }
        }
    }

    private func killAllCaffeinateProcesses() {
        let process = Process()
        process.launchPath = "/usr/bin/pkill"
        process.arguments = ["caffeinate"]
        try? process.run()
        process.waitUntilExit()
    }
  
    private func isAnyCaffeinateRunning() -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/pgrep"
        process.arguments = ["-x", "caffeinate"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            // pgrep exits with 0 when it finds a matching process
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func startTimers() {
        // Ensure caffeinate is stopped on bar restart
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
        caffeinateProcessKeepAlive = nil

        let settings = settingsManager.settings.widgets

        // Battery timer
        scheduleTimer(id: "battery", interval: settings.battery.refreshInterval) { [weak self] in
            self?.refreshBattery()
            self?.refreshCaffeinate()
        }

        // CPU timer
        scheduleTimer(id: "cpu", interval: settings.cpu.refreshInterval) { [weak self] in
            self?.refreshCPU()
        }

        // Memory timer
        scheduleTimer(id: "memory", interval: settings.memory.refreshInterval) { [weak self] in
            self?.refreshMemory()
        }

        // GPU timer
        scheduleTimer(id: "gpu", interval: settings.gpu.refreshInterval) { [weak self] in
            self?.refreshGPU()
        }

        // Network stats timer
        scheduleTimer(id: "netstats", interval: settings.netstats.refreshInterval) { [weak self] in
            self?.refreshNetworkStats()
        }

        // Disk activity timer
        scheduleTimer(id: "diskActivity", interval: settings.diskActivity.refreshInterval) { [weak self] in
            self?.refreshDiskStats()
        }

        // WiFi timer
        scheduleTimer(id: "wifi", interval: settings.wifi.refreshInterval) { [weak self] in
            self?.refreshWifi()
        }

        // Volume timer
        scheduleTimer(id: "volume", interval: settings.sound.refreshInterval) { [weak self] in
            self?.refreshVolume()
        }

        // Mic timer
        scheduleTimer(id: "mic", interval: settings.mic.refreshInterval) { [weak self] in
            self?.refreshMic()
        }

        // Keyboard timer
        scheduleTimer(id: "keyboard", interval: settings.keyboard.refreshInterval) { [weak self] in
            self?.refreshKeyboard()
        }
    }

    private func scheduleTimer(id: String, interval: TimeInterval, action: @escaping () -> Void) {
        refreshTimers[id]?.invalidate()
        refreshTimers[id] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            action()
        }
    }

    private func refreshVolumes() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []
        let volumes = urls.compactMap { url -> StorageVolume? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  let name = values.volumeName,
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity
            else { return nil }
            // Optionally filter out unwanted volumes (e.g., disk images)
            // if let isRemovable = values.volumeIsRemovable, isRemovable { return nil }
            return StorageVolume(
                name: name,
                url: url,
                totalBytes: total,
                usedBytes: total - available
            )
        }
        DispatchQueue.main.async {
            self.volumes = volumes
        }
    }

    private func setupAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshVolumes()
        }
    }

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleMount), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(handleMount), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    @objc private func handleMount(_ notification: Notification) {
        refreshVolumes()
    }
}

struct BatteryInfo: Equatable {
    var percentage: Int = 100
    var isCharging: Bool = false
    var isLowPowerMode: Bool = false

    var isLow: Bool {
        percentage < 20 && !isCharging
    }
}

struct WifiInfo: Equatable {
    var isActive: Bool = false
    var ssid: String = ""
}

struct StorageVolume: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
    let totalBytes: Int
    let usedBytes: Int

    var fullness: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var fullnessPercent: Int {
        Int((fullness * 100).rounded())
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .file)
    }
}

struct DiskIOStats: Equatable {
    var read: UInt64 = 0
    var write: UInt64 = 0
    
    var formattedRead: String {
        formatSpeed(Double(read))
    }
    
    var formattedWrite: String {
        formatSpeed(Double(write))
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f K/s", bytesPerSecond / 1024)
        } else if bytesPerSecond < 1024 * 1024 * 1024 {
            return String(format: "%.1f M/s", bytesPerSecond / 1024 / 1024)
        } else {
            return String(format: "%.1f G/s", bytesPerSecond / 1024 / 1024 / 1024)
        }
    }
}
