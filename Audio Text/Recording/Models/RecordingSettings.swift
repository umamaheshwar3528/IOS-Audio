import Foundation

struct RecordingSettings: Codable {
    // Audio Settings
    var audioQuality: AudioConfiguration.Quality
    var backgroundRecordingEnabled: Bool
    var autoStopOnLowBattery: Bool
    var showAudioLevels: Bool
    var maxRecordingDuration: TimeInterval
    var autoSaveEnabled: Bool
    
    // Transcription Settings
    var enableAutoTranscription: Bool
    var preferredTranscriptionService: TranscriptionService?
    var allowServiceFallback: Bool
    var allowCellularTranscription: Bool
    var preferLocalProcessing: Bool
    var maxRetryAttempts: Int
    var maxConcurrentTranscriptions: Int
    
    // Advanced Settings
    var enableDeveloperMode: Bool
    var enableDetailedLogging: Bool

    static let `default` = RecordingSettings(
        // Audio defaults
        audioQuality: .medium,
        backgroundRecordingEnabled: true,
        autoStopOnLowBattery: true,
        showAudioLevels: true,
        maxRecordingDuration: AudioConstants.maxRecordingDuration,
        autoSaveEnabled: true,
        
        // Transcription defaults
        enableAutoTranscription: false, // Start disabled
        preferredTranscriptionService: nil, // Auto-select
        allowServiceFallback: true,
        allowCellularTranscription: false,
        preferLocalProcessing: true,
        maxRetryAttempts: 5,
        maxConcurrentTranscriptions: 3,
        
        // Advanced defaults
        enableDeveloperMode: false,
        enableDetailedLogging: false
    )

    private enum Keys: String {
        // Audio keys
        case audioQuality = "recording_audio_quality"
        case backgroundRecording = "recording_background_enabled"
        case autoStopLowBattery = "recording_auto_stop_low_battery"
        case showAudioLevels = "recording_show_audio_levels"
        case maxDuration = "recording_max_duration"
        case autoSave = "recording_auto_save"
        
        // Transcription keys
        case enableAutoTranscription = "recording_enable_auto_transcription"
        case preferredTranscriptionService = "recording_preferred_transcription_service"
        case allowServiceFallback = "recording_allow_service_fallback"
        case allowCellularTranscription = "recording_allow_cellular_transcription"
        case preferLocalProcessing = "recording_prefer_local_processing"
        case maxRetryAttempts = "recording_max_retry_attempts"
        case maxConcurrentTranscriptions = "recording_max_concurrent_transcriptions"
        
        // Advanced keys
        case enableDeveloperMode = "recording_enable_developer_mode"
        case enableDetailedLogging = "recording_enable_detailed_logging"
    }

    func save() {
        let defaults = UserDefaults.standard
        
        // Save audio settings
        defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality.rawValue)
        defaults.set(backgroundRecordingEnabled, forKey: Keys.backgroundRecording.rawValue)
        defaults.set(autoStopOnLowBattery, forKey: Keys.autoStopLowBattery.rawValue)
        defaults.set(showAudioLevels, forKey: Keys.showAudioLevels.rawValue)
        defaults.set(maxRecordingDuration, forKey: Keys.maxDuration.rawValue)
        defaults.set(autoSaveEnabled, forKey: Keys.autoSave.rawValue)
        
        // Save transcription settings
        defaults.set(enableAutoTranscription, forKey: Keys.enableAutoTranscription.rawValue)
        defaults.set(preferredTranscriptionService?.rawValue, forKey: Keys.preferredTranscriptionService.rawValue)
        defaults.set(allowServiceFallback, forKey: Keys.allowServiceFallback.rawValue)
        defaults.set(allowCellularTranscription, forKey: Keys.allowCellularTranscription.rawValue)
        defaults.set(preferLocalProcessing, forKey: Keys.preferLocalProcessing.rawValue)
        defaults.set(maxRetryAttempts, forKey: Keys.maxRetryAttempts.rawValue)
        defaults.set(maxConcurrentTranscriptions, forKey: Keys.maxConcurrentTranscriptions.rawValue)
        
        // Save advanced settings
        defaults.set(enableDeveloperMode, forKey: Keys.enableDeveloperMode.rawValue)
        defaults.set(enableDetailedLogging, forKey: Keys.enableDetailedLogging.rawValue)
    }

    static func load() -> RecordingSettings {
        let defaults = UserDefaults.standard

        return RecordingSettings(
            // Load audio settings
            audioQuality: AudioConfiguration.Quality(rawValue: defaults.string(forKey: Keys.audioQuality.rawValue) ?? "") ?? .medium,
            backgroundRecordingEnabled: defaults.object(forKey: Keys.backgroundRecording.rawValue) as? Bool ?? true,
            autoStopOnLowBattery: defaults.object(forKey: Keys.autoStopLowBattery.rawValue) as? Bool ?? true,
            showAudioLevels: defaults.object(forKey: Keys.showAudioLevels.rawValue) as? Bool ?? true,
            maxRecordingDuration: defaults.object(forKey: Keys.maxDuration.rawValue) as? TimeInterval ?? AudioConstants.maxRecordingDuration,
            autoSaveEnabled: defaults.object(forKey: Keys.autoSave.rawValue) as? Bool ?? true,
            
            // Load transcription settings
            enableAutoTranscription: defaults.object(forKey: Keys.enableAutoTranscription.rawValue) as? Bool ?? false,
            preferredTranscriptionService: {
                if let rawValue = defaults.string(forKey: Keys.preferredTranscriptionService.rawValue),
                   !rawValue.isEmpty {
                    return TranscriptionService(rawValue: rawValue)
                }
                return nil
            }(),
            allowServiceFallback: defaults.object(forKey: Keys.allowServiceFallback.rawValue) as? Bool ?? true,
            allowCellularTranscription: defaults.object(forKey: Keys.allowCellularTranscription.rawValue) as? Bool ?? false,
            preferLocalProcessing: defaults.object(forKey: Keys.preferLocalProcessing.rawValue) as? Bool ?? true,
            maxRetryAttempts: defaults.object(forKey: Keys.maxRetryAttempts.rawValue) as? Int ?? 5,
            maxConcurrentTranscriptions: defaults.object(forKey: Keys.maxConcurrentTranscriptions.rawValue) as? Int ?? 3,
            
            // Load advanced settings
            enableDeveloperMode: defaults.object(forKey: Keys.enableDeveloperMode.rawValue) as? Bool ?? false,
            enableDetailedLogging: defaults.object(forKey: Keys.enableDetailedLogging.rawValue) as? Bool ?? false
        )
    }
}
