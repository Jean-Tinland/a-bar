import Carbon
import Combine
import CoreAudio
import Foundation
import IOKit.ps
import AppKit

/// The CoreAudio registration boundary is injectable; readers retain their existing native calls.
struct AudioPropertyEvents {
    var hasProperty: (AudioObjectID, AudioObjectPropertyAddress) -> Bool
    var add: (AudioObjectID, AudioObjectPropertyAddress, @escaping AudioObjectPropertyListenerBlock) -> OSStatus
    var remove: (AudioObjectID, AudioObjectPropertyAddress, @escaping AudioObjectPropertyListenerBlock) -> Void

    static let live = AudioPropertyEvents(
        hasProperty: { object, address in
            var address = address
            return AudioObjectHasProperty(object, &address)
        },
        add: { object, address, block in
            var address = address
            return AudioObjectAddPropertyListenerBlock(object, &address, .main, block)
        },
        remove: { object, address, block in
            var address = address
            _ = AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        })
}

/// Service for collecting system information (battery, CPU, memory, etc.)
class SystemInfoService: ObservableObject {
    static let shared = SystemInfoService()

    @Published private(set) var batteryInfo = BatteryInfo()
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryPressure: Double = 0
    @Published private(set) var gpuUsage: Double = 0
    @Published private(set) var networkStats = NetworkStats()
    @Published private(set) var volumeLevel: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var audioOutputDeviceName: String = ""
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var isMicMuted: Bool = false
    @Published private(set) var audioInputDeviceName: String = ""
    @Published private(set) var keyboardLayout: String = ""
    @Published private(set) var isCaffeinateActive: Bool = false
    private var caffeinateProcess: Process?
    private var caffeinateProcessKeepAlive: Process?
    
    // Disk I/O
    @Published private(set) var diskStats = DiskIOStats()
    /// A disk that vanishes and comes back is not a burst of I/O, so a counter going backwards
    /// reports nothing.
    private var diskSampler = RateSampler(onCounterReset: .reportNothing)

    // Graph histories
    @Published var cpuHistory = GraphHistory(maxLength: 40)
    @Published var gpuHistory = GraphHistory(maxLength: 40)
    @Published var downloadHistory = GraphHistory(maxLength: 30)
    @Published var uploadHistory = GraphHistory(maxLength: 30)
    @Published var diskReadHistory = GraphHistory(maxLength: 30)
    @Published var diskWriteHistory = GraphHistory(maxLength: 30)

    private var refreshTimers: [String: Timer] = [:]
    private let settingsManager: SettingsManager
    private let readingQueue: DispatchQueue
    private let onRead: (WidgetRefreshSchedule.Reading) -> Void
    private let keyboardNotifications: NotificationCenter
    private let workspaceNotifications: NotificationCenter

    /// An interface that re-attaches counts from zero again, so the whole new reading is this
    /// interval's traffic.
    private var networkSampler = RateSampler(onCounterReset: .countWholeReading)

    // Storage volumes
    @Published private(set) var volumes: [StorageVolume] = []
    private var activeWidgets = Set<WidgetIdentifier>()

    private typealias Reading = WidgetRefreshSchedule.Reading
    // Versions and pending work are protected because workers finish after visibility changes.
    private let readingLock = NSLock()
    private let samplerLock = NSLock()
    private var activeReadings = Set<Reading>()
    private var versions: [Reading: UInt] = [:]
    private var pendingReadings: [Reading: UInt] = [:]
    private var queuedReadings = Set<Reading>()
    private var asyncReadings: [Reading: (version: UInt, task: Task<Void, Never>)] = [:]
    private var eventDrivenReadings = Set<Reading>()
    private var timerReadings: [String: [Reading]] = [:]
    private var keyboardObserver: NSObjectProtocol?
    private var storageObservers: [NSObjectProtocol] = []
    private var powerObserver: NSObjectProtocol?
    private var powerSource: CFRunLoopSource?
    private var powerContext: PowerContext?
    private let audioEvents: AudioPropertyEvents
    private let eventAudioDevice: ((Bool) -> AudioObjectID?)?
    typealias PowerSourceFactory = (IOPowerSourceCallbackType, UnsafeMutableRawPointer?) -> CFRunLoopSource?
    private let makePowerSource: PowerSourceFactory
    private struct AudioListener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var audioListeners: [Reading: [AudioListener]] = [:]
    private final class PowerContext {
        weak var service: SystemInfoService?
        let version: UInt
        init(_ service: SystemInfoService, version: UInt) {
            self.service = service
            self.version = version
        }
    }

