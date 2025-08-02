import XCTest
import AVFoundation
@testable import Audio_Text

class AudioConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = AudioConfiguration.default
        
        XCTAssertEqual(config.sampleRate, 44_100)
        XCTAssertEqual(config.bitDepth, 16)
        XCTAssertEqual(config.channels, 1)
        XCTAssertEqual(config.quality, .medium)
        XCTAssertTrue(config.isValid)
    }
    
    func testCompatibleConfiguration() {
        let config = AudioConfiguration.compatible
        
        XCTAssertEqual(config.sampleRate, 44_100)
        XCTAssertEqual(config.channels, 1)
        XCTAssertTrue(config.isValid)
        XCTAssertNotNil(config.createAVAudioFormat())
    }
    
    func testConfigurationValidation() {
        // Test invalid configuration
        let invalidConfig = AudioConfiguration(
            sampleRate: 0,
            bitDepth: -1,
            channels: 0,
            format: kAudioFormatLinearPCM,
            quality: .low
        )
        
        XCTAssertFalse(invalidConfig.isValid)
        
        // Test valid configuration
        let validConfig = AudioConfiguration.highQuality
        XCTAssertTrue(validConfig.isValid)
    }
}
