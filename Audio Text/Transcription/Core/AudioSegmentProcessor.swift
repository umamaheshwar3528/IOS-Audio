import AVFoundation
import Foundation
import Combine

class AudioSegmentProcessor: ObservableObject {
    static let shared = AudioSegmentProcessor()
    
    @Published var currentSegmentIndex = 0
    @Published var isProcessingSegments = false
    @Published var segmentQueue: [TranscriptionSegment] = []
    
    private var segmentTimer: Timer?
    private var currentRecordingSession: RecordingSession?
    private var audioFileWriter: AudioFileWriter?
    private var segmentStartTime: TimeInterval = 0
    private var accumulatedAudioTime: TimeInterval = 0
    
    // Dependencies
    private let fileManager = AudioFileManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupRecordingObservers()
    }
    
    deinit {
        stopSegmentation()
    }
    
    // MARK: - Public Interface
    
    func startSegmentation(for session: RecordingSession) {
        Logger.shared.info("Starting audio segmentation for session: \(session.id)")
        
        currentRecordingSession = session
        currentSegmentIndex = 0
        segmentStartTime = 0
        accumulatedAudioTime = 0
        isProcessingSegments = true
        
        // Create first segment
        createNewSegment()
        
        // Start timer for automatic segmentation
        startSegmentTimer()
    }
    
    func stopSegmentation() {
        Logger.shared.info("Stopping audio segmentation")
        
        segmentTimer?.invalidate()
        segmentTimer = nil
        
        // Finalize current segment if it exists
        if let currentSegment = getCurrentSegment() {
            finalizeSegment(currentSegment)
        }
        
        audioFileWriter?.close()
        audioFileWriter = nil
        currentRecordingSession = nil
        isProcessingSegments = false
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, timestamp: TimeInterval) {
        guard isProcessingSegments,
              let session = currentRecordingSession else { return }
        
        // Update accumulated time
        let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        accumulatedAudioTime += bufferDuration
        
        // Write audio to current segment file
        writeBufferToCurrentSegment(buffer)
        
        // Check if segment duration threshold is reached
        let currentSegmentDuration = accumulatedAudioTime - segmentStartTime
        if currentSegmentDuration >= TranscriptionConstants.defaultSegmentDuration {
            finalizeCurrentSegmentAndCreateNext()
        }
    }
    
    func getSegmentsForSession(_ sessionId: UUID) -> [TranscriptionSegment] {
        return segmentQueue.filter { $0.sessionId == sessionId }
    }
    
    // MARK: - Segment Management
    
    private func createNewSegment() {
        guard let session = currentRecordingSession else { return }
        
        let segmentStartTime = self.segmentStartTime
        let segmentEndTime = segmentStartTime + TranscriptionConstants.defaultSegmentDuration
        
        let segment = TranscriptionSegment(
            sessionId: session.id,
            segmentIndex: currentSegmentIndex,
            startTime: segmentStartTime,
            endTime: segmentEndTime
        )
        
        // Create audio file for this segment
        if let segmentFileURL = createSegmentAudioFile(for: segment) {
            var updatedSegment = segment
            updatedSegment.audioFileURL = segmentFileURL
            segmentQueue.append(updatedSegment)
            
            // Setup audio file writer
            setupAudioFileWriter(for: segmentFileURL, with: session.configuration)
        }
        
        Logger.shared.debug("Created new segment \(currentSegmentIndex) for session \(session.id)")
    }
    
    private func finalizeCurrentSegmentAndCreateNext() {
        guard let currentSegment = getCurrentSegment() else { return }
        
        // Finalize current segment
        finalizeSegment(currentSegment)
        
        // Setup next segment
        segmentStartTime = accumulatedAudioTime
        currentSegmentIndex += 1
        
        // Create next segment
        createNewSegment()
    }
    
    private func finalizeSegment(_ segment: TranscriptionSegment) {
        // Close current audio file writer
        audioFileWriter?.close()
        audioFileWriter = nil
        
        // Update segment with actual end time
        if let index = segmentQueue.firstIndex(where: { $0.id == segment.id }) {
            var updatedSegment = segment
            updatedSegment.endTime = accumulatedAudioTime
            segmentQueue[index] = updatedSegment
            
            // Queue for transcription
            queueSegmentForTranscription(updatedSegment)
        }
        
        Logger.shared.debug("Finalized segment \(segment.segmentIndex)")
    }
    
    private func getCurrentSegment() -> TranscriptionSegment? {
        return segmentQueue.last
    }
    
    // MARK: - Audio File Management
    
    private func createSegmentAudioFile(for segment: TranscriptionSegment) -> URL? {
        let segmentsDirectory = getSegmentsDirectory()
        let fileName = "\(TranscriptionConstants.processedSegmentPrefix)\(segment.sessionId)_\(segment.segmentIndex).m4a"
        let fileURL = segmentsDirectory.appendingPathComponent(fileName)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)
        
        return fileURL
    }
    
    private func setupAudioFileWriter(for fileURL: URL, with config: AudioConfiguration) {
        do {
            guard let format = config.createAVAudioFormat() else {
                Logger.shared.error("Failed to create audio format for segment")
                return
            }
            
            audioFileWriter = try AudioFileWriter(url: fileURL, format: format)
        } catch {
            Logger.shared.error("Failed to setup audio file writer: \(error)")
        }
    }
    
    private func writeBufferToCurrentSegment(_ buffer: AVAudioPCMBuffer) {
        do {
            try audioFileWriter?.write(buffer: buffer)
        } catch {
            Logger.shared.error("Failed to write buffer to segment: \(error)")
        }
    }
    
    private func getSegmentsDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(TranscriptionConstants.segmentDirectoryName)
    }
    
    // MARK: - Timer Management
    
    private func startSegmentTimer() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: TranscriptionConstants.defaultSegmentDuration, repeats: true) { [weak self] _ in
            self?.handleSegmentTimerTick()
        }
    }
    
    private func handleSegmentTimerTick() {
        // This serves as a backup mechanism in case audio buffer processing
        // doesn't trigger segment creation (e.g., during silence)
        let currentSegmentDuration = accumulatedAudioTime - segmentStartTime
        
        if currentSegmentDuration >= TranscriptionConstants.defaultSegmentDuration {
            finalizeCurrentSegmentAndCreateNext()
        }
    }
    
    // MARK: - Transcription Queue
    
    private func queueSegmentForTranscription(_ segment: TranscriptionSegment) {
        // Post notification that segment is ready for transcription
        NotificationCenter.default.post(
            name: .init("segmentReadyForTranscription"),
            object: segment
        )
        
        Logger.shared.info("Queued segment \(segment.segmentIndex) for transcription")
    }
    
    // MARK: - Recording Observers
    
    private func setupRecordingObservers() {
        // Observe recording state changes
        AudioRecordingManager.shared.$currentState
            .sink { [weak self] state in
                self?.handleRecordingStateChange(state)
            }
            .store(in: &cancellables)
        
        // Listen for segment transcription requests
        NotificationCenter.default.addObserver(
            forName: .init("segmentReadyForTranscription"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let segment = notification.object as? TranscriptionSegment {
                self?.handleSegmentReadyForTranscription(segment)
            }
        }
    }
    
    private func handleRecordingStateChange(_ state: RecordingState) {
        switch state {
        case .recording:
            if !isProcessingSegments,
               let session = AudioRecordingManager.shared.currentSession {
                startSegmentation(for: session)
            }
        case .stopped:
            if isProcessingSegments {
                stopSegmentation()
            }
        case .paused:
            // Keep segmentation active but don't create new segments during pause
            break
        default:
            break
        }
    }
    
    private func handleSegmentReadyForTranscription(_ segment: TranscriptionSegment) {
        // This will be handled by TranscriptionManager in Phase 2
        Logger.shared.debug("Segment \(segment.segmentIndex) ready for transcription")
    }
    
    // MARK: - Cleanup
    
    func cleanupSegmentFiles(for sessionId: UUID) {
        let segments = getSegmentsForSession(sessionId)
        
        for segment in segments {
            if let fileURL = segment.audioFileURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        // Remove from queue
        segmentQueue.removeAll { $0.sessionId == sessionId }
        
        Logger.shared.info("Cleaned up segment files for session \(sessionId)")
    }
    
    func getSegmentFileSize(for segment: TranscriptionSegment) -> Int64 {
        guard let fileURL = segment.audioFileURL else { return 0 }
        return fileURL.fileSize
    }
    
    func getTotalSegmentSize(for sessionId: UUID) -> Int64 {
        return getSegmentsForSession(sessionId)
            .compactMap { $0.audioFileURL }
            .reduce(0) { total, url in
                total + url.fileSize
            }
    }
}

// MARK: - Audio File Writer Helper

class AudioFileWriter {
    private let audioFile: AVAudioFile
    private let fileURL: URL
    
    init(url: URL, format: AVAudioFormat) throws {
        self.fileURL = url
        self.audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
    }
    
    func write(buffer: AVAudioPCMBuffer) throws {
        try audioFile.write(from: buffer)
    }
    
    func close() {
        // AVAudioFile will automatically close when deallocated
        Logger.shared.debug("Closed audio file writer for: \(fileURL.lastPathComponent)")
    }
}

// MARK: - Segment Queue Manager

class SegmentQueueManager: ObservableObject {
    static let shared = SegmentQueueManager()
    
    @Published var pendingSegments: [TranscriptionSegment] = []
    @Published var processingSegments: [TranscriptionSegment] = []
    @Published var completedSegments: [TranscriptionSegment] = []
    @Published var failedSegments: [TranscriptionSegment] = []
    
    private let maxConcurrentProcessing = TranscriptionConstants.maxConcurrentTranscriptions
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationObservers()
        loadPersistedQueue()
    }
    
    // MARK: - Queue Management
    
    func addSegment(_ segment: TranscriptionSegment) {
        pendingSegments.append(segment)
        saveQueueState()
        processNextSegment()
    }
    
    func moveSegmentToProcessing(_ segment: TranscriptionSegment) {
        if let index = pendingSegments.firstIndex(where: { $0.id == segment.id }) {
            pendingSegments.remove(at: index)
            processingSegments.append(segment)
            saveQueueState()
        }
    }
    
    func moveSegmentToCompleted(_ segment: TranscriptionSegment) {
        if let index = processingSegments.firstIndex(where: { $0.id == segment.id }) {
            processingSegments.remove(at: index)
            completedSegments.append(segment)
            saveQueueState()
            processNextSegment()
        }
    }
    
    func moveSegmentToFailed(_ segment: TranscriptionSegment) {
        if let index = processingSegments.firstIndex(where: { $0.id == segment.id }) {
            processingSegments.remove(at: index)
            
            if segment.needsRetry {
                // Add back to pending for retry
                pendingSegments.append(segment)
            } else {
                // Move to failed permanently
                failedSegments.append(segment)
            }
            
            saveQueueState()
            processNextSegment()
        }
    }
    
    private func processNextSegment() {
        guard processingSegments.count < maxConcurrentProcessing,
              !pendingSegments.isEmpty else { return }
        
        let nextSegment = pendingSegments.removeFirst()
        moveSegmentToProcessing(nextSegment)
        
        // Notify transcription manager
        NotificationCenter.default.post(
            name: .init("processNextSegment"),
            object: nextSegment
        )
    }
    
    // MARK: - Persistence
    
    private func saveQueueState() {
        let queueState = QueueState(
            pending: pendingSegments,
            processing: processingSegments,
            completed: completedSegments,
            failed: failedSegments
        )
        
        if let encoded = try? JSONEncoder().encode(queueState) {
            UserDefaults.standard.set(encoded, forKey: "segmentQueueState")
        }
    }
    
    private func loadPersistedQueue() {
        guard let data = UserDefaults.standard.data(forKey: "segmentQueueState"),
              let queueState = try? JSONDecoder().decode(QueueState.self, from: data) else {
            return
        }
        
        pendingSegments = queueState.pending
        processingSegments = queueState.processing
        completedSegments = queueState.completed
        failedSegments = queueState.failed
        
        // Reset processing segments to pending on app restart
        pendingSegments.append(contentsOf: processingSegments)
        processingSegments.removeAll()
        
        Logger.shared.info("Loaded persisted segment queue with \(pendingSegments.count) pending segments")
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .init("segmentReadyForTranscription"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let segment = notification.object as? TranscriptionSegment {
                self?.addSegment(segment)
            }
        }
    }
    
    // MARK: - Statistics
    
    var totalSegments: Int {
        return pendingSegments.count + processingSegments.count + completedSegments.count + failedSegments.count
    }
    
    var completionRate: Float {
        guard totalSegments > 0 else { return 0 }
        return Float(completedSegments.count) / Float(totalSegments)
    }
    
    var failureRate: Float {
        guard totalSegments > 0 else { return 0 }
        return Float(failedSegments.count) / Float(totalSegments)
    }
}

// MARK: - Queue State Persistence Model

private struct QueueState: Codable {
    let pending: [TranscriptionSegment]
    let processing: [TranscriptionSegment]
    let completed: [TranscriptionSegment]
    let failed: [TranscriptionSegment]
}
