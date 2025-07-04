import Foundation

struct RecordingSettings: Codable {
    var audioQuality: AudioConfiguration.Quality
    var backgroundRecordingEnabled: Bool
    var autoStopOnLowBattery: Bool
    var showAudioLevels: Bool
    var maxRecordingDuration: TimeInterval
    var autoSaveEnabled: Bool
    
    var preferLocalProcessing: Bool
    
    static let `default` = RecordingSettings(
        audioQuality: .medium,
        backgroundRecordingEnabled: true,
        autoStopOnLowBattery: true,
        showAudioLevels: true,
        maxRecordingDuration: AudioConstants.maxRecordingDuration,
        autoSaveEnabled: true,
        preferLocalProcessing: true
    )
    
    // UserDefaults keys
    private enum Keys: String {
        case audioQuality = "recording_audio_quality"
        case backgroundRecording = "recording_background_enabled"
        case autoStopLowBattery = "recording_auto_stop_low_battery"
        case showAudioLevels = "recording_show_audio_levels"
        case maxDuration = "recording_max_duration"
        case autoSave = "recording_auto_save"
        case preferLocalProcessing    = "recording_prefer_local_processing"
    }
    
    // Save to UserDefaults
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality.rawValue)
        defaults.set(backgroundRecordingEnabled, forKey: Keys.backgroundRecording.rawValue)
        defaults.set(autoStopOnLowBattery, forKey: Keys.autoStopLowBattery.rawValue)
        defaults.set(showAudioLevels, forKey: Keys.showAudioLevels.rawValue)
        defaults.set(maxRecordingDuration, forKey: Keys.maxDuration.rawValue)
        defaults.set(autoSaveEnabled, forKey: Keys.autoSave.rawValue)
        defaults.set(preferLocalProcessing, forKey: Keys.preferLocalProcessing.rawValue)
    }
    
    // Load from UserDefaults
    static func load() -> RecordingSettings {
        let defaults = UserDefaults.standard
        
        return RecordingSettings(
            audioQuality: AudioConfiguration.Quality(rawValue: defaults.string(forKey: Keys.audioQuality.rawValue) ?? "") ?? .medium,
            backgroundRecordingEnabled: defaults.object(forKey: Keys.backgroundRecording.rawValue) as? Bool ?? true,
            autoStopOnLowBattery: defaults.object(forKey: Keys.autoStopLowBattery.rawValue) as? Bool ?? true,
            showAudioLevels: defaults.object(forKey: Keys.showAudioLevels.rawValue) as? Bool ?? true,
            maxRecordingDuration: defaults.object(forKey: Keys.maxDuration.rawValue) as? TimeInterval ?? AudioConstants.maxRecordingDuration,
            autoSaveEnabled: defaults.object(forKey: Keys.autoSave.rawValue) as? Bool ?? true,
            preferLocalProcessing:       defaults.object(forKey: Keys.preferLocalProcessing.rawValue) as? Bool ?? true
        )
    }
}
