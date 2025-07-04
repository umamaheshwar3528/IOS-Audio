import Foundation

enum TranscriptionService: String, Codable, CaseIterable {
    case none = "none"
    case openai = "openai"
    case apple = "apple"
    case localWhisper = "local_whisper"
    
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .openai:
            return "OpenAI Whisper"
        case .apple:
            return "Apple Speech"
        case .localWhisper:
            return "Local Whisper"
        }
    }
    
    var requiresNetwork: Bool {
        switch self {
        case .openai:
            return true
        case .apple, .localWhisper, .none:
            return false
        }
    }
    
    var supportedLanguages: [String] {
        switch self {
        case .openai:
            return ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "ar", "hi"] // Whisper supports 99 languages
        case .apple:
            return ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "ru-RU", "ja-JP", "ko-KR", "zh-CN"]
        case .localWhisper:
            return ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh"]
        case .none:
            return []
        }
    }
    
    var estimatedProcessingTime: TimeInterval {
        switch self {
        case .openai:
            return 3.0 // 3 seconds for 30s audio
        case .apple:
            return 1.5 // 1.5 seconds for 30s audio
        case .localWhisper:
            return 8.0 // 8 seconds for 30s audio (device dependent)
        case .none:
            return 0
        }
    }
}
