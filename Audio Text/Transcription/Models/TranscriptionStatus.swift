
import Foundation

enum TranscriptionStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case queued = "queued"
    
    var displayText: String {
        switch self {
        case .pending:
            return "Waiting"
        case .processing:
            return "Transcribing..."
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .queued:
            return "Queued"
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
        case .failed:
            return "exclamationmark.triangle.fill"
        case .queued:
            return "tray.fill"
        }
    }
    
    var color: String {
        switch self {
        case .pending:
            return "gray"
        case .processing:
            return "blue"
        case .completed:
            return "green"
        case .failed:
            return "red"
        case .queued:
            return "orange"
        }
    }
}
