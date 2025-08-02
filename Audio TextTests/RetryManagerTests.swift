import XCTest
@testable import Audio_Text

class RetryManagerTests: XCTestCase {
    
    var retryManager: RetryManager!
    
    override func setUp() {
        super.setUp()
        retryManager = RetryManager.shared
        retryManager.resetStatistics()
    }
    
    override func tearDown() {
        retryManager.cancelAllRetries()
        retryManager = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(retryManager.activeRetries.count, 0)
        XCTAssertEqual(retryManager.retryStatistics.totalRetries, 0)
        XCTAssertEqual(retryManager.retryStatistics.successfulRetries, 0)
        XCTAssertEqual(retryManager.retryStatistics.permanentFailures, 0)
    }
    
    func testRetryScheduling() {
        var segment = TranscriptionSegment(
            sessionId: UUID(),
            segmentIndex: 0,
            startTime: 0,
            endTime: 30
        )
        segment.markAsFailed(error: "Test error", service: .openai)
        
        // Ensure segment needs retry
        XCTAssertTrue(segment.needsRetry)
        
        let expectation = XCTestExpectation(description: "Retry completion")
        
        retryManager.scheduleRetry(for: segment) { retrySegment in
            XCTAssertEqual(retrySegment.id, segment.id)
            expectation.fulfill()
        }
        
        XCTAssertEqual(retryManager.activeRetries.count, 0)
        XCTAssertEqual(retryManager.retryStatistics.totalRetries, 1)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testRetryStatistics() {
        let segmentId = UUID()
        
        // Mark retry as successful
        retryManager.markRetrySuccessful(for: segmentId)
        
        // Mark another as permanently failed
        retryManager.markRetryPermanentlyFailed(for: segmentId)
        
        let analytics = retryManager.getRetryAnalytics()
        XCTAssertNotNil(analytics["totalRetries"])
        XCTAssertNotNil(analytics["successfulRetries"])
        XCTAssertNotNil(analytics["permanentFailures"])
        XCTAssertNotNil(analytics["successRate"])
    }
}
