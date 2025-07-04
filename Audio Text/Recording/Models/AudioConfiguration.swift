import AVFoundation
import Foundation

struct AudioConfiguration: Codable {
    let sampleRate: Double
    let bitDepth: Int
    let channels: Int
    let format: AudioFormatID
    let quality: Quality
    
    enum Quality: String, CaseIterable, Codable {
        case low    = "Low"
        case medium = "Medium"
        case high   = "High"
        case custom = "Custom"
        
        var sampleRate: Double {
            switch self {
            case .low:    return 22_050
            case .medium, .custom: return 44_100
            case .high:   return 48_000
            }
        }
        
        var bitDepth: Int {
            switch self {
            case .low, .medium, .custom: return 16
            case .high:                   return 24
            }
        }
        
        var channels: Int {
            switch self {
            case .low, .medium, .custom: return 1  // Mono for compatibility
            case .high:                   return 2  // Stereo for high quality
            }
        }
    }
    
    // Most compatible default configuration
    static let `default` = AudioConfiguration(
        sampleRate: 44_100,
        bitDepth:   16,
        channels:   1,
        format:     kAudioFormatLinearPCM,
        quality:    .medium
    )

    // Guaranteed compatible configuration that should work on all devices
    static let compatible = AudioConfiguration(
        sampleRate: 44_100,
        bitDepth:   16,
        channels:   1,
        format:     kAudioFormatLinearPCM,
        quality:    .medium
    )
    
    // High quality configuration (may require format conversion)
    static let highQuality = AudioConfiguration(
        sampleRate: 48_000,
        bitDepth:   24,
        channels:   1,  // Keep mono for now to avoid conversion issues
        format:     kAudioFormatLinearPCM,
        quality:    .high
    )
    
    // Low quality configuration for minimal file sizes
    static let lowQuality = AudioConfiguration(
        sampleRate: 22_050,
        bitDepth:   16,
        channels:   1,
        format:     kAudioFormatLinearPCM,
        quality:    .low
    )
    
    func createAVAudioFormat() -> AVAudioFormat? {
        let settings: [String: Any] = [
            AVFormatIDKey:              format,
            AVSampleRateKey:            Float(sampleRate),
            AVNumberOfChannelsKey:      channels,
            AVLinearPCMBitDepthKey:     bitDepth,
            AVLinearPCMIsFloatKey:      false,
            AVLinearPCMIsBigEndianKey:  false
        ]
        
        let audioFormat = AVAudioFormat(settings: settings)
        
        if audioFormat == nil {
            Logger.shared.error("Failed to create AVAudioFormat with settings: \(settings)")
        }
        
        return audioFormat
    }
    
    func createCompatibleAVAudioFormat() -> AVAudioFormat? {
        // Create a standard PCM format that's guaranteed to be compatible
        let standardFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        
        if standardFormat == nil {
            Logger.shared.error("Failed to create standard AVAudioFormat with sample rate: \(sampleRate), channels: \(channels)")
        }
        
        return standardFormat
    }
    
    // Creates the most basic possible format for maximum compatibility
    func createSimplestAVAudioFormat() -> AVAudioFormat? {
        return AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
    }
    
    var estimatedFileSize: Double {
        let bytesPerSecond = (sampleRate * Double(bitDepth) * Double(channels)) / 8
        return (bytesPerSecond * 60) / (1_024 * 1_024)  // MB per minute
    }
    
    var displayName: String {
        return "\(quality.rawValue) (\(Int(sampleRate))Hz, \(bitDepth)-bit, \(channels == 1 ? "Mono" : "Stereo"))"
    }
    
    var description: String {
        return "Sample Rate: \(Int(sampleRate))Hz, Bit Depth: \(bitDepth)-bit, Channels: \(channels), Format: \(formatName)"
    }
    
    private var formatName: String {
        switch format {
        case kAudioFormatLinearPCM:
            return "Linear PCM"
        case kAudioFormatMPEG4AAC:
            return "AAC"
        case kAudioFormatAppleLossless:
            return "Apple Lossless"
        case kAudioFormatFLAC:
            return "FLAC"
        default:
            return "Unknown (\(format))"
        }
    }
    
    // Validation method to check if configuration is reasonable
    var isValid: Bool {
        return sampleRate > 0 &&
               bitDepth > 0 &&
               channels > 0 &&
               sampleRate <= 192_000 &&  // Reasonable upper limit
               bitDepth <= 32 &&         // Reasonable upper limit
               channels <= 8             // Reasonable upper limit
    }
    
    // Check if this configuration is likely to need format conversion
    func needsConversionFrom(_ inputFormat: AVAudioFormat) -> Bool {
        return inputFormat.sampleRate != sampleRate ||
               inputFormat.channelCount != channels ||
               (inputFormat.commonFormat == .pcmFormatFloat32 && format == kAudioFormatLinearPCM)
    }
}

// MARK: - Preset Configurations

extension AudioConfiguration {
    static var allPresets: [AudioConfiguration] {
        return [
            .compatible,
            .default,
            .lowQuality,
            .highQuality
        ]
    }
    
    // Create configuration optimized for transcription
    static let transcriptionOptimized = AudioConfiguration(
        sampleRate: 16_000,  // Common for speech recognition
        bitDepth:   16,
        channels:   1,       // Mono is sufficient for speech
        format:     kAudioFormatLinearPCM,
        quality:    .custom
    )
    
    // Create configuration for music recording
    static let musicOptimized = AudioConfiguration(
        sampleRate: 44_100,  // CD quality
        bitDepth:   24,      // High bit depth for dynamic range
        channels:   2,       // Stereo for music
        format:     kAudioFormatLinearPCM,
        quality:    .custom
    )
    
    // Create configuration for voice memos
    static let voiceMemoOptimized = AudioConfiguration(
        sampleRate: 22_050,  // Adequate for voice
        bitDepth:   16,
        channels:   1,       // Mono for voice
        format:     kAudioFormatLinearPCM,
        quality:    .custom
    )
}

// MARK: - Audio Quality Extensions

extension AudioConfiguration.Quality {
    var fileExtension: String {
        switch self {
        case .low:
            return "m4a"
        case .medium:
            return "wav"
        case .high:
            return "wav"
        case .custom:
            return "wav"
        }
    }
    
    var compressionRatio: Float {
        switch self {
        case .low:    return 0.1
        case .medium: return 0.5
        case .high:   return 1.0
        case .custom: return 0.5
        }
    }
}
