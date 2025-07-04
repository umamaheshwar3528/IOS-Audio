import Foundation

// OpenAI Whisper API Response
struct WhisperAPIResponse: Codable {
    let text: String
    let language: String?
    let duration: Double?
    let segments: [WhisperSegment]?
    
    struct WhisperSegment: Codable {
        let id: Int
        let seek: Double
        let start: Double
        let end: Double
        let text: String
        let tokens: [Int]
        let temperature: Double
        let avgLogprob: Double
        let compressionRatio: Double
        let noSpeechProb: Double
    }
}

// Apple Speech Recognition Result
struct AppleSpeechResult {
    let transcription: String
    let confidence: Float
    let isFinal: Bool
    let segments: [AppleSpeechSegment]?
    
    struct AppleSpeechSegment {
        let text: String
        let confidence: Float
        let timestamp: TimeInterval
        let duration: TimeInterval
    }
}

// Generic API Error Response
struct APIErrorResponse: Codable, Error {
    let error: APIError
    
    struct APIError: Codable {
        let message: String
        let type: String?
        let code: String?
    }
    
    var localizedDescription: String {
        return error.message
    }
}

// Network Request Models
struct TranscriptionRequest {
    let audioData: Data
    let language: String?
    let prompt: String?
    let temperature: Float?
    let format: AudioFormat
    
    enum AudioFormat: String, CaseIterable {
        case m4a = "m4a"
        case mp3 = "mp3"
        case wav = "wav"
        case flac = "flac"
    }
}

struct TranscriptionResponse {
    let text: String
    let confidence: Float?
    let language: String?
    let processingTime: TimeInterval
    let service: TranscriptionService
    let segments: [TranscriptionSegmentDetail]?
    
    struct TranscriptionSegmentDetail {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let confidence: Float
    }
}
