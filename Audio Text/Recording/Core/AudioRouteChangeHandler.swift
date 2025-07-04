import AVFoundation
import Foundation
import Combine

class AudioRouteChangeHandler: ObservableObject {
    static let shared = AudioRouteChangeHandler()
    
    @Published var availableInputs: [AVAudioSessionPortDescription] = []
    @Published var currentInput: AVAudioSessionPortDescription?
    @Published var isHeadphonesConnected = false
    @Published var isBluetoothConnected = false
    
    private let audioSession = AVAudioSession.sharedInstance()
    
    private init() {
        updateAudioRouteInfo()
        setupRouteChangeObserver()
    }
    
    // MARK: - Route Information
    
    private func updateAudioRouteInfo() {
        availableInputs = audioSession.availableInputs ?? []
        currentInput = audioSession.currentRoute.inputs.first
        
        // Check for headphones
        isHeadphonesConnected = audioSession.currentRoute.outputs.contains { output in
            [.headphones, .headsetMic].contains(output.portType)
        }
        
        // Check for Bluetooth
        isBluetoothConnected = audioSession.currentRoute.inputs.contains { input in
            input.portType == .bluetoothHFP
        } || audioSession.currentRoute.outputs.contains { output in
            [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains(output.portType)
        }
        
        Logger.shared.debug("Route updated - Headphones: \(isHeadphonesConnected), Bluetooth: \(isBluetoothConnected)")
    }
    
    // MARK: - Route Change Handling
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        updateAudioRouteInfo()
        
        let shouldAdjustRecording = handleSpecificRouteChange(reason, userInfo: userInfo)
        
        if shouldAdjustRecording {
            adjustRecordingForRouteChange(reason)
        }
        
        NotificationCenter.default.post(
            name: .init("audioRouteChanged"),
            object: reason,
            userInfo: ["currentInput": currentInput as Any]
        )
    }
    
    private func handleSpecificRouteChange(_ reason: AVAudioSession.RouteChangeReason, userInfo: [AnyHashable: Any]) -> Bool {
        switch reason {
        case .newDeviceAvailable:
            Logger.shared.info("New audio device connected")
            return true
            
        case .oldDeviceUnavailable:
            Logger.shared.info("Audio device disconnected")
            handleDeviceDisconnection(userInfo: userInfo)
            return true
            
        case .categoryChange:
            Logger.shared.info("Audio category changed")
            return false
            
        case .override:
            Logger.shared.info("Audio route overridden by system")
            return true
            
        case .wakeFromSleep:
            Logger.shared.info("Device woke from sleep")
            return true
            
        case .noSuitableRouteForCategory:
            Logger.shared.error("No suitable route for current category")
            return false
            
        case .routeConfigurationChange:
            Logger.shared.info("Route configuration changed")
            return true
            
        @unknown default:
            Logger.shared.debug("Unknown route change reason: \(reason.rawValue)")
            return false
        }
    }
    
    private func handleDeviceDisconnection(userInfo: [AnyHashable: Any]) {
        if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
            let wasUsingHeadphones = previousRoute.outputs.contains { output in
                [.headphones, .headsetMic].contains(output.portType)
            }
            
            let wasUsingBluetooth = previousRoute.inputs.contains { input in
                input.portType == .bluetoothHFP
            }
            
            if wasUsingHeadphones || wasUsingBluetooth {
                Logger.shared.info("External audio device disconnected during recording")
                // Potentially pause recording or show user notification
                NotificationCenter.default.post(
                    name: .init("externalAudioDeviceDisconnected"),
                    object: wasUsingHeadphones ? "headphones" : "bluetooth"
                )
            }
        }
    }
    
    private func adjustRecordingForRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        // Only adjust if currently recording
        guard AudioRecordingManager.shared.currentState.isRecording else { return }
        
        switch reason {
        case .newDeviceAvailable:
            // New device available - might want to switch to it
            if let preferredInput = findPreferredInput() {
                try? audioSession.setPreferredInput(preferredInput)
            }
            
        case .oldDeviceUnavailable:
            // Device removed - ensure we still have a valid input
            if currentInput == nil {
                Logger.shared.error("No audio input available")
                // Could pause recording here if no input is available
            }
            
        default:
            break
        }
    }
    
    private func findPreferredInput() -> AVAudioSessionPortDescription? {
        // Prefer external microphones over built-in
        return availableInputs.first { input in
            [.headsetMic, .bluetoothHFP].contains(input.portType)
        } ?? availableInputs.first { input in
            input.portType == .builtInMic
        }
    }
    
    // MARK: - Setup
    
    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
}
