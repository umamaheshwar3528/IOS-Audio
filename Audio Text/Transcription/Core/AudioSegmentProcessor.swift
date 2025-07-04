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
    
    // Enhanced audio management
    private var tempSegmentURL: URL?
    private var segmentAudioFormat: AVAudioFormat?
    private var segmentSampleCount: AVAudioFrameCount = 0
    
    // Dependencies
    private let fileManager = AudioFileManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // FIXED: Flag to track if recording observers are setup
    private var recordingObserversSetup = false
    
    private init() {
        Logger.shared.info("AudioSegmentProcessor initialized")
        
        // FIXED: Setup observers after a delay to ensure both singletons are initialized
        DispatchQueue.main.async { [weak self] in
            self?.setupRecordingObserversIfNeeded()
        }
    }
    
    deinit {
        stopSegmentation()
    }
    
    // MARK: - Safe Observer Setup
        
    private func setupRecordingObserversIfNeeded() {
        guard !recordingObserversSetup else { return }
            
        recordingObserversSetup = true
            
        // FIXED: Now safe to observe AudioRecordingManager
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
        
        Logger.shared.info("Recording observers setup completed")
    }
        
    
    // MARK: - Public Interface
    
    func startSegmentation(for session: RecordingSession) {
        Logger.shared.info("Starting audio segmentation for session: \(session.id)")
        
        currentRecordingSession = session
        currentSegmentIndex = 0
        segmentStartTime = 0
        accumulatedAudioTime = 0
        segmentSampleCount = 0
        isProcessingSegments = true
        
        // FIXED: Use a more compatible audio format for segments
        // Instead of using session configuration directly, use input format from recording
        segmentAudioFormat = createCompatibleSegmentFormat()
        
        // Create first segment
        createNewSegment()
        
        // Start timer for automatic segmentation
        startSegmentTimer()
    }
    
    private func createCompatibleSegmentFormat() -> AVAudioFormat? {
        // Try to get the actual recording format from AudioRecordingManager
        // If not available, fall back to a standard format
        if let recordingManager = AudioRecordingManager.shared.audioEngine,
           recordingManager.isRunning {
            let inputFormat = recordingManager.inputNode.outputFormat(forBus: 0)
            Logger.shared.info("Using input format for segments: \(inputFormat)")
            return inputFormat
        }
            
        // Fallback to a standard format that's widely compatible
        let standardFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        Logger.shared.info("Using standard fallback format for segments: \(standardFormat!)")
        return standardFormat
    }
    
    func stopSegmentation() {
        Logger.shared.info("Stopping audio segmentation")
        
        segmentTimer?.invalidate()
        segmentTimer = nil
        
        // Finalize current segment if it exists
        if let currentSegment = getCurrentSegment() {
            finalizeSegment(currentSegment)
        }
        
        // Cleanup
        closeCurrentAudioWriter()
        currentRecordingSession = nil
        segmentAudioFormat = nil
        isProcessingSegments = false
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, timestamp: TimeInterval) {
            // Ensure observers are setup
            setupRecordingObserversIfNeeded()
            
            guard isProcessingSegments,
                  let session = currentRecordingSession else {
                Logger.shared.debug("Not processing segments or no session available")
                return
            }
            
            // Validate buffer
            guard buffer.frameLength > 0 else {
                Logger.shared.warning("Received empty audio buffer in segment processor")
                return
            }
            
            // Update accumulated time
            let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
            accumulatedAudioTime += bufferDuration
            
            Logger.shared.debug("📊 Processing audio buffer: \(buffer.frameLength) frames, duration: \(String(format: "%.3f", bufferDuration))s, accumulated: \(String(format: "%.3f", accumulatedAudioTime))s")
            
            // Write audio to current segment file
            writeBufferToCurrentSegment(buffer)
            
            // Update sample count
            segmentSampleCount += buffer.frameLength
            
            // Check if segment duration threshold is reached
            let currentSegmentDuration = accumulatedAudioTime - segmentStartTime
            if currentSegmentDuration >= TranscriptionConstants.defaultSegmentDuration {
                Logger.shared.info("Segment duration threshold reached: \(String(format: "%.3f", currentSegmentDuration))s")
                finalizeCurrentSegmentAndCreateNext()
            }
        }
    
    func getSegmentsForSession(_ sessionId: UUID) -> [TranscriptionSegment] {
        return segmentQueue.filter { $0.sessionId == sessionId }
    }
    
    // MARK: - Segment Management
    
    private func createNewSegment() {
        guard let session = currentRecordingSession,
              let audioFormat = segmentAudioFormat else { return }
        
        let segmentStartTime = self.segmentStartTime
        let segmentEndTime = segmentStartTime + TranscriptionConstants.defaultSegmentDuration
        
        var segment = TranscriptionSegment(
            sessionId: session.id,
            segmentIndex: currentSegmentIndex,
            startTime: segmentStartTime,
            endTime: segmentEndTime
        )
        
        // Create audio file for this segment
        do {
            let segmentFileURL = try createSegmentAudioFile(for: segment)
            segment.audioFileURL = segmentFileURL
            segmentQueue.append(segment)
            
            // Setup audio file writer
            try setupAudioFileWriter(for: segmentFileURL, with: audioFormat)
            
            // Reset segment sample count
            segmentSampleCount = 0
            
            Logger.shared.debug("Created new segment \(currentSegmentIndex) for session \(session.id)")
        } catch {
            Logger.shared.error("Failed to create segment \(currentSegmentIndex): \(error)")
        }
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
        Logger.shared.debug("Finalizing segment \(segment.segmentIndex)")
        
        // Close current audio file writer and get validation info
        let (wasSuccessful, actualSamples) = closeCurrentAudioWriterWithInfo()
        
        // Update segment with actual end time and validation status
        if let index = segmentQueue.firstIndex(where: { $0.id == segment.id }) {
            var updatedSegment = segment
            updatedSegment.endTime = accumulatedAudioTime
            
            Logger.shared.info("Segment \(segment.segmentIndex) validation - Success: \(wasSuccessful), Samples: \(actualSamples), Duration: \(String(format: "%.3f", updatedSegment.duration))s")
            
            // Validate the segment file
            if wasSuccessful,
               actualSamples > 0,
               let audioFileURL = updatedSegment.audioFileURL {
                do {
                    try fileManager.validateAudioFile(at: audioFileURL)
                    let fileSize = fileManager.getFileSize(at: audioFileURL)
                    
                    segmentQueue[index] = updatedSegment
                    
                    // Queue for transcription only if validation passed
                    queueSegmentForTranscription(updatedSegment)
                    
                    Logger.shared.info("Segment \(segment.segmentIndex) finalized successfully - Size: \(fileSize) bytes, Duration: \(String(format: "%.3f", updatedSegment.duration))s")
                } catch {
                    Logger.shared.error("Segment \(segment.segmentIndex) validation failed: \(error)")
                    cleanupSegmentFile(updatedSegment)
                }
            } else {
                Logger.shared.error("Segment \(segment.segmentIndex) was not written successfully - Success: \(wasSuccessful), Samples: \(actualSamples)")
                cleanupSegmentFile(updatedSegment)
            }
        }
    }
    
    private func closeCurrentAudioWriterWithInfo() -> (success: Bool, samples: AVAudioFrameCount) {
        guard let writer = audioFileWriter else {
            return (false, 0)
        }
        
        let actualSamples = segmentSampleCount
        let success = writer.close()
        audioFileWriter = nil
        
        // Validate the written file if we have a temp URL
        if let tempURL = tempSegmentURL {
            let fileSize = fileManager.getFileSize(at: tempURL)
            Logger.shared.debug("Closed segment file writer. File size: \(fileSize) bytes, Samples written: \(actualSamples)")
            
            if fileSize > 0 && actualSamples > 0 {
                tempSegmentURL = nil
                return (true, actualSamples)
            } else {
                Logger.shared.warning("Segment file appears empty after writing - Size: \(fileSize), Samples: \(actualSamples)")
                // Clean up empty file
                try? FileManager.default.removeItem(at: tempURL)
                tempSegmentURL = nil
                return (false, actualSamples)
            }
        }
        
        return (success && actualSamples > 0, actualSamples)
    }
    
    private func getCurrentSegment() -> TranscriptionSegment? {
        return segmentQueue.last
    }
    
    // MARK: - Audio File Management
    
    private func createSegmentAudioFile(for segment: TranscriptionSegment) throws -> URL {
        let segmentsDirectory = getSegmentsDirectory()
        let fileName = "\(TranscriptionConstants.processedSegmentPrefix)\(segment.sessionId.uuidString.prefix(8))_\(segment.segmentIndex).m4a"
        let fileURL = segmentsDirectory.appendingPathComponent(fileName)
        
        // Ensure directory exists
        try FileManager.default.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Store temp URL for cleanup if needed
        tempSegmentURL = fileURL
        
        Logger.shared.debug("Created segment file URL: \(fileURL.path)")
        return fileURL
    }
    
    private func setupAudioFileWriter(for fileURL: URL, with format: AVAudioFormat) throws {
        // Close any existing writer first
        closeCurrentAudioWriter()
        
        // Create new audio file writer
        audioFileWriter = try AudioFileWriter(url: fileURL, format: format)
        tempSegmentURL = fileURL
        
        Logger.shared.debug("Setup audio file writer for: \(fileURL.lastPathComponent)")
    }
    
    private func writeBufferToCurrentSegment(_ buffer: AVAudioPCMBuffer) {
            guard let writer = audioFileWriter else {
                Logger.shared.error("No audio file writer available for segment")
                return
            }
            
            do {
                try writer.write(buffer: buffer)
                Logger.shared.debug("Wrote \(buffer.frameLength) frames to segment")
            } catch {
                Logger.shared.error("Failed to write buffer to segment: \(error)")
                
                // Try to recreate the writer with the buffer's format if conversion failed
                if error.localizedDescription.contains("frameCapacity") ||
                   error.localizedDescription.contains("conversion") {
                    Logger.shared.info("Attempting to recreate audio file writer with buffer format")
                    recreateWriterWithBufferFormat(buffer)
                }
            }
        }
        
        private func recreateWriterWithBufferFormat(_ buffer: AVAudioPCMBuffer) {
            guard let currentSegment = getCurrentSegment() else { return }
            
            do {
                // Close current writer
                closeCurrentAudioWriter()
                
                // Create new writer using the buffer's format directly
                Logger.shared.info("Recreating writer with buffer format: \(buffer.format)")
                try setupAudioFileWriter(for: currentSegment.audioFileURL!, with: buffer.format)
                
                // Update our segment format to match
                segmentAudioFormat = buffer.format
                
                // Try writing again
                try audioFileWriter?.write(buffer: buffer)
                Logger.shared.info("Successfully recreated writer and wrote buffer")
                
            } catch {
                Logger.shared.error("Failed to recreate audio file writer with buffer format: \(error)")
            }
        }
    
    private func closeCurrentAudioWriter() -> Bool {
        guard let writer = audioFileWriter else { return false }
        
        let success = writer.close()
        audioFileWriter = nil
        
        // Validate the written file if we have a temp URL
        if let tempURL = tempSegmentURL {
            let fileSize = fileManager.getFileSize(at: tempURL)
            Logger.shared.debug("Closed segment file writer. File size: \(fileSize) bytes, Samples written: \(segmentSampleCount)")
            
            if fileSize > 0 && segmentSampleCount > 0 {
                tempSegmentURL = nil
                return true
            } else {
                Logger.shared.warning("Segment file appears empty after writing")
                // Clean up empty file
                try? FileManager.default.removeItem(at: tempURL)
                tempSegmentURL = nil
                return false
            }
        }
        
        return success
    }
    
    private func cleanupSegmentFile(_ segment: TranscriptionSegment) {
        if let fileURL = segment.audioFileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
            Logger.shared.debug("Cleaned up invalid segment file: \(fileURL.lastPathComponent)")
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
            // Only create new segment if we have some audio content
            if segmentSampleCount > 0 {
                finalizeCurrentSegmentAndCreateNext()
            } else {
                Logger.shared.debug("Skipping segment creation due to no audio content")
            }
        }
    }
    
    // MARK: - Transcription Queue
    
    private func queueSegmentForTranscription(_ segment: TranscriptionSegment) {
        // Additional validation before queuing
        guard let audioFileURL = segment.audioFileURL else {
            Logger.shared.error("Cannot queue segment without audio file URL")
            return
        }
        
        let fileSize = fileManager.getFileSize(at: audioFileURL)
        guard fileSize > 0 else {
            Logger.shared.error("Cannot queue segment with empty audio file")
            return
        }
        
        // Post notification that segment is ready for transcription
        NotificationCenter.default.post(
            name: .init("segmentReadyForTranscription"),
            object: segment
        )
        
        Logger.shared.info("Queued segment \(segment.segmentIndex) for transcription (Size: \(fileSize) bytes)")
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
        // This will be handled by TranscriptionManager
        Logger.shared.debug("Segment \(segment.segmentIndex) ready for transcription")
    }
    
    // MARK: - Cleanup
    
    func cleanupSegmentFiles(for sessionId: UUID) {
        let segments = getSegmentsForSession(sessionId)
        var cleanedCount = 0
        var cleanedSize: Int64 = 0
        
        for segment in segments {
            if let fileURL = segment.audioFileURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                let fileSize = fileManager.getFileSize(at: fileURL)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    cleanedCount += 1
                    cleanedSize += fileSize
                } catch {
                    Logger.shared.error("Failed to cleanup segment file \(fileURL.lastPathComponent): \(error)")
                }
            }
        }
        
        // Remove from queue
        segmentQueue.removeAll { $0.sessionId == sessionId }
        
        Logger.shared.info("Cleaned up \(cleanedCount) segment files for session \(sessionId), freed \(ByteCountFormatter.string(fromByteCount: cleanedSize, countStyle: .file))")
    }
    
    func getSegmentFileSize(for segment: TranscriptionSegment) -> Int64 {
        guard let fileURL = segment.audioFileURL else { return 0 }
        return fileManager.getFileSize(at: fileURL)
    }
    
    func getTotalSegmentSize(for sessionId: UUID) -> Int64 {
        return getSegmentsForSession(sessionId)
            .compactMap { $0.audioFileURL }
            .reduce(0) { total, url in
                total + fileManager.getFileSize(at: url)
            }
    }
    
    // MARK: - Diagnostics
    
    func getProcessingStatistics() -> SegmentProcessingStats {
        let totalSegments = segmentQueue.count
        let validSegments = segmentQueue.filter { segment in
            guard let url = segment.audioFileURL else { return false }
            return fileManager.getFileSize(at: url) > 0
        }.count
        
        return SegmentProcessingStats(
            totalSegments: totalSegments,
            validSegments: validSegments,
            invalidSegments: totalSegments - validSegments,
            isCurrentlyProcessing: isProcessingSegments,
            currentSegmentIndex: currentSegmentIndex,
            accumulatedTime: accumulatedAudioTime
        )
    }
}

