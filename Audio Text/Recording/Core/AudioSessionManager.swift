import AVFoundation
import Foundation
import Combine

class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()
    
    @Published var isSessionActive = false
    @Published var currentRoute: String = ""
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationObservers()
        updateCurrentRoute()
    }
    
    deinit {
        deactivateSession()
    }
    
    // MARK: - Session Configuration
    
    func configureSessionForRecording() throws {
        do {
            try audioSession.setCategory(
                AudioConstants.sessionCategory,
                mode: AudioConstants.sessionMode,
                options: AudioConstants.sessionOptions
            )
            
            Logger.shared.info("Audio session configured for recording")
        } catch {
            Logger.shared.error("Failed to configure audio session: \(error)")
            throw RecordingError.audioSessionConfigurationFailed
        }
    }
    
    func activateSession() throws {
        do {
            try audioSession.setActive(true, options: [])
            isSessionActive = true
            updateCurrentRoute()
            Logger.shared.info("Audio session activated")
        } catch {
            Logger.shared.error("Failed to activate audio session: \(error)")
            throw RecordingError.audioSessionConfigurationFailed
        }
    }
    
    func deactivateSession() {
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            isSessionActive = false
            Logger.shared.info("Audio session deactivated")
        } catch {
            Logger.shared.error("Failed to deactivate audio session: \(error)")
        }
    }
    
    func setupBackgroundRecording() throws {
        try configureSessionForRecording()
        
        // Request permission for background recording
        if !audioSession.isInputAvailable {
            throw RecordingError.audioRouteUnavailable
        }
    }
    
    // MARK: - Route Management
    
    private func updateCurrentRoute() {
        let currentRoute = audioSession.currentRoute
        let inputName = currentRoute.inputs.first?.portName ?? "Unknown"
        self.currentRoute = inputName
        
        Logger.shared.debug("Current audio route: \(inputName)")
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        updateCurrentRoute()
        
        switch reason {
        case .newDeviceAvailable:
            Logger.shared.info("New audio device available")
        case .oldDeviceUnavailable:
            Logger.shared.info("Audio device removed")
        case .categoryChange:
            Logger.shared.info("Audio category changed")
        case .override:
            Logger.shared.info("Audio route overridden")
        default:
            Logger.shared.debug("Audio route changed: \(reason.rawValue)")
        }
        
        NotificationCenter.default.post(
            name: .init("audioRouteChanged"),
            object: reason,
            userInfo: userInfo
        )
    }
    
    // MARK: - Notification Setup
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
}
