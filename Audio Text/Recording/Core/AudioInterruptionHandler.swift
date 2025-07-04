import AVFoundation
import Foundation
import Combine

class AudioInterruptionHandler: ObservableObject {
    static let shared = AudioInterruptionHandler()
    
    @Published var isInterrupted = false
    @Published var interruptionReason: String = ""
    
    private var shouldResumeAfterInterruption = false
    private var wasRecordingBeforeInterruption = false
    
    private init() {
        registerForInterruptionNotifications()
    }
    
    // MARK: - Interruption Handling
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            beginInterruption(userInfo: userInfo)
        case .ended:
            endInterruption(userInfo: userInfo)
        @unknown default:
            Logger.shared.error("Unknown interruption type: \(typeValue)")
        }
    }
    
    private func beginInterruption(userInfo: [AnyHashable: Any]) {
        Logger.shared.info("Audio interruption began")
        
        isInterrupted = true
        wasRecordingBeforeInterruption = AudioRecordingManager.shared.currentState.isRecording
        
        // Determine interruption reason
        if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
           let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
            switch reason {
            case .default:
                interruptionReason = "System interruption"
            case .appWasSuspended:
                interruptionReason = "App suspended"
            case .builtInMicMuted:
                interruptionReason = "Built-in microphone muted"
            @unknown default:
                interruptionReason = "Unknown interruption"
            }
        } else {
            interruptionReason = "Audio interruption"
        }
        
        // Pause recording if active
        if wasRecordingBeforeInterruption {
            AudioRecordingManager.shared.pauseRecording()
        }
        
        NotificationCenter.default.post(
            name: .init("audioInterruptionBegan"),
            object: interruptionReason
        )
    }
    
    private func endInterruption(userInfo: [AnyHashable: Any]) {
        Logger.shared.info("Audio interruption ended")
        
        isInterrupted = false
        interruptionReason = ""
        
        // Check if we should resume
        var shouldResume = wasRecordingBeforeInterruption
        
        if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            shouldResume = shouldResume && options.contains(.shouldResume)
        }
        
        // Resume recording if appropriate
        if shouldResume {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AudioRecordingManager.shared.resumeRecording()
            }
        }
        
        wasRecordingBeforeInterruption = false
        
        NotificationCenter.default.post(
            name: .init("audioInterruptionEnded"),
            object: shouldResume
        )
    }
    
    func prepareForInterruption() {
        shouldResumeAfterInterruption = AudioRecordingManager.shared.currentState.isRecording
    }
    
    // MARK: - Notification Setup
    
    private func registerForInterruptionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
}
