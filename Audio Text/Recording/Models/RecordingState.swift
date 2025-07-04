import Foundation

enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case stopped
    case error(RecordingError)
    
    var isRecording: Bool {
        switch self {
        case .recording:
            return true
        default:
            return false
        }
    }
    
    var isPaused: Bool {
        switch self {
        case .paused:
            return true
        default:
            return false
        }
    }
    
    var displayText: String {
        switch self {
        case .idle:
            return "Ready to Record"
        case .recording:
            return "Recording..."
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}
