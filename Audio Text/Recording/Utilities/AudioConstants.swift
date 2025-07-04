import AVFoundation
import Foundation

struct AudioConstants {
    
    // Audio Session
    static let sessionCategory = AVAudioSession.Category.playAndRecord
    static let sessionOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]
    static let sessionMode = AVAudioSession.Mode.default

    // Recording Settings
    static let defaultSampleRate: Double = 44100.0
    static let defaultBitDepth: Int = 16
    static let defaultBitRate = 128000
    static let defaultChannels: UInt32 = 1
    
    // File Management
    static let audioFileExtension = "m4a"
    static let audioDirectoryName = "Recordings"
    static let tempDirectoryName = "TempRecordings"
    static let supportedAudioExtensions = ["m4a", "mp3", "wav", "aiff", "caf"]
    
    // Recording Limits
    static let maxRecordingDuration: TimeInterval = 3600 // 1 hour
    static let minStorageRequired: Int64 = 50 * 1024 * 1024 // 50 MB
    
    // Audio Level Monitoring
    static let silenceThreshold: Float = -80.0
    static let levelMeterUpdateInterval: TimeInterval = 0.05
    
    // Background Recording
    static let backgroundGracePeriod: TimeInterval = 30.0
    
    // Retry Configuration
    static let maxRetryAttempts = 3
    static let retryDelay: TimeInterval = 1.0
    static let maxFileSize: Int64 = 25 * 1024 * 1024 // 25MB for API uploads
}