// MARK: - Enhanced Audio File Writer

class AudioFileWriter {
    private var audioFile: AVAudioFile?
    private let fileURL: URL
    private let format: AVAudioFormat
    private var samplesWritten: AVAudioFrameCount = 0
    private var isValidFile = false
    private var writeCount = 0
    
    init(url: URL, format: AVAudioFormat) throws {
        self.fileURL = url
        self.format = format
        
        Logger.shared.debug("Creating audio file writer for: \(url.lastPathComponent) with format: \(format)")
        
        // Create the audio file
        do {
            self.audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            Logger.shared.debug("Created audio file writer successfully")
        } catch {
            Logger.shared.error("Failed to create audio file writer: \(error)")
            throw error
        }
    }
    
    func write(buffer: AVAudioPCMBuffer) throws {
        guard let audioFile = audioFile else {
            Logger.shared.error("Attempting to write to closed audio file")
            throw AudioFileError.fileNotFound
        }
            
        writeCount += 1
        
        // Validate buffer has content
        guard buffer.frameLength > 0 else {
            Logger.shared.warning("Attempting to write empty buffer")
            return
        }
        
        // Log occasional write operations for debugging
        if writeCount % 10 == 1 {
            Logger.shared.debug("Writing buffer \(writeCount): \(buffer.frameLength) frames, format: \(buffer.format)")
        }
            
        // Validate buffer format compatibility
        if !buffer.format.isEqual(format) {
            Logger.shared.debug("Format conversion needed for write operation")
            // Attempt format conversion if needed
            if let convertedBuffer = convertBuffer(buffer, to: format) {
                try audioFile.write(from: convertedBuffer)
                samplesWritten += convertedBuffer.frameLength
                Logger.shared.debug("Converted and wrote \(convertedBuffer.frameLength) frames")
            } else {
                Logger.shared.error("Failed to convert buffer format for writing")
                throw AudioFileError.invalidAudioFormat
            }
        } else {
            // Direct write if formats match
            try audioFile.write(from: buffer)
            samplesWritten += buffer.frameLength
                
            if writeCount % 10 == 1 {
                Logger.shared.debug("Direct write successful: \(buffer.frameLength) frames")
            }
        }
            
        isValidFile = true
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            Logger.shared.error("Could not create audio converter")
            return nil
        }
        
