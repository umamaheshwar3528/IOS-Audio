import Foundation

class AudioQualityService {
    static let shared = AudioQualityService()
    
    private init() {}
    
    func recommendedQuality(basedOnStorage availableBytes: Int64) -> AudioConfiguration.Quality {
        let availableMB = Double(availableBytes) / (1024 * 1024)
        
        switch availableMB {
        case 0..<100:
            return .low
        case 100..<500:
            return .medium
        default:
            return .high
        }
    }
    
    func validateConfiguration(_ config: AudioConfiguration) -> Bool {
        // Validate sample rate
        guard config.sampleRate >= 8000 && config.sampleRate <= 96000 else {
            return false
        }
        
        // Validate bit depth
        guard [8, 16, 24, 32].contains(config.bitDepth) else {
            return false
        }
        
        // Validate channels
        guard config.channels >= 1 && config.channels <= 2 else {
            return false
        }
        
        return true
    }
    
    func estimatedRecordingTime(for config: AudioConfiguration, availableBytes: Int64) -> TimeInterval {
        let bytesPerSecond = (config.sampleRate * Double(config.bitDepth) * Double(config.channels)) / 8
        return Double(availableBytes) / bytesPerSecond
    }
}
