import Foundation
import Combine

class RetryManager: ObservableObject {
    static let shared = RetryManager()
    
    @Published var activeRetries: [UUID: RetryInfo] = [:]
    @Published var retryStatistics = RetryStatistics()
    
    private var retryTimers: [UUID: Timer] = [:]
    private let retryQueue = DispatchQueue(label: "retry.manager", qos: .utility)
    
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
    
    private init() {}
    
    // MARK: - Public Interface
    
    func scheduleRetry(for segment: TranscriptionSegment, completion: @escaping (TranscriptionSegment) -> Void) {
        guard segment.needsRetry else {
            Logger.shared.warning("Segment \(segment.segmentIndex) does not need retry")
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
        
        activeRetries[segment.id] = retryInfo
        
        Logger.shared.info("Scheduling retry for segment \(segment.segmentIndex) in \(retryDelay) seconds")
        
        // Schedule timer for retry
        let timer = Timer.scheduledTimer(withTimeInterval: retryDelay, repeats: false) { [weak self] _ in
            self?.executeRetry(for: segment, completion: completion)
        }
        
        retryTimers[segment.id] = timer
        retryStatistics.totalRetries += 1
    }
    
    func cancelRetry(for segmentId: UUID) {
        Logger.shared.info("Cancelling retry for segment: \(segmentId)")
        
        retryTimers[segmentId]?.invalidate()
        retryTimers.removeValue(forKey: segmentId)
        activeRetries.removeValue(forKey: segmentId)
    }
    
    func markRetrySuccessful(for segmentId: UUID) {
        if activeRetries[segmentId] != nil {
            retryStatistics.successfulRetries += 1
            updateAverageRetries()
        }
        
        cancelRetry(for: segmentId)
    }
    
    func markRetryPermanentlyFailed(for segmentId: UUID) {
        if activeRetries[segmentId] != nil {
            retryStatistics.permanentFailures += 1
        }
        
        cancelRetry(for: segmentId)
    }
    
    // MARK: - Private Implementation
    
    private func calculateRetryDelay(for segment: TranscriptionSegment) -> TimeInterval {
        let attempt = segment.retryCount + 1
        let baseDelay = TranscriptionConstants.baseRetryDelay
        let multiplier = pow(TranscriptionConstants.retryMultiplier, Double(attempt - 1))
        
        // Add jitter to prevent thundering herd
        let jitter = Double.random(in: 0.8...1.2)
        let delay = baseDelay * multiplier * jitter
        
        return min(delay, TranscriptionConstants.maxRetryDelay)
    }
    
    private func executeRetry(for segment: TranscriptionSegment, completion: @escaping (TranscriptionSegment) -> Void) {
        Logger.shared.info("Executing retry for segment \(segment.segmentIndex)")
        
        var retrySegment = segment
        retrySegment.status = .pending
        retrySegment.errorMessage = nil
        
        // Remove from active retries since we're processing now
        activeRetries.removeValue(forKey: segment.id)
        retryTimers.removeValue(forKey: segment.id)
        
        completion(retrySegment)
    }
    
    private func updateAverageRetries() {
        guard retryStatistics.successfulRetries > 0 else { return }
        
        // This is a simplified calculation - in practice, you'd track more detailed statistics
        retryStatistics.averageRetriesBeforeSuccess = Double(retryStatistics.totalRetries) / Double(retryStatistics.successfulRetries)
    }
    
    // MARK: - Analytics
    
    func getRetryAnalytics() -> [String: Any] {
        return [
            "totalRetries": retryStatistics.totalRetries,
            "successfulRetries": retryStatistics.successfulRetries,
            "permanentFailures": retryStatistics.permanentFailures,
            "successRate": retryStatistics.successRate,
            "averageRetriesBeforeSuccess": retryStatistics.averageRetriesBeforeSuccess,
            "activeRetries": activeRetries.count
        ]
    }
    
    func resetStatistics() {
        retryStatistics = RetryStatistics()
    }
}