    /// Cached host port to avoid Mach port leaks.
    /// Each call to mach_host_self() creates a new send right that must be
    /// manually deallocated. Caching it once avoids leaking ~2,700 ports/hour
    /// which would exhaust the per-task port limit after ~1.5 days, causing
    /// system-wide input freeze (keyboard/mouse unresponsive).
    private let hostPort: mach_port_t = mach_host_self()

    init(
        settingsManager: SettingsManager = .shared,
        audioEvents: AudioPropertyEvents = .live,
        eventAudioDevice: ((Bool) -> AudioObjectID?)? = nil,
        readingQueue: DispatchQueue = DispatchQueue.global(qos: .utility),
        onRead: @escaping (WidgetRefreshSchedule.Reading) -> Void = { _ in },
        makePowerSource: @escaping PowerSourceFactory = { callback, context in
            IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()
        },
        keyboardNotifications: NotificationCenter = DistributedNotificationCenter.default(),
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.settingsManager = settingsManager
        self.readingQueue = readingQueue
        self.onRead = onRead
        self.audioEvents = audioEvents
        self.eventAudioDevice = eventAudioDevice
        self.makePowerSource = makePowerSource
        self.keyboardNotifications = keyboardNotifications
        self.workspaceNotifications = workspaceNotifications
    }

