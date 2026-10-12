import Foundation
import Combine

/// Polls one network source on behalf of every bar that shows it.
///
/// Owns one in-flight request and one refresh timer, so a widget mounted on several displays
/// never duplicates either, and a view re-render can never reset the schedule. A changed input
/// invalidates the old result before the latest input is queued; a failed refresh keeps the
/// last successful value. Sources without a setting to load from pass an empty input.
@MainActor
final class PollingModel<Value: Equatable>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var isRefreshing = false
    var isLoading: Bool { value == nil && isRefreshing }

    private let load: (String) async throws -> Value
    private var task: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var input: String?
    private var generation = 0
    private var isActive = false
    private var hasQueuedRefresh = false

    init(load: @escaping (String) async throws -> Value) {
        self.load = load
    }

    /// The app owns visibility; all mounted copies share this one polling schedule.
    func start(input: String, refreshInterval: TimeInterval) {
        let next = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRefresh = refreshTimer == nil || self.input != next
        if refreshTimer?.timeInterval != refreshInterval {
            refreshTimer?.invalidate()
            let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] timer in
                Task { @MainActor [weak self] in
                    // A queued tick from a replaced or stopped timer must not restart polling.
                    guard let self, self.refreshTimer === timer, let input = self.input else { return }
                    self.refresh(input: input)
                }
            }
            refreshTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        if shouldRefresh { refresh(input: next) }
    }

    func refresh(input: String) {
        let next = input.trimmingCharacters(in: .whitespacesAndNewlines)
        isActive = true
        if self.input != next {
            self.input = next
            generation += 1
            value = nil
            errorMessage = nil
            lastSuccess = nil
            task?.cancel()
        }
        if let task {
            // A CLI may ignore cancellation. Wait for it before starting the latest input.
            if task.isCancelled { hasQueuedRefresh = true }
            return
        }
        startRequest(next)
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isActive = false
        hasQueuedRefresh = false
        generation += 1
        task?.cancel()
        isRefreshing = false
    }

    private func startRequest(_ input: String) {
        let version = generation
        let load = load
        isRefreshing = true
        task = Task { [weak self] in
            let result: Result<Value, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await load(input))
            }
            catch { result = .failure(error) }
            self?.finish(result, generation: version)
        }
    }

    private func finish(_ result: Result<Value, Error>, generation version: Int) {
        task = nil
        isRefreshing = false
        if isActive && version == generation {
            switch result {
            case .success(let value):
                if self.value != value { self.value = value }
                errorMessage = nil
                lastSuccess = Date()
            case .failure(let error):
                if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
        if isActive && hasQueuedRefresh, let input {
            hasQueuedRefresh = false
            startRequest(input)
        }
    }
}
