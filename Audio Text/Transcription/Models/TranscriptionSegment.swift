import Foundation

struct TranscriptionSegment: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let segmentIndex: Int
    let startTime: TimeInterval
    var endTime: TimeInterval
    var audioFileURL: URL?
    var transcriptionText: String?
    var confidence: Float?
    var status: TranscriptionStatus
    var service: TranscriptionService
    var createdAt: Date
    var transcribedAt: Date?
    var retryCount: Int
    var errorMessage: String?
    
    init(sessionId: UUID, segmentIndex: Int, startTime: TimeInterval, endTime: TimeInterval, audioFileURL: URL? = nil) {
        self.id = UUID()
        self.sessionId = sessionId
        self.segmentIndex = segmentIndex
        self.startTime = startTime
        self.endTime = endTime
        self.audioFileURL = audioFileURL
        self.status = .pending
        self.service = .none
        self.createdAt = Date()
        self.retryCount = 0
    }
    
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    var formattedTimeRange: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        let start = formatter.string(from: startTime) ?? "0:00"
        let end = formatter.string(from: endTime) ?? "0:00"
        return "\(start) - \(end)"
    }
    
    var isTranscribed: Bool {
        return status == .completed && transcriptionText != nil
    }
    
    var needsRetry: Bool {
        return status == .failed && retryCount < TranscriptionConstants.maxRetryAttempts
    }
    
    mutating func markAsProcessing(with service: TranscriptionService) {
        self.status = .processing
        self.service = service
    }
    
    mutating func markAsCompleted(text: String, confidence: Float? = nil, service: TranscriptionService) {
        self.status = .completed
        self.transcriptionText = text
        self.confidence = confidence
        self.service = service
        self.transcribedAt = Date()
        self.errorMessage = nil
    }
    
    mutating func markAsFailed(error: String, service: TranscriptionService) {
        self.status = .failed
        self.errorMessage = error
        self.service = service
        self.retryCount += 1
    }
    
    mutating func markAsQueued() {
        self.status = .queued
    }
}
