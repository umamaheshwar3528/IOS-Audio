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
        guard totalSegments > 0 else { return false }
        return completedSegments + failedSegments == totalSegments &&
               pendingSegments == 0 &&
               processingSegments == 0
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
        let completedSegments = segments
            .filter { $0.status == .completed && $0.transcriptionText != nil }
            .sorted { $0.segmentIndex < $1.segmentIndex }
        
        // Join segments with appropriate spacing
        var fullText = ""
        for (index, segment) in completedSegments.enumerated() {
            if let text = segment.transcriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                
                // Add the text
                fullText += text
                
                // Add spacing between segments (but not after the last one)
                if index < completedSegments.count - 1 {
                    // Add space if the current segment doesn't end with punctuation
                    if !text.hasSuffix(".") && !text.hasSuffix("!") && !text.hasSuffix("?") && !text.hasSuffix(",") {
                        fullText += " "
                    } else {
                        fullText += " "
                    }
                }
            }
        }
        
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var estimatedCompletionTime: TimeInterval {
        let remainingSegments = pendingSegments + processingSegments
        return TimeInterval(remainingSegments) * preferredService.estimatedProcessingTime
    }
    
    /// Gets a formatted summary of the transcription job
    var summary: String {
        let statusText = status.displayText
        let progressText = String(format: "%.0f%%", progress * 100)
        
        if hasFailures {
            return "\(statusText) (\(progressText)) - \(failedSegments) segments failed"
        } else {
            return "\(statusText) (\(progressText))"
        }
    }
    
    /// Gets the word count of the transcription
    var wordCount: Int {
        return fullTranscriptionText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    /// Gets the character count of the transcription
    var characterCount: Int {
        return fullTranscriptionText.count
    }
    
    /// Gets the average confidence score across all completed segments
    var averageConfidence: Float? {
        let confidenceValues = segments
            .compactMap { $0.confidence }
        
        guard !confidenceValues.isEmpty else { return nil }
        
        let sum = confidenceValues.reduce(0, +)
        return sum / Float(confidenceValues.count)
    }
    
    /// Gets segments that need retry
    var segmentsNeedingRetry: [TranscriptionSegment] {
        return segments.filter { $0.needsRetry }
    }
    
    /// Gets segments that have permanently failed
    var permanentlyFailedSegments: [TranscriptionSegment] {
        return segments.filter { $0.status == .failed && !$0.needsRetry }
    }
    
    mutating func addSegment(_ segment: TranscriptionSegment) {
        // Check if segment already exists
        if let existingIndex = segments.firstIndex(where: { $0.id == segment.id }) {
            segments[existingIndex] = segment
        } else {
            segments.append(segment)
        }
        
        totalSegments = segments.count
        
        // Mark as started if this is the first segment
        if startedAt == nil && !segments.isEmpty {
            markAsStarted()
        }
    }
    
    mutating func updateSegment(_ updatedSegment: TranscriptionSegment) {
        if let index = segments.firstIndex(where: { $0.id == updatedSegment.id }) {
            segments[index] = updatedSegment
        } else {
            // If segment doesn't exist, add it
            addSegment(updatedSegment)
        }
    }
    
    mutating func removeSegment(_ segmentId: UUID) {
        segments.removeAll { $0.id == segmentId }
        totalSegments = segments.count
    }
    
    mutating func markAsStarted() {
        if startedAt == nil {
            startedAt = Date()
        }
    }
    
    mutating func markAsCompleted() {
        if completedAt == nil {
            completedAt = Date()
        }
    }
    
    /// Forces the job to be marked as completed regardless of segment status
    mutating func forceComplete() {
        markAsCompleted()
        
        // Mark any pending or processing segments as failed
        for index in segments.indices {
            if segments[index].status == .pending ||
               segments[index].status == .processing ||
               segments[index].status == .queued {
                segments[index].markAsFailed(error: "Job force completed", service: .none)
            }
        }
    }
    
    /// Gets statistics about the job
    func getStatistics() -> TranscriptionJobStatistics {
        let totalDuration = segments.reduce(0.0) { $0 + $1.duration }
        let processingTime = completedAt?.timeIntervalSince(startedAt ?? createdAt) ?? 0
        
        return TranscriptionJobStatistics(
            totalSegments: totalSegments,
            completedSegments: completedSegments,
            failedSegments: failedSegments,
            totalDuration: totalDuration,
            processingTime: processingTime,
            wordCount: wordCount,
            characterCount: characterCount,
            averageConfidence: averageConfidence
        )
    }
    
    /// Gets a preview of the transcription (first few words)
    func getPreview(wordLimit: Int = 15) -> String {
        let words = fullTranscriptionText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.count <= wordLimit {
            return fullTranscriptionText
        } else {
            return words.prefix(wordLimit).joined(separator: " ") + "..."
        }
    }
    
    /// Validates the job's internal consistency
    func validate() -> [String] {
        var issues: [String] = []
        
        if segments.count != totalSegments {
            issues.append("Segment count mismatch: \(segments.count) vs \(totalSegments)")
        }
        
        let uniqueIndices = Set(segments.map { $0.segmentIndex })
        if uniqueIndices.count != segments.count {
            issues.append("Duplicate segment indices found")
        }
        
        if let startedAt = startedAt, startedAt < createdAt {
            issues.append("Started time is before created time")
        }
        
        if let completedAt = completedAt, let startedAt = startedAt, completedAt < startedAt {
            issues.append("Completed time is before started time")
        }
        
        return issues
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
    
    var systemImage: String {
        switch self {
        case .pending:
            return "clock"
        case .processing:
            return "waveform.badge.magnifyingglass"
        case .completed:
            return "checkmark.circle.fill"
        case .completedWithErrors:
            return "checkmark.circle.badge.exclamationmark"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .pending:
            return "orange"
        case .processing:
            return "blue"
        case .completed:
            return "green"
        case .completedWithErrors:
            return "orange"
        case .failed:
            return "red"
        }
    }
}

struct TranscriptionJobStatistics: Codable {
    let totalSegments: Int
    let completedSegments: Int
    let failedSegments: Int
    let totalDuration: TimeInterval
    let processingTime: TimeInterval
    let wordCount: Int
    let characterCount: Int
    let averageConfidence: Float?
    
    var successRate: Float {
        guard totalSegments > 0 else { return 0 }
        return Float(completedSegments) / Float(totalSegments)
    }
    
    var failureRate: Float {
        guard totalSegments > 0 else { return 0 }
        return Float(failedSegments) / Float(totalSegments)
    }
    
    var processingSpeedRatio: Float {
        guard processingTime > 0 && totalDuration > 0 else { return 0 }
        return Float(totalDuration / processingTime)
    }
}

// MARK: - Convenience Extensions

extension TranscriptionJob {
    /// Creates a test job for debugging purposes
    static func createTestJob() -> TranscriptionJob {
        var job = TranscriptionJob(sessionId: UUID(), preferredService: .openai)
        
        // Add some test segments
        for i in 0..<3 {
            var segment = TranscriptionSegment(
                sessionId: job.sessionId,
                segmentIndex: i,
                startTime: TimeInterval(i * 30),
                endTime: TimeInterval((i + 1) * 30)
            )
            
            if i < 2 {
                segment.markAsCompleted(
                    text: "This is test transcription for segment \(i + 1).",
                    confidence: 0.95,
                    service: .openai
                )
            }
            
            job.addSegment(segment)
        }
        
        return job
    }
}

extension Array where Element == TranscriptionJob {
    /// Gets all jobs for a specific session
    func forSession(_ sessionId: UUID) -> [TranscriptionJob] {
        return filter { $0.sessionId == sessionId }
    }
    
    /// Gets jobs with a specific status
    func withStatus(_ status: TranscriptionJobStatus) -> [TranscriptionJob] {
        return filter { $0.status == status }
    }
    
    /// Gets the most recent job for a session
    func mostRecent(for sessionId: UUID) -> TranscriptionJob? {
        return forSession(sessionId)
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }
}