        let targetFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) *
                                                   targetFormat.sampleRate / buffer.format.sampleRate)
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                    frameCapacity: targetFrameCapacity) else {
            Logger.shared.error("Could not create converted buffer")
            return nil
        }
        
        do {
            try converter.convert(to: convertedBuffer, from: buffer)
            return convertedBuffer
        } catch {
            Logger.shared.error("Audio format conversion failed: \(error)")
            return nil
        }
    }
    
    func close() -> Bool {
        defer {
            audioFile = nil
        }
        
        guard let audioFile = audioFile else {
            Logger.shared.warning("Attempted to close already closed audio file")
            return false
        }
        
        // AVAudioFile will automatically close when deallocated
        let success = isValidFile && samplesWritten > 0
        
        Logger.shared.debug("Closed audio file writer for: \(fileURL.lastPathComponent), samples written: \(samplesWritten), valid: \(success)")
        
        return success
    }
    
    var fileSize: Int64 {
        return AudioFileManager.shared.getFileSize(at: fileURL)
    }
    
    var isValid: Bool {
        return isValidFile && samplesWritten > 0
    }
}

// MARK: - Segment Processing Statistics

struct SegmentProcessingStats {
    let totalSegments: Int
    let validSegments: Int
    let invalidSegments: Int
    let isCurrentlyProcessing: Bool
    let currentSegmentIndex: Int
    let accumulatedTime: TimeInterval
    
