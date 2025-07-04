import Foundation

struct TranscriptionJob: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    var segments: [TranscriptionSegment]
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var totalSegments: Int
    var preferredService: TranscriptionService
    var allowFallback: Bool
    
    init(sessionId: UUID, preferredService: TranscriptionService = .openai, allowFallback: Bool = true) {
        self.id = UUID()
        self.sessionId = sessionId
        self.segments = []
        self.createdAt = Date()
        self.totalSegments = 0
        self.preferredService = preferredService
        self.allowFallback = allowFallback
    }
    
    var completedSegments: Int {
        return segments.filter { $0.status == .completed }.count
    }
    
    var failedSegments: Int {
        return segments.filter { $0.status == .failed }.count
    }
    
    var pendingSegments: Int {
        return segments.filter { $0.status == .pending || $0.status == .queued }.count
    }
    
    var processingSegments: Int {
        return segments.filter { $0.status == .processing }.count
    }
    
    var progress: Float {
        guard totalSegments > 0 else { return 0 }
        return Float(completedSegments) / Float(totalSegments)
    }
    
    var isCompleted: Bool {
        return completedSegments == totalSegments && pendingSegments == 0 && processingSegments == 0
    }
    
    var hasFailures: Bool {
        return failedSegments > 0
    }
    
    var status: TranscriptionJobStatus {
        if isCompleted {
            return hasFailures ? .completedWithErrors : .completed
        } else if processingSegments > 0 || pendingSegments > 0 {
            return .processing
        } else if segments.isEmpty {
            return .pending
        } else {
            return .failed
        }
    }
    
    var fullTranscriptionText: String {
        return segments
            .sorted { $0.segmentIndex < $1.segmentIndex }
            .compactMap { $0.transcriptionText }
            .joined(separator: " ")
    }
    
    var estimatedCompletionTime: TimeInterval {
        let remainingSegments = pendingSegments + processingSegments
        return TimeInterval(remainingSegments) * preferredService.estimatedProcessingTime
    }
    
    mutating func addSegment(_ segment: TranscriptionSegment) {
        segments.append(segment)
        totalSegments = segments.count
    }
    
    mutating func updateSegment(_ updatedSegment: TranscriptionSegment) {
        if let index = segments.firstIndex(where: { $0.id == updatedSegment.id }) {
            segments[index] = updatedSegment
        }
    }
    
    mutating func markAsStarted() {
        startedAt = Date()
    }
    
    mutating func markAsCompleted() {
        completedAt = Date()
    }
}

enum TranscriptionJobStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case completedWithErrors = "completed_with_errors"
    case failed = "failed"
    
    var displayText: String {
        switch self {
        case .pending:
            return "Waiting to start"
        case .processing:
            return "Transcribing"
        case .completed:
            return "Completed"
        case .completedWithErrors:
            return "Completed with errors"
        case .failed:
            return "Failed"
        }
    }
}
