import UIKit
import Foundation
import Combine

class BackgroundTaskService: ObservableObject {
    static let shared = BackgroundTaskService()
    
    @Published var backgroundTimeRemaining: TimeInterval = 0
    @Published var isBackgroundRecordingActive = false
    
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTimer: Timer?
    
    private init() {}
    
    func beginBackgroundTask(name: String = "AudioRecording") {
        endBackgroundTask() // End any existing task
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Called when background time expires
            self.endBackgroundTask()
            self.isBackgroundRecordingActive = false
            NotificationCenter.default.post(name: .init("backgroundRecordingExpired"), object: nil)
        }
        
        if backgroundTaskIdentifier != .invalid {
            isBackgroundRecordingActive = true
            startBackgroundTimer()
            Logger.shared.info("Background task started: \(backgroundTaskIdentifier.rawValue)")
        }
    }
    
    func endBackgroundTask() {
        guard backgroundTaskIdentifier != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
        isBackgroundRecordingActive = false
        
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        backgroundTimeRemaining = 0
        
        Logger.shared.info("Background task ended")
    }
    
    private func startBackgroundTimer() {
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
            
            if self.backgroundTimeRemaining <= AudioConstants.backgroundGracePeriod {
                // Warn about impending expiration
                NotificationCenter.default.post(
                    name: .init("backgroundRecordingWarning"),
                    object: self.backgroundTimeRemaining
                )
            }
        }
    }
}
