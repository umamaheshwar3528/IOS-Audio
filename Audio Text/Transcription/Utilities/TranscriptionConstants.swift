import Foundation

struct TranscriptionConstants {
    // Segmentation
    static let defaultSegmentDuration: TimeInterval = 30.0
    static let segmentOverlap: TimeInterval = 1.0 // 1 second overlap for word boundary detection
    static let minSegmentDuration: TimeInterval = 5.0
    static let maxSegmentDuration: TimeInterval = 60.0
    
    // Retry Logic
    static let maxRetryAttempts = 5
    static let baseRetryDelay: TimeInterval = 2.0
    static let maxRetryDelay: TimeInterval = 30.0
    static let retryMultiplier: Double = 2.0
    
    // API Limits
    static let maxConcurrentTranscriptions = 3
    static let apiTimeout: TimeInterval = 60.0
    static let maxFileSize: Int64 = 25 * 1024 * 1024 // 25MB (OpenAI limit)
    
    // Queue Management
    static let maxQueueSize = 1000
    static let queueProcessingInterval: TimeInterval = 5.0
    static let backgroundProcessingTime: TimeInterval = 25.0 // iOS background limit is ~30s
    
    // Quality Settings
    static let defaultLanguage = "en"
    static let defaultTemperature: Float = 0.0
    static let minimumConfidenceThreshold: Float = 0.5
    
    // File Management
    static let segmentDirectoryName = "AudioSegments"
    static let tempSegmentPrefix = "temp_segment_"
    static let processedSegmentPrefix = "segment_"
    
    // Service Priorities
    static let servicePriorityOrder: [TranscriptionService] = [.openai, .apple, .localWhisper]
    
    // Error Codes
    enum ErrorCode: String {
        case networkUnavailable = "network_unavailable"
        case apiQuotaExceeded = "api_quota_exceeded"
        case audioFormatUnsupported = "audio_format_unsupported"
        case fileTooLarge = "file_too_large"
        case serviceUnavailable = "service_unavailable"
        case authenticationFailed = "authentication_failed"
        case processingTimeout = "processing_timeout"
        case unknownError = "unknown_error"
    }
}
