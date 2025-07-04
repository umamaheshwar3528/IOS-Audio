import Foundation

enum RecordingError: Error, LocalizedError, Equatable {
    case permissionDenied
    case audioSessionConfigurationFailed
    case audioEngineStartFailed
    case fileCreationFailed
    case insufficientStorage
    case recordingInProgress
    case noActiveRecording
    case backgroundRecordingFailed
    case audioRouteUnavailable
    case hardwareNotAvailable
    case interrupted
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required to record audio"
        case .audioSessionConfigurationFailed:
            return "Failed to configure audio session"
        case .audioEngineStartFailed:
            return "Failed to start audio engine"
        case .fileCreationFailed:
            return "Could not create recording file"
        case .insufficientStorage:
            return "Not enough storage space available"
        case .recordingInProgress:
            return "Recording is already in progress"
        case .noActiveRecording:
            return "No active recording to stop"
        case .backgroundRecordingFailed:
            return "Background recording is not available"
        case .audioRouteUnavailable:
            return "Audio input route is not available"
        case .hardwareNotAvailable:
            return "Audio hardware is not available"
        case .interrupted:
            return "Recording was interrupted"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please enable microphone access in Settings"
        case .audioSessionConfigurationFailed:
            return "Try restarting the app"
        case .audioEngineStartFailed:
            return "Make sure no other apps are using the microphone"
        case .fileCreationFailed:
            return "Check available storage space"
        case .insufficientStorage:
            return "Free up storage space and try again"
        case .recordingInProgress:
            return "Stop the current recording first"
        case .noActiveRecording:
            return "Start a new recording"
        case .backgroundRecordingFailed:
            return "Enable background app refresh for better recording"
        case .audioRouteUnavailable:
            return "Check your audio input device connection"
        case .hardwareNotAvailable:
            return "Restart the app or device"
        case .interrupted:
            return "Recording will resume automatically when possible"
        case .unknown:
            return "Try restarting the app"
        }
    }
}
