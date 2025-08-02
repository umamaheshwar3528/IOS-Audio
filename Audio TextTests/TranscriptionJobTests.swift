import XCTest
@testable import Audio_Text

class TranscriptionJobTests: XCTestCase {
    
    func testJobInitialization() {
        let sessionId = UUID()
        let job = TranscriptionJob(sessionId: sessionId)
        
        XCTAssertNotNil(job.id)
        XCTAssertEqual(job.sessionId, sessionId)
        XCTAssertEqual(job.segments.count, 0)
        XCTAssertEqual(job.totalSegments, 0)
        XCTAssertEqual(job.progress, 0.0)
        XCTAssertFalse(job.isCompleted)
    }
    
    func testSegmentManagement() {
        var job = TranscriptionJob(sessionId: UUID())
        
        // Add a segment
        let segment = TranscriptionSegment(
            sessionId: job.sessionId,
            segmentIndex: 0,
            startTime: 0,
            endTime: 30
        )
        
        job.addSegment(segment)
        
        XCTAssertEqual(job.segments.count, 1)
        XCTAssertEqual(job.totalSegments, 1)
        XCTAssertNotNil(job.startedAt)
    }
    
    func testJobProgress() {
        var job = TranscriptionJob(sessionId: UUID())
        
        // Add segments
        for i in 0..<3 {
            var segment = TranscriptionSegment(
                sessionId: job.sessionId,
                segmentIndex: i,
                startTime: TimeInterval(i * 30),
                endTime: TimeInterval((i + 1) * 30)
            )
            
            if i < 2 {
                segment.markAsCompleted(text: "Test", service: .openai)
            }
            
            job.addSegment(segment)
        }
        
        XCTAssertEqual(job.completedSegments, 2)
        XCTAssertEqual(job.pendingSegments, 1)
        XCTAssertEqual(job.progress, 2.0/3.0, accuracy: 0.01)
        XCTAssertFalse(job.isCompleted)
    }
}
