import XCTest
@testable import Audio_Text

class TranscriptionManagerTests: XCTestCase {
    
    var transcriptionManager: TranscriptionManager!
    
    override func setUp() {
        super.setUp()
        transcriptionManager = TranscriptionManager.shared
    }
    
    override func tearDown() {
        transcriptionManager = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(transcriptionManager.activeJobs.count, 1)
        XCTAssertEqual(transcriptionManager.completedJobs.count, 1)
        XCTAssertFalse(!transcriptionManager.isProcessing)
        XCTAssertEqual(transcriptionManager.currentProgress, 0.0)
    }
    
    func testJobCreation() {
        let session = RecordingSession()
        let job = transcriptionManager.startTranscriptionJob(for: session)
        
        XCTAssertNotNil(job.id)
        XCTAssertEqual(job.sessionId, session.id)
        XCTAssertTrue(transcriptionManager.isProcessing)
        XCTAssertEqual(transcriptionManager.activeJobs.count, 1)
        
        // Cleanup
        transcriptionManager.stopTranscriptionJob(session.id)
    }
    
    func testTranscriptionTextRetrieval() {
        let sessionId = UUID()
        
        // Initially no text
        XCTAssertNil(transcriptionManager.getTranscriptionText(for: sessionId))
        
        // Create a completed job with text
        var job = TranscriptionJob(sessionId: sessionId)
        var segment = TranscriptionSegment(
            sessionId: sessionId,
            segmentIndex: 0,
            startTime: 0,
            endTime: 30
        )
        segment.markAsCompleted(text: "Test transcription", service: .openai)
        job.addSegment(segment)
        job.markAsCompleted()
        
        transcriptionManager.completedJobs.append(job)
        
        let text = transcriptionManager.getTranscriptionText(for: sessionId)
        XCTAssertEqual(text, "Test transcription")
    }
}
