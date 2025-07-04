import Foundation
import Combine

class RetryManager: ObservableObject {
    static let shared = RetryManager()
    
    @Published var activeRetries: [UUID: RetryInfo] = [:]
    @Published var retryStatistics = RetryStatistics()
    
    // Thread-safe timer management
    private var retryTimers: [UUID: Timer] = [:]
    private let timersQueue = DispatchQueue(label: "retry.timers", attributes: .concurrent)
    private let statisticsQueue = DispatchQueue(label: "retry.statistics")
    
    struct RetryInfo {
        let segmentId: UUID
        let currentAttempt: Int
        let nextRetryTime: Date
        let lastError: String
        let service: TranscriptionService
        
        var delay: TimeInterval {
            let baseDelay = TranscriptionConstants.baseRetryDelay
            let multiplier = pow(TranscriptionConstants.retryMultiplier, Double(currentAttempt - 1))
            return min(baseDelay * multiplier, TranscriptionConstants.maxRetryDelay)
        }
    }
    
    struct RetryStatistics {
        var totalRetries = 0
        var successfulRetries = 0
        var permanentFailures = 0
        var averageRetriesBeforeSuccess: Double = 0
        
        var successRate: Double {
            guard totalRetries > 0 else { return 0 }
            return Double(successfulRetries) / Double(totalRetries)
        }
    }
    
    private init() {
        Logger.shared.info("RetryManager initialized")
    }
    
    deinit {
        cancelAllRetries()
    }
    
    // MARK: - Public Interface
    
    func scheduleRetry(for segment: TranscriptionSegment, completion: @escaping (TranscriptionSegment) -> Void) {
        // Validate retry eligibility first
        guard segment.needsRetry else {
            Logger.shared.warning("Segment \(segment.segmentIndex) does not need retry (count: \(segment.retryCount), permanent: \(segment.isPermanentFailure))")
            return
        }
        
        // Validate segment ID
        guard segment.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            Logger.shared.error("Invalid segment ID detected, skipping retry")
            return
        }
        
        // Check if we're already retrying this segment
        if activeRetries[segment.id] != nil {
            Logger.shared.warning("Retry already scheduled for segment \(segment.segmentIndex), skipping duplicate")
            return
        }
        
        let retryDelay = calculateRetryDelay(for: segment)
        let nextRetryTime = Date().addingTimeInterval(retryDelay)
        
        let retryInfo = RetryInfo(
            segmentId: segment.id,
            currentAttempt: segment.retryCount + 1,
            nextRetryTime: nextRetryTime,
            lastError: segment.errorMessage ?? "Unknown error",
            service: segment.service
        )
        
        Logger.shared.info("Scheduling retry for segment \(segment.segmentIndex) (ID: \(segment.id.uuidString.prefix(8))) in \(String(format: "%.2f", retryDelay)) seconds (attempt \(retryInfo.currentAttempt)/\(TranscriptionConstants.maxRetryAttempts))")
        
        // Update active retries on main queue
        DispatchQueue.main.async { [weak self] in
            self?.activeRetries[segment.id] = retryInfo
        }
        
        // Update statistics
        statisticsQueue.async { [weak self] in
            self?.retryStatistics.totalRetries += 1
            
            // Update published statistics on main queue
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
        
        // Schedule timer safely
        scheduleTimerSafely(for: segment, delay: retryDelay, completion: completion)
    }
    
    func cancelRetry(for segmentId: UUID) {
        Logger.shared.info("Cancelling retry for segment: \(segmentId.uuidString.prefix(8))")
        
        // Cancel timer safely
        timersQueue.async(flags: .barrier) { [weak self] in
            if let timer = self?.retryTimers[segmentId] {
                timer.invalidate()
                self?.retryTimers.removeValue(forKey: segmentId)
            }
        }
        
        // Remove from active retries on main queue
        DispatchQueue.main.async { [weak self] in
            self?.activeRetries.removeValue(forKey: segmentId)
        }
    }
    
