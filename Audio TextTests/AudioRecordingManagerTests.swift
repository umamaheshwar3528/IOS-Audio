import XCTest
@testable import Audio_Text

class AudioRecordingManagerTests: XCTestCase {
    
    var recordingManager: AudioRecordingManager!
    
    override func setUp() {
        super.setUp()
        recordingManager = AudioRecordingManager.shared
    }
    
    override func tearDown() {
        recordingManager = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(recordingManager.currentState, .idle)
        XCTAssertNil(recordingManager.currentSession)
        XCTAssertEqual(recordingManager.audioLevel, 0.0)
        XCTAssertEqual(recordingManager.recordingDuration, 0.0)
    }
    
    func testRecordingInfo() {
        let info = recordingManager.getCurrentRecordingInfo()
        
        XCTAssertEqual(info.duration, recordingManager.recordingDuration)
        XCTAssertEqual(info.audioLevel, recordingManager.audioLevel)
        XCTAssertGreaterThanOrEqual(info.sampleCount, 0)
    }
    
    func testAudioContentValidation() {
        // Initially no audio content
        XCTAssertFalse(recordingManager.hasValidAudioContent())

        let hasContent = recordingManager.hasValidAudioContent()
        XCTAssertNotNil(hasContent)
    }
}
