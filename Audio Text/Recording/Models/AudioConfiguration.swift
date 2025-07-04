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
            case .medium: return 44_100
            case .high:   return 48_000
            case .custom: return 44_100
            }
        }
        
        var bitDepth: Int {
            switch self {
            case .low, .medium, .custom: return 16
            case .high:                   return 24
            }
        }
    }
    
    static let `default` = AudioConfiguration(
        sampleRate: Quality.medium.sampleRate,
        bitDepth:   Quality.medium.bitDepth,
        channels:   1,
        format:     kAudioFormatLinearPCM,
        quality:    .medium
    )
    
    func createAVAudioFormat() -> AVAudioFormat? {
        let settings: [String: Any] = [
            AVFormatIDKey:            format,
            AVSampleRateKey:          sampleRate,
            AVNumberOfChannelsKey:    channels,
            AVLinearPCMBitDepthKey:   bitDepth,
            AVLinearPCMIsFloatKey:    false,
            AVLinearPCMIsBigEndianKey:false
        ]
        return AVAudioFormat(settings: settings)
    }
    
    var estimatedFileSize: Double {
        let bytesPerSecond = (sampleRate * Double(bitDepth) * Double(channels)) / 8
        return (bytesPerSecond * 60) / (1_024 * 1_024)  // MB per minute
    }
}
