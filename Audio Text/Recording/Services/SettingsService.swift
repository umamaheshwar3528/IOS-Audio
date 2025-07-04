import Foundation
import Combine

class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    @Published var settings: RecordingSettings
    
    private init() {
        self.settings = RecordingSettings.load()
    }
    
    func updateSettings(_ newSettings: RecordingSettings) {
        settings = newSettings
        settings.save()
        
        // Apply settings immediately
        applySettings()
    }
    
    func resetToDefaults() {
        settings = RecordingSettings.default
        settings.save()
        applySettings()
    }
    
    private func applySettings() {
        // Update audio constants if needed
        // This could trigger updates to recording manager
        NotificationCenter.default.post(name: .init("settingsChanged"), object: settings)
    }
}