    deinit {
        stop()
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    func start(widgets: Set<WidgetIdentifier>) {
        let next = WidgetRefreshSchedule.readings(for: widgets)
        readingLock.lock()
        let removed = activeReadings.subtracting(next)
        let added = next.subtracting(activeReadings)
        activeReadings = next
        for reading in removed.union(added) {
            versions[reading, default: 0] += 1
            pendingReadings.removeValue(forKey: reading)
            queuedReadings.remove(reading)
        }
        readingLock.unlock()
        activeWidgets = widgets
        for reading in removed {
            asyncReadings.removeValue(forKey: reading)?.task.cancel()
            removeObserver(for: reading)
        }
        // Restarting a counter sampler establishes a new baseline, not a rate across hidden time.
        samplerLock.lock()
        if added.contains(.cpu) { previousCPUTicks = nil }
        if added.contains(.networkStats) { networkSampler = RateSampler(onCounterReset: .countWholeReading) }
        if added.contains(.diskStats) { diskSampler = RateSampler(onCounterReset: .reportNothing) }
        samplerLock.unlock()
        for reading in added { installObserver(for: reading) }
        startTimers()
        for reading in added { collect(reading) }
    }

    func stop() {
        start(widgets: [])
    }

    func refresh() {
        for reading in WidgetRefreshSchedule.readings(for: activeWidgets) { collect(reading) }
    }

    private func isActive(_ reading: Reading) -> Bool {
        readingLock.lock()
        defer { readingLock.unlock() }
        return activeReadings.contains(reading)
    }

    private func version(of reading: Reading) -> UInt {
        readingLock.lock()
        defer { readingLock.unlock() }
        return versions[reading, default: 0]
    }

    private func isCurrent(_ reading: Reading, _ version: UInt) -> Bool {
        readingLock.lock()
        defer { readingLock.unlock() }
        return activeReadings.contains(reading) && versions[reading, default: 0] == version
    }

    private func beginReading(_ reading: Reading) -> UInt? {
        readingLock.lock()
        defer { readingLock.unlock() }
        guard activeReadings.contains(reading) else { return nil }
        if pendingReadings[reading] != nil {
            // An event racing publication needs one latest follow-up, not a lost state change.
            queuedReadings.insert(reading)
            return nil
        }
        let version = versions[reading, default: 0]
        pendingReadings[reading] = version
        return version
    }

    private func endReading(_ reading: Reading, _ version: UInt) {
        readingLock.lock()
        let current = activeReadings.contains(reading) && versions[reading, default: 0] == version
        var repeatReading = false
        if pendingReadings[reading] == version {
            pendingReadings.removeValue(forKey: reading)
            repeatReading = queuedReadings.remove(reading) != nil && current
        }
        readingLock.unlock()
        if asyncReadings[reading]?.version == version { asyncReadings.removeValue(forKey: reading) }
        if repeatReading { collect(reading) }
    }

    private func read<Value>(
        _ reading: Reading, work: @escaping (UInt) -> Value, publish: @escaping (Value) -> Void
    ) {
        guard let version = beginReading(reading) else { return }
        readingQueue.async { [weak self] in
            guard let self else { return }
            guard self.isCurrent(reading, version) else { return }
            self.onRead(reading)
            let value = work(version)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.endReading(reading, version) }
                guard self.isCurrent(reading, version) else { return }
                publish(value)
            }
        }
    }

    private func readAsync<Value>(
        _ reading: Reading, work: @escaping (UInt) async -> Value, publish: @escaping (Value) -> Void
    ) {
        guard let version = beginReading(reading) else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endReading(reading, version) }
            guard !Task.isCancelled, self.isCurrent(reading, version) else { return }
            self.onRead(reading)
            let value = await work(version)
            guard !Task.isCancelled, self.isCurrent(reading, version) else { return }
            publish(value)
        }
        asyncReadings[reading] = (version, task)
    }

    private func collect(_ reading: WidgetRefreshSchedule.Reading) {
        switch reading {
        case .battery: refreshBattery()
        case .caffeinate: refreshCaffeinate()
        case .cpu: refreshCPU()
        case .memory: refreshMemory()
        case .gpu: refreshGPU()
        case .networkStats: refreshNetworkStats()
        case .diskStats: refreshDiskStats()
        case .volume: refreshVolume()
        case .mic: refreshMic()
        case .keyboard: refreshKeyboard()
        case .storageVolumes: refreshVolumes()
        }
    }

    func refreshBattery() {
        read(.battery, work: { _ in self.getBatteryInfo() }) { info in
            if self.batteryInfo != info { self.batteryInfo = info }
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
        read(.cpu, work: { version in self.getCPUUsage(version: version) }) { usage in
            if self.cpuUsage != usage { self.cpuUsage = usage }
            self.cpuHistory.add(usage)
        }
    }

    private func getCPUUsage(version: UInt) -> Double {
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

        samplerLock.lock()
        let usage: Double
        if isCurrent(.cpu, version) {
            usage = CPUTicks.usage(previous: previousCPUTicks, current: ticks) ?? 0
            previousCPUTicks = ticks
        } else { usage = 0 }
        samplerLock.unlock()

        // Deallocate the cpuInfo buffer
        let cpuInfoSize = Int(numCPU) * MemoryLayout<integer_t>.stride
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfoPtr), vm_size_t(cpuInfoSize))

        return usage
    }

    func refreshMemory() {
        read(.memory, work: { _ in self.getMemoryUsage() }) { usage in
            if self.memoryPressure != usage { self.memoryPressure = usage }
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

        // The page size cancels out of the ratio, so the raw counts are enough.
        return MemoryPressure.percentage(
            MemoryPressure.Pages(
                active: UInt64(stats.active_count),
                wired: UInt64(stats.wire_count),
                compressed: UInt64(stats.compressor_page_count),
                free: UInt64(stats.free_count),
                inactive: UInt64(stats.inactive_count)))
    }

    func refreshGPU() {
        readAsync(.gpu, work: { _ in await self.getGPUUsage() }) { usage in
            if self.gpuUsage != usage { self.gpuUsage = usage }
            self.gpuHistory.add(usage)
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
        readAsync(.networkStats, work: { version in await self.getNetworkStats(version: version) }) { stats in
            if self.networkStats != stats { self.networkStats = stats }
            self.downloadHistory.add(Double(stats.download))
            self.uploadHistory.add(Double(stats.upload))
        }
    }

    /// Get network statistics - uses shell command fallback for M4 compatibility
    private func getNetworkStats(version: UInt) async -> NetworkStats {
        // Try native approach first
        if let stats = getNetworkStatsNative(version: version) {
            return stats
        }
        
        // Fallback to netstat command for M4 Macs where native approach may fail
        return await getNetworkStatsViaNetstat(version: version)
    }

    private func calculateNetworkStats(rxBytes: UInt64, txBytes: UInt64, version: UInt) -> NetworkStats {
        samplerLock.lock()
        defer { samplerLock.unlock() }
        guard isCurrent(.networkStats, version), !Task.isCancelled else { return NetworkStats() }
        let rates = networkSampler.sample(inbound: rxBytes, outbound: txBytes)
        return NetworkStats(download: rates.inbound, upload: rates.outbound)
    }

    /// Native sysctl-based network statistics (primary method)
    private func getNetworkStatsNative(version: UInt) -> NetworkStats? {
        var rxBytes: UInt64 = 0
        var txBytes: UInt64 = 0
        var foundValidInterface = false
        
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
                    
                    if NetworkInterfaces.isValidDataInterface(ifName) {
                        foundValidInterface = true
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
        
        if !foundValidInterface {
            print("[NetworkStats] No valid interfaces found via sysctl, falling back to netstat")
            return nil
        }

        return calculateNetworkStats(rxBytes: rxBytes, txBytes: txBytes, version: version)
    }
    
    /// Fallback method using netstat command
    private func getNetworkStatsViaNetstat(version: UInt) async -> NetworkStats {
        do {
            // Get interface stats using netstat
            let output = try await ShellExecutor.run("netstat -ibn | awk 'NR>1 && $1 !~ /lo/ {print $1,$7,$10}'")
            
            let totals = NetstatParser.totals(output)
            return calculateNetworkStats(rxBytes: totals.received, txBytes: totals.sent, version: version)
            
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

    func refreshDiskStats() {
        readAsync(.diskStats, work: { version in await self.getDiskStats(version: version) }) { stats in
            if self.diskStats != stats { self.diskStats = stats }
            self.diskReadHistory.add(Double(stats.read))
            self.diskWriteHistory.add(Double(stats.write))
        }
    }

    /// Get disk I/O statistics using IOKit (IOBlockStorageDriver)
    private func getDiskStats(version: UInt) async -> DiskIOStats {
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
        
        return samplerLock.withLock {
            guard isCurrent(.diskStats, version), !Task.isCancelled else { return DiskIOStats() }
            let rates = diskSampler.sample(inbound: readBytes, outbound: writeBytes)
            return DiskIOStats(read: rates.inbound, write: rates.outbound)
        }
    }

    private enum AudioDeviceKind {
        case output
        case input

        var selector: AudioObjectPropertySelector {
            switch self {
            case .output:
                return kAudioHardwarePropertyDefaultOutputDevice
            case .input:
                return kAudioHardwarePropertyDefaultInputDevice
            }
        }
    }

    private func defaultAudioDeviceID(for kind: AudioDeviceKind) -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kind.selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        ) == noErr else {
            return nil
        }

        return deviceID
    }

    private func audioDeviceName(for deviceID: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceName: CFString? = nil
        var propertySize = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &deviceName) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &propertySize,
                pointer
            )
        }

        guard status == noErr else {
            return nil
        }

        return deviceName as String?
    }

    func refreshVolume() {
        read(.volume, work: { _ in (self.getSystemVolume(), self.isSystemMuted(), self.getAudioOutputDeviceName()) }) { volume, muted, name in
            if self.volumeLevel != volume { self.volumeLevel = volume }
            if self.isMuted != muted { self.isMuted = muted }
            if self.audioOutputDeviceName != name { self.audioOutputDeviceName = name }
        }
    }

    /// Set system output volume (0.0 - 1.0) using CoreAudio and update published state. Best-effort, robust for all macOS devices.
    @discardableResult
    func setSystemVolume(_ level: Float) -> Bool {
        let clampedValue = min(max(level, 0.0), 1.0)
        var didSet = false
        DispatchQueue.global(qos: .userInitiated).async {
            guard let deviceID = self.defaultAudioDeviceID(for: .output) else {
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
                      AudioObjectIsPropertySettable(deviceID, &volumeAddress, &isSettable) == noErr,
                      isSettable != false,
                      AudioObjectSetPropertyData(
                          deviceID,
                          &volumeAddress,
                          0,
                          nil,
                          propertySize,
                          &volume
                      ) == noErr
                else {
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
                    self.refreshVolume()
                }
            }
        }
        return didSet
    }

    /// Set system output mute state using CoreAudio and update published state.
    func setSystemMuted(_ muted: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let defaultOutputDeviceID = self.defaultAudioDeviceID(for: .output) else { return }

            var mutedValue: UInt32 = muted ? 1 : 0
            let propertySize = UInt32(MemoryLayout<UInt32>.size)

            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectSetPropertyData(defaultOutputDeviceID, &propertyAddress, 0, nil, propertySize, &mutedValue)

            DispatchQueue.main.async {
                self.refreshVolume()
            }
        }
    }

    private func getSystemVolume() -> Float {
        // Robust, production-safe macOS output volume retrieval
        guard let deviceID = defaultAudioDeviceID(for: .output) else {
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
        guard let defaultOutputDeviceID = defaultAudioDeviceID(for: .output) else { return false }

        var muted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        var propertyAddress = AudioObjectPropertyAddress(
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
    
    private func getAudioOutputDeviceName() -> String {
        guard let defaultOutputDeviceID = defaultAudioDeviceID(for: .output) else { return "Unknown" }
        return audioDeviceName(for: defaultOutputDeviceID) ?? "Unknown"
    }

    func refreshMic() {
        read(.mic, work: { _ in (self.getMicLevel(), self.checkIfMicMuted(), self.getAudioInputDeviceName()) }) { level, muted, name in
            if self.micLevel != level { self.micLevel = level }
            if self.isMicMuted != muted { self.isMicMuted = muted }
            if self.audioInputDeviceName != name { self.audioInputDeviceName = name }
        }
    }

    private func getMicLevel() -> Float {
        guard let defaultInputDeviceID = defaultAudioDeviceID(for: .input) else { return 0 }

        var volume: Float32 = 0
        var propertySize = UInt32(MemoryLayout<Float32>.size)

        var propertyAddress = AudioObjectPropertyAddress(
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
        guard let defaultInputDeviceID = defaultAudioDeviceID(for: .input) else { return false }

        var muted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        var propertyAddress = AudioObjectPropertyAddress(
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
    
    private func getAudioInputDeviceName() -> String {
        guard let defaultInputDeviceID = defaultAudioDeviceID(for: .input) else { return "Unknown" }
        return audioDeviceName(for: defaultInputDeviceID) ?? "Unknown"
    }

    /// Set microphone input level (0.0 - 1.0) using CoreAudio and update published state.
    @discardableResult
    func setMicLevel(_ level: Float) -> Bool {
        let clampedValue = min(max(level, 0.0), 1.0)
        var didSet = false
        DispatchQueue.global(qos: .userInitiated).async {
            guard let deviceID = self.defaultAudioDeviceID(for: .input) else {
                return
            }

            var volume = clampedValue
            let propertySize = UInt32(MemoryLayout<Float32>.size)
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var isSettable: DarwinBoolean = false
            guard AudioObjectHasProperty(deviceID, &volumeAddress),
                  AudioObjectIsPropertySettable(deviceID, &volumeAddress, &isSettable) == noErr,
                  isSettable != false,
                  AudioObjectSetPropertyData(
                      deviceID,
                      &volumeAddress,
                      0,
                      nil,
                      propertySize,
                      &volume
                  ) == noErr
            else {
                return
            }

            didSet = true

            if didSet {
                DispatchQueue.main.async {
                    self.refreshMic()
                }
            }
        }
        return didSet
    }

    /// Set microphone mute state using CoreAudio and update published state.
    func setMicMuted(_ muted: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let defaultInputDeviceID = self.defaultAudioDeviceID(for: .input) else { return }

            var mutedValue: UInt32 = muted ? 1 : 0
            let propertySize = UInt32(MemoryLayout<UInt32>.size)

            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectSetPropertyData(
                defaultInputDeviceID, &propertyAddress, 0, nil, propertySize, &mutedValue)

            DispatchQueue.main.async {
                self.refreshMic()
            }
        }
    }

    func refreshKeyboard() {
        // TIS belongs to the main run loop; only publication is deferred.
        guard let version = beginReading(.keyboard) else { return }
        onRead(.keyboard)
        let layout = getCurrentKeyboardLayout()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.endReading(.keyboard, version) }
            guard self.isCurrent(.keyboard, version) else { return }
            if self.keyboardLayout != layout { self.keyboardLayout = layout }
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

    func refreshCaffeinate() {
        guard isActive(.caffeinate) else { return }
        let managedActive = caffeinateProcess?.isRunning ?? false
        read(.caffeinate, work: { _ in
            managedActive || self.isAnyCaffeinateRunning()
        }) { active in
            if self.isCaffeinateActive != active { self.isCaffeinateActive = active }
        }
    }

    func toggleCaffeinate(option: String = "") {
        if isCaffeinateActive {
            caffeinateProcess?.terminate()
            caffeinateProcess = nil
            caffeinateProcessKeepAlive = nil
            killAllCaffeinateProcesses()
            DispatchQueue.main.async {
                self.isCaffeinateActive = false
            }
        } else {
            // Ensure no other caffeinate instances are running first
            killAllCaffeinateProcesses()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            process.arguments = CaffeinateOptions.arguments(for: option)
            // Attach pipes so the process has valid output targets (avoid unexpected behavior)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.qualityOfService = .userInitiated

            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isCaffeinateActive = false
                }
            }

            // Retain the process before running to avoid it being deallocated
            caffeinateProcess = process
            caffeinateProcessKeepAlive = process

            do {
                try process.run()
                DispatchQueue.main.async {
                    // Reflect actual running state immediately so the UI updates right away
                    self.isCaffeinateActive = process.isRunning
                }
            } catch {
                caffeinateProcess = nil
                caffeinateProcessKeepAlive = nil
                DispatchQueue.main.async {
                    self.isCaffeinateActive = false
                }
            }
        }

        // Refresh state asynchronously (keeps external checks in sync)
        refreshCaffeinate()
    }

    private func killAllCaffeinateProcesses() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["caffeinate"]
        // We run synchronously and wait so we don't race with a subsequently
        // launched `caffeinate` process which could otherwise be killed.
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // pkill may fail if no caffeinate is running; that's fine.
        }
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
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func startTimers() {
        let timers = WidgetRefreshSchedule.timers(for: activeWidgets, in: settingsManager.settings.widgets)
        var wanted = Set<String>()
        for timer in timers {
            let readings = WidgetRefreshSchedule.readings(for: timer.widget).filter {
                // Mount notifications cannot describe capacity changes; caffeinate may be external.
                $0 == .storageVolumes || $0 == .caffeinate || !eventDrivenReadings.contains($0)
            }
            guard !readings.isEmpty else { continue }
            wanted.insert(timer.id)
            if refreshTimers[timer.id]?.timeInterval == timer.interval,
               timerReadings[timer.id] == readings { continue }
            refreshTimers[timer.id]?.invalidate()
            timerReadings[timer.id] = readings
            let id = timer.id
            let scheduled = Timer(timeInterval: timer.interval, repeats: true) { [weak self] timer in
                guard let self, self.refreshTimers[id] === timer else { return }
                for reading in readings { self.collect(reading) }
            }
            refreshTimers[timer.id] = scheduled
            RunLoop.main.add(scheduled, forMode: .common)
        }
        for id in Array(refreshTimers.keys) where !wanted.contains(id) {
            refreshTimers.removeValue(forKey: id)?.invalidate()
            timerReadings.removeValue(forKey: id)
        }
    }

    private func refreshVolumes() {
        read(.storageVolumes, work: { _ in
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
                return StorageVolume(
                    name: name,
                    url: url,
                    totalBytes: total,
                    usedBytes: total - available
                )
            }
            return volumes
        }) { volumes in
            if self.volumes != volumes { self.volumes = volumes }
        }
    }

    private func installObserver(for reading: Reading) {
        let generation = version(of: reading)
        switch reading {
        case .keyboard:
            keyboardObserver = keyboardNotifications.addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.isCurrent(.keyboard, generation) else { return }
                self.refreshKeyboard()
            }
            eventDrivenReadings.insert(.keyboard)
        case .storageVolumes:
            let center = workspaceNotifications
            storageObservers = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    guard let self, self.isCurrent(.storageVolumes, generation) else { return }
                    self.refreshVolumes()
                }
            }
        case .battery:
            let context = PowerContext(self, version: generation)
            powerContext = context
            powerSource = makePowerSource({ pointer in
                guard let pointer else { return }
                let context = Unmanaged<PowerContext>.fromOpaque(pointer).takeUnretainedValue()
                // The source is attached to the main loop; capture its context before queuing.
                DispatchQueue.main.async {
                    guard let service = context.service, service.isCurrent(.battery, context.version) else { return }
                    service.refreshBattery()
                }
            }, Unmanaged.passUnretained(context).toOpaque())
            if let powerSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes)
                eventDrivenReadings.insert(.battery)
            }
            powerObserver = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.isCurrent(.battery, generation) else { return }
                self.refreshBattery()
            }
        case .volume, .mic:
            installAudioObservers(for: reading)
        default: break
        }
    }

    private func removeObserver(for reading: Reading) {
        eventDrivenReadings.remove(reading)
        switch reading {
        case .keyboard:
            if let keyboardObserver { keyboardNotifications.removeObserver(keyboardObserver) }
            keyboardObserver = nil
        case .storageVolumes:
            for observer in storageObservers { workspaceNotifications.removeObserver(observer) }
            storageObservers.removeAll()
        case .battery:
            if let powerSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
                CFRunLoopSourceInvalidate(powerSource)
            }
            powerSource = nil
            powerContext = nil
            if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
            powerObserver = nil
        case .volume, .mic:
            for listener in audioListeners.removeValue(forKey: reading) ?? [] {
                audioEvents.remove(listener.object, listener.address, listener.block)
            }
        default: break
        }
    }

    private func installAudioObservers(for reading: Reading) {
        let generation = version(of: reading)
        let input = reading == .mic
        let kind: AudioDeviceKind = input ? .input : .output
        let systemAddress = AudioObjectPropertyAddress(
            mSelector: kind.selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var complete = true
        func observe(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, rebind: Bool = false) {
            let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.isCurrent(reading, generation) else { return }
                if rebind {
                    // Old-device callbacks must not read or publish after the new binding starts.
                    self.readingLock.lock()
                    self.versions[reading, default: 0] += 1
                    self.pendingReadings.removeValue(forKey: reading)
                    self.queuedReadings.remove(reading)
                    self.readingLock.unlock()
                    self.removeObserver(for: reading)
                    self.installAudioObservers(for: reading)
                    self.startTimers()
                }
                self.collect(reading)
            }
            if audioEvents.add(object, address, callback) == noErr {
                audioListeners[reading, default: []].append(AudioListener(object: object, address: address, block: callback))
            } else { complete = false }
        }
        observe(AudioObjectID(kAudioObjectSystemObject), systemAddress, rebind: true)
        let device = eventAudioDevice.map { $0(input) } ?? defaultAudioDeviceID(for: kind)
        guard let device, device != AudioObjectID(kAudioObjectUnknown) else { return }
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        var addresses = [AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain), AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: kAudioObjectPropertyElementMain)]
        let master = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        addresses.append(master)
        if !input {
            // The getter also falls back when an advertised master property fails to read.
            addresses += [1, 2].map { AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: $0) }
        }
        // Unsupported properties are the reader's constant fallback values. Observe every
        // supported property; polling is useful only when an available listener failed.
        for address in addresses where audioEvents.hasProperty(device, address) { observe(device, address) }
        if complete { eventDrivenReadings.insert(reading) }
    }
}
