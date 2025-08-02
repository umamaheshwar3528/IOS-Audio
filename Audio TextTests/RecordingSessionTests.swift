import XCTest
@testable import Audio_Text

class RecordingSessionTests: XCTestCase {
    
    func testSessionInitialization() {
        let session = RecordingSession()
        
        XCTAssertNotNil(session.id)
        XCTAssertFalse(session.title.isEmpty)
        XCTAssertNotNil(session.startTime)
        XCTAssertNil(session.endTime)
        XCTAssertNil(session.fileURL)
        XCTAssertFalse(session.isComplete)
    }
    
    func testSessionDuration() {
        let session = RecordingSession()
        
        // Test duration calculation for ongoing session
        let ongoingDuration = session.duration
        //XCTAssertGreaterThan(ongoingDuration, 0)
        
        // Test completed session duration
        var completedSession = session
        completedSession.endTime = Date().addingTimeInterval(10)
        
        let completedDuration = completedSession.duration
        XCTAssertGreaterThan(completedDuration, 0)
        XCTAssertLessThan(completedDuration, 15) // Should be around 10 seconds
    }
    
    func testSessionCompletion() {
        var session = RecordingSession()
        
        // Initially not complete
        XCTAssertFalse(session.isComplete)
        
        // Complete the session
        session.endTime = Date()
        session.fileURL = URL(fileURLWithPath: "/test/path.m4a")
        
        XCTAssertTrue(session.isComplete)
    }
}