    var validationRate: Double {
        guard totalSegments > 0 else { return 0 }
        return Double(validSegments) / Double(totalSegments)
    }
    
    var averageSegmentDuration: TimeInterval {
        guard validSegments > 0 else { return 0 }
        return accumulatedTime / Double(validSegments)
    }
}

// MARK: - Segment Queue Manager (Enhanced)

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
        // Validate segment before adding
        guard validateSegmentForQueue(segment) else {
            Logger.shared.error("Segment \(segment.segmentIndex) failed validation, not adding to queue")
            return
        }
        
        pendingSegments.append(segment)
        saveQueueState()
        processNextSegment()
    }
    
    private func validateSegmentForQueue(_ segment: TranscriptionSegment) -> Bool {
        // Check if audio file exists and is valid
        guard let audioFileURL = segment.audioFileURL else {
            Logger.shared.error("Segment has no audio file URL")
            return false
        }
        
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            Logger.shared.error("Segment audio file does not exist: \(audioFileURL.path)")
            return false
        }
        
        let fileSize = AudioFileManager.shared.getFileSize(at: audioFileURL)
        guard fileSize > 0 else {
            Logger.shared.error("Segment audio file is empty")
            return false
        }
        
        // Try to validate audio file format
        do {
            try AudioFileManager.shared.validateAudioFile(at: audioFileURL)
            return true
        } catch {
            Logger.shared.error("Segment audio file validation failed: \(error)")
            return false
        }
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
        
        // Validate persisted segments before restoring
        pendingSegments = queueState.pending.filter { validateSegmentForQueue($0) }
        processingSegments = queueState.processing.filter { validateSegmentForQueue($0) }
        completedSegments = queueState.completed
        failedSegments = queueState.failed
        
        // Reset processing segments to pending on app restart
        pendingSegments.append(contentsOf: processingSegments)
        processingSegments.removeAll()
        
        Logger.shared.info("Loaded persisted segment queue with \(pendingSegments.count) valid pending segments")
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