    func markRetrySuccessful(for segmentId: UUID) {
        Logger.shared.info("Marking retry successful for segment: \(segmentId.uuidString.prefix(8))")
        
        let wasActive = activeRetries[segmentId] != nil
        
        if wasActive {
            statisticsQueue.async { [weak self] in
                self?.retryStatistics.successfulRetries += 1
                self?.updateAverageRetries()
                
                // Update published statistics on main queue
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
        }
        
        cancelRetry(for: segmentId)
    }
    
    func markRetryPermanentlyFailed(for segmentId: UUID) {
        Logger.shared.info("Marking retry permanently failed for segment: \(segmentId.uuidString.prefix(8))")
        
        let wasActive = activeRetries[segmentId] != nil
        
        if wasActive {
            statisticsQueue.async { [weak self] in
                self?.retryStatistics.permanentFailures += 1
                
                // Update published statistics on main queue
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
        }
        
        cancelRetry(for: segmentId)
    }
    
    func cancelAllRetries() {
        Logger.shared.info("Cancelling all active retries")
        
        // Cancel all timers safely
        timersQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            for (_, timer) in self.retryTimers {
                timer.invalidate()
            }
            self.retryTimers.removeAll()
        }
        
        // Clear active retries on main queue
        DispatchQueue.main.async { [weak self] in
            self?.activeRetries.removeAll()
        }
    }
    
    // MARK: - Private Implementation
    
    private func scheduleTimerSafely(for segment: TranscriptionSegment, delay: TimeInterval, completion: @escaping (TranscriptionSegment) -> Void) {
        // Create timer on main queue (Timer requirement)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.executeRetry(for: segment, completion: completion)
            }
            
            // Store timer safely
            self.timersQueue.async(flags: .barrier) {
                self.retryTimers[segment.id] = timer
            }
        }
    }
    
    private func calculateRetryDelay(for segment: TranscriptionSegment) -> TimeInterval {
        let attempt = max(1, segment.retryCount + 1) // Ensure minimum of 1
        let baseDelay = TranscriptionConstants.baseRetryDelay
        let multiplier = pow(TranscriptionConstants.retryMultiplier, Double(attempt - 1))
        
        // Add jitter to prevent thundering herd
        let jitter = Double.random(in: 0.8...1.2)
        let delay = baseDelay * multiplier * jitter
        
        return min(max(delay, 1.0), TranscriptionConstants.maxRetryDelay) // Minimum 1 second
    }
    
    private func executeRetry(for segment: TranscriptionSegment, completion: @escaping (TranscriptionSegment) -> Void) {
        Logger.shared.info("Executing retry for segment \(segment.segmentIndex) (ID: \(segment.id.uuidString.prefix(8)))")
        
        var retrySegment = segment
        retrySegment.status = .pending
        retrySegment.errorMessage = nil
        
        // Clean up timer reference
        timersQueue.async(flags: .barrier) { [weak self] in
            self?.retryTimers.removeValue(forKey: segment.id)
        }
        
        // Remove from active retries
        DispatchQueue.main.async { [weak self] in
            self?.activeRetries.removeValue(forKey: segment.id)
        }
        
        // Execute completion on a background queue to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async {
            completion(retrySegment)
        }
    }
    
    private func updateAverageRetries() {
        guard retryStatistics.successfulRetries > 0 else { return }
        
        // This is a simplified calculation - in practice, you'd track more detailed statistics
        retryStatistics.averageRetriesBeforeSuccess = Double(retryStatistics.totalRetries) / Double(retryStatistics.successfulRetries)
    }
    
    // MARK: - Analytics
    
    func getRetryAnalytics() -> [String: Any] {
        return statisticsQueue.sync {
            return [
                "totalRetries": retryStatistics.totalRetries,
                "successfulRetries": retryStatistics.successfulRetries,
                "permanentFailures": retryStatistics.permanentFailures,
                "successRate": retryStatistics.successRate,
                "averageRetriesBeforeSuccess": retryStatistics.averageRetriesBeforeSuccess,
                "activeRetries": activeRetries.count
            ]
        }
    }
    
    func resetStatistics() {
        statisticsQueue.async { [weak self] in
            self?.retryStatistics = RetryStatistics()
            
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Debug Methods
    
    func getActiveTimerCount() -> Int {
        return timersQueue.sync {
            return retryTimers.count
        }
    }
    
    func debugPrintState() {
        Logger.shared.info("RetryManager State:")
        Logger.shared.info("- Active retries: \(activeRetries.count)")
        Logger.shared.info("- Active timers: \(getActiveTimerCount())")
        Logger.shared.info("- Total retries: \(retryStatistics.totalRetries)")
        Logger.shared.info("- Successful retries: \(retryStatistics.successfulRetries)")
        Logger.shared.info("- Permanent failures: \(retryStatistics.permanentFailures)")
    }
}
