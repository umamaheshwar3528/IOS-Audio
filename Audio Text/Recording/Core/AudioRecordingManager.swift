import AVFoundation
import Foundation
import Combine
import UIKit

class AudioRecordingManager: ObservableObject {
    static let shared = AudioRecordingManager()
    
    @Published var currentState: RecordingState = .idle
    @Published var currentSession: RecordingSession?
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0
    
    public var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0.0
    private var lastPauseTime: Date?
    private var audioLevelTimer: Timer?
    private var durationTimer: Timer?
    
    // Audio format management
    private var recordingFormat: AVAudioFormat?
    private var inputNode: AVAudioInputNode?
    
    // Audio validation
    private var audioBuffer: AVAudioPCMBuffer?
    private var totalSamplesWritten: AVAudioFrameCount = 0
    private var audioLevelHistory: [Float] = []
    private let maxAudioHistory = 100 // Keep last 100 level readings
    
    // File management
    private var tempFileURL: URL?
    private var finalFileURL: URL?
    
    private let sessionManager = AudioSessionManager.shared
    private let permissionService = AudioPermissionService.shared
    private let fileManagerService = FileManagerService.shared
    private let backgroundTaskService = BackgroundTaskService.shared
    private let interruptionHandler = AudioInterruptionHandler.shared
    private let routeChangeHandler = AudioRouteChangeHandler.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    private lazy var segmentProcessor = AudioSegmentProcessor.shared

    
    private init() {
        setupNotificationObservers()
    }
    
    deinit {
        cleanupRecording()
        audioLevelTimer?.invalidate()
        durationTimer?.invalidate()
    }
    
    // MARK: - Recording Control
    
    func startRecording(with configuration: AudioConfiguration = .compatible) async throws {
        Logger.shared.info("Starting recording with configuration: \(configuration.quality.rawValue)")
        
        // Check current state
        guard currentState == .idle || currentState == .stopped else {
            throw RecordingError.recordingInProgress
        }
        
        // Check permissions
        guard await permissionService.checkAndRequestPermissionIfNeeded() else {
            currentState = .error(.permissionDenied)
            throw RecordingError.permissionDenied
        }
        
        // Check storage
        if fileManagerService.hasInsufficientStorage() {
            currentState = .error(.insufficientStorage)
            throw RecordingError.insufficientStorage
        }
        
        do {
            // Create new session
            let session = RecordingSession(configuration: configuration)
            currentSession = session
            
            // Configure audio session
            try sessionManager.configureSessionForRecording()
            try sessionManager.activateSession()
            
            // Setup audio engine and file with multiple fallback attempts
            var setupSuccess = false
            var lastError: Error?
            
            // Try 1: Requested configuration
            do {
                try await setupAudioEngineAndFile(with: configuration, for: session)
                setupSuccess = true
                Logger.shared.info("Successfully setup with requested configuration")
            } catch {
                lastError = error
                Logger.shared.warning("Failed to setup with requested configuration: \(error)")
                
                // Try 2: Compatible configuration
                let compatibleConfig = AudioConfiguration.compatible
                do {
                    try await setupAudioEngineAndFile(with: compatibleConfig, for: session)
                    setupSuccess = true
                    Logger.shared.info("Successfully setup with compatible configuration")
                } catch {
                    lastError = error
                    Logger.shared.warning("Failed to setup with compatible configuration: \(error)")
                    
                    // Try 3: Simplest possible configuration (input format only)
                    do {
                        try await setupSimplestAudioEngine(for: session)
                        setupSuccess = true
                        Logger.shared.info("Successfully setup with simplest configuration")
                    } catch {
                        lastError = error
                        Logger.shared.error("Failed to setup with simplest configuration: \(error)")
                    }
                }
            }
            
            guard setupSuccess else {
                throw lastError ?? RecordingError.audioEngineStartFailed
            }
            
            // Start background task
            backgroundTaskService.beginBackgroundTask(name: "AudioRecording")
            
            // Start recording
            try startAudioEngineRecording()
            
            // Start segmentation for transcription
            try startRecordingWithSegmentation()
            
            // Reset timers and start recording
            recordingStartTime = Date()
            pausedDuration = 0.0
            lastPauseTime = nil
            recordingDuration = 0.0
            totalSamplesWritten = 0
            audioLevelHistory.removeAll()
            
            // Update state and start timers
            currentState = .recording
            startTimers()
            
            Logger.shared.info("Recording started successfully")
            
        } catch {
            Logger.shared.error("Failed to start recording: \(error)")
            currentState = .error(.audioEngineStartFailed)
            cleanupRecording()
            throw error
        }
    }
    
    // Simplest possible audio setup - use input format directly with no conversion
    private func setupSimplestAudioEngine(for session: RecordingSession) async throws {
        // Initialize audio engine
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else {
            throw RecordingError.audioEngineStartFailed
        }
        
        // Get input node and format - use exactly as-is
        inputNode = engine.inputNode
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        
        Logger.shared.info("Using simplest setup with input format: \(inputFormat)")
        
        // Use input format directly - no conversion at all
        recordingFormat = inputFormat
        
        // Create file URLs
        try createFileURLs(for: session)
        
        // Create and configure AVAudioFile for writing using input format
        guard let tempURL = tempFileURL else {
            throw RecordingError.fileCreationFailed
        }
        
        audioFile = try AVAudioFile(forWriting: tempURL, settings: inputFormat.settings)
        Logger.shared.info("Created audio file with input format directly")
        
        // Create audio buffer for processing
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 1024) else {
            throw RecordingError.audioEngineStartFailed
        }
        audioBuffer = buffer
        
        // Install tap for audio processing - same format throughout
        inputNode!.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBufferDirect(buffer, at: time)
        }
        
        engine.prepare()
        
        Logger.shared.info("Simplest audio engine setup completed successfully")
    }
    
    // Direct audio processing without any format conversion
    private func processAudioBufferDirect(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        // Only process if recording (not paused)
        guard currentState.isRecording else { return }
        
        // Validate buffer
        guard buffer.frameLength > 0 else {
            Logger.shared.warning("Received empty audio buffer")
            return
        }
        
        // Calculate and update audio level
        updateAudioLevel(from: buffer)
        
        // Write audio data directly to file (no conversion)
        writeAudioToFileDirect(buffer)
        
        // Update sample count
        totalSamplesWritten += buffer.frameLength
        
        // Validate we're getting actual audio data
        validateAudioContent(buffer)
    }
    
    // Direct file writing without any format conversion
    private func writeAudioToFileDirect(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile = audioFile else {
            Logger.shared.error("No audio file available for writing")
            return
        }
        
        do {
            // Direct write - buffer and file should have same format
            try audioFile.write(from: buffer)
        } catch {
            Logger.shared.error("Failed to write audio buffer directly: \(error)")
            Logger.shared.error("Buffer format: \(buffer.format)")
            Logger.shared.error("File format: \(audioFile.fileFormat)")
            
            DispatchQueue.main.async {
                self.handleRecordingError(RecordingError.fileWriteFailed)
            }
        }
    }
    
    func stopRecording() -> RecordingSession? {
        Logger.shared.info("Stopping recording")
        
        guard currentState.isRecording || currentState.isPaused else {
            Logger.shared.warning("No active recording to stop")
            return nil
        }
        
        // Stop segmentation first
        segmentProcessor.stopSegmentation()
        
        // Stop audio engine and close file
        stopAudioEngineRecording()
        
        // Calculate final duration
        if let startTime = recordingStartTime {
            let totalDuration = Date().timeIntervalSince(startTime) - pausedDuration
            recordingDuration = totalDuration
        }
        
        // Finalize and validate the recording
        guard var session = currentSession else {
            Logger.shared.error("No current session to finalize")
            return nil
        }
        
        do {
            // Move temp file to final location and validate
            try finalizeRecordingFile()
            
            // Update session with final file info
            session.endTime = Date()
            if let fileURL = finalFileURL {
                session.fileURL = fileURL
                session.fileSize = AudioFileManager.shared.getFileSize(at: fileURL)
                
                // Validate the audio file
                try validateRecordedAudio(at: fileURL)
                
                Logger.shared.info("Audio file validated successfully. Size: \(session.fileSize) bytes, Samples: \(totalSamplesWritten)")
            }
            
            // Save to file manager
            fileManagerService.saveRecording(session)
            
            // Update state
            currentState = .stopped
            stopTimers()
            cleanupRecording()
            
            // Post notification
            NotificationCenter.default.post(name: .recordingSessionCompleted, object: session)
            
            Logger.shared.info("Recording stopped successfully. Duration: \(session.formattedDuration)")
            
            let completedSession = session
            currentSession = nil
            return completedSession
            
        } catch {
            Logger.shared.error("Failed to finalize recording: \(error)")
            currentState = .error(.fileCreationFailed)
            cleanupRecording()
            return nil
        }
    }
    
    func pauseRecording() {
        guard currentState.isRecording else { return }
        
        audioEngine?.pause()
        
        // Flush any pending audio data
        flushAudioBuffers()
        
        currentState = .paused
        lastPauseTime = Date()
        
        // Stop the duration timer but keep audio level timer for UI
        durationTimer?.invalidate()
        durationTimer = nil
        
        Logger.shared.info("Recording paused")
    }
    
    func resumeRecording() {
        guard currentState.isPaused else { return }
        
        do {
            try audioEngine?.start()
            
            // Calculate paused duration
            if let pauseTime = lastPauseTime {
                pausedDuration += Date().timeIntervalSince(pauseTime)
                lastPauseTime = nil
            }
            
            currentState = .recording
            
            // Restart duration timer
            startDurationTimer()
            
            Logger.shared.info("Recording resumed")
        } catch {
            Logger.shared.error("Failed to resume recording: \(error)")
            currentState = .error(.audioEngineStartFailed)
        }
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngineAndFile(with configuration: AudioConfiguration, for session: RecordingSession) async throws {
        // Initialize audio engine
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else {
            throw RecordingError.audioEngineStartFailed
        }
        
        // Get input node and format
        inputNode = engine.inputNode
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        
        Logger.shared.info("Input format: \(inputFormat)")
        Logger.shared.info("Input format details - Sample Rate: \(inputFormat.sampleRate), Channels: \(inputFormat.channelCount), Format: \(inputFormat.commonFormat.rawValue)")
        
        // For maximum compatibility, prefer using the input format directly
        var finalRecordingFormat: AVAudioFormat = inputFormat
        
        // Only try custom format if user specifically requested high quality and formats are compatible
        if configuration.quality == .high {
            if let targetFormat = configuration.createAVAudioFormat() {
                Logger.shared.info("Requested format: \(targetFormat)")
                Logger.shared.info("Requested format details - Sample Rate: \(targetFormat.sampleRate), Channels: \(targetFormat.channelCount)")
                
                // Test if we can reliably convert between formats
                if testAudioConversion(from: inputFormat, to: targetFormat) {
                    Logger.shared.info("Format conversion validated successfully, using requested format")
                    finalRecordingFormat = targetFormat
                } else {
                    Logger.shared.warning("Format conversion test failed, using input format for maximum compatibility")
                    finalRecordingFormat = inputFormat
                }
            } else {
                Logger.shared.warning("Failed to create requested format, using input format")
                finalRecordingFormat = inputFormat
            }
        } else {
            Logger.shared.info("Using input format directly for maximum compatibility")
            finalRecordingFormat = inputFormat
        }
        
        recordingFormat = finalRecordingFormat
        
        // Create file URLs
        try createFileURLs(for: session)
        
        // Create and configure AVAudioFile for writing
        guard let tempURL = tempFileURL else {
            throw RecordingError.fileCreationFailed
        }
        
        // Create the audio file with the final recording format
        do {
            audioFile = try AVAudioFile(forWriting: tempURL, settings: finalRecordingFormat.settings)
            Logger.shared.info("Created audio file successfully with format: \(finalRecordingFormat)")
        } catch {
            Logger.shared.error("Failed to create audio file with format \(finalRecordingFormat): \(error)")
            
            // Fallback: try creating with a basic PCM format
            let fallbackFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            do {
                audioFile = try AVAudioFile(forWriting: tempURL, settings: fallbackFormat.settings)
                recordingFormat = fallbackFormat
                Logger.shared.info("Created audio file with fallback format: \(fallbackFormat)")
            } catch {
                Logger.shared.error("Failed to create audio file even with fallback format: \(error)")
                throw RecordingError.fileCreationFailed
            }
        }
        
        // Create audio buffer for processing - use input format for the tap
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 1024) else {
            throw RecordingError.audioEngineStartFailed
        }
        audioBuffer = buffer
        
        // Install tap for audio processing using input format
        inputNode!.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, at: time)
        }
        
        engine.prepare()
        
        Logger.shared.info("Audio engine and file setup completed successfully")
        Logger.shared.info("Final recording format: \(recordingFormat!)")
        Logger.shared.info("Input format equals recording format: \(areFormatsCompatible(inputFormat, recordingFormat!))")
        Logger.shared.info("Temp file: \(tempURL.path)")
    }
    
    private func createFileURLs(for session: RecordingSession) throws {
        // Create temp file URL in temp directory
        let tempDirectory = AudioFileManager.shared.tempDirectory
        let tempFileName = "temp_recording_\(session.id.uuidString).m4a"
        tempFileURL = tempDirectory.appendingPathComponent(tempFileName)
        
        // Create final file URL
        finalFileURL = try fileManagerService.createRecordingFile(for: session)
        
        // Ensure temp directory exists
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        
        Logger.shared.info("Created file URLs - Temp: \(tempFileURL!.path), Final: \(finalFileURL!.path)")
    }
    
    private func startAudioEngineRecording() throws {
        guard let engine = audioEngine else {
            throw RecordingError.audioEngineStartFailed
        }
        
        try engine.start()
        Logger.shared.info("Audio engine started successfully")
    }
    
    private func stopAudioEngineRecording() {
        // Stop the engine first
        audioEngine?.stop()
        
        // Remove tap to prevent further callbacks
        if let inputNode = inputNode {
            inputNode.removeTap(onBus: 0)
        }
        
        // Flush any remaining audio data
        flushAudioBuffers()
        
        // Close the audio file properly
        closeAudioFile()
        
        // Cleanup
        audioEngine = nil
        inputNode = nil
        recordingFormat = nil
        audioBuffer = nil
        
        backgroundTaskService.endBackgroundTask()
        sessionManager.deactivateSession()
        
        Logger.shared.info("Audio engine stopped and cleaned up")
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        // Only process if recording (not paused)
        guard currentState.isRecording else { return }
        
        // Validate buffer
        guard buffer.frameLength > 0 else {
            Logger.shared.warning("Received empty audio buffer")
            return
        }
        
        // Calculate and update audio level
        updateAudioLevel(from: buffer)
        
        // Forward buffer to segment processor for transcription preparation
        if let session = currentSession {
            let currentTime = Date().timeIntervalSince(recordingStartTime ?? Date()) - pausedDuration
            segmentProcessor.processAudioBuffer(buffer, timestamp: currentTime)
        }
        
        // Check if we need format conversion for main recording
        guard let targetFormat = recordingFormat else {
            Logger.shared.error("No recording format available")
            return
        }
        
        if areFormatsCompatible(buffer.format, targetFormat) {
            // Direct write if formats are compatible
            writeAudioToFileDirect(buffer)
        } else {
            // Try conversion, fall back to direct if it fails
            writeAudioToFile(buffer)
        }
        
        // Update sample count
        totalSamplesWritten += buffer.frameLength
        
        // Validate we're getting actual audio data
        validateAudioContent(buffer)
    }
    
    private func startRecordingWithSegmentation() throws {
        guard let session = currentSession else { return }
        
        // Start the segment processor
        segmentProcessor.startSegmentation(for: session)
        
        Logger.shared.info("Started audio segmentation for transcription")
    }
    
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        var peak: Float = 0.0
        
        for i in 0..<frameLength {
            let sample = abs(channelData[i])
            sum += sample
            peak = max(peak, sample)
        }
        
        let averageLevel = frameLength > 0 ? sum / Float(frameLength) : 0.0
        let decibelLevel = averageLevel > 0 ? 20 * log10(averageLevel) : AudioConstants.silenceThreshold
        
        // Store audio level for validation
        audioLevelHistory.append(peak)
        if audioLevelHistory.count > maxAudioHistory {
            audioLevelHistory.removeFirst()
        }
        
        DispatchQueue.main.async {
            self.audioLevel = max(decibelLevel, AudioConstants.silenceThreshold)
        }
    }
    
    private func writeAudioToFile(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile = audioFile else {
            Logger.shared.error("No audio file available for writing")
            return
        }
        
        guard let targetFormat = recordingFormat else {
            Logger.shared.error("No target recording format available")
            return
        }
        
        do {
            // Check if format conversion is needed
            if areFormatsCompatible(buffer.format, targetFormat) {
                // Direct write if formats are compatible
                try audioFile.write(from: buffer)
            } else {
                // Log format mismatch for debugging
                Logger.shared.debug("Format conversion needed: Input[\(buffer.format.sampleRate)Hz, \(buffer.format.channelCount)ch, \(buffer.format.commonFormat.rawValue)] -> Target[\(targetFormat.sampleRate)Hz, \(targetFormat.channelCount)ch, \(targetFormat.commonFormat.rawValue)]")
                
                // Convert buffer format to target format
                if let convertedBuffer = convertBuffer(buffer, to: targetFormat) {
                    // Verify the converted buffer format matches exactly
                    if areFormatsCompatible(convertedBuffer.format, targetFormat) {
                        try audioFile.write(from: convertedBuffer)
                    } else {
                        Logger.shared.error("Converted buffer format still doesn't match target format")
                        Logger.shared.error("Converted: \(convertedBuffer.format)")
                        Logger.shared.error("Target: \(targetFormat)")
                        
                        // Fallback: try direct write anyway (may work if differences are minor)
                        Logger.shared.warning("Attempting direct write as fallback")
                        try audioFile.write(from: buffer)
                    }
                } else {
                    Logger.shared.error("Failed to convert audio buffer format - attempting direct write as fallback")
                    // Fallback: try direct write (may work if the format difference is minor)
                    try audioFile.write(from: buffer)
                }
            }
        } catch {
            Logger.shared.error("Failed to write audio buffer: \(error)")
            Logger.shared.error("Buffer format: \(buffer.format)")
            Logger.shared.error("Target format: \(targetFormat)")
            
            // Last resort: skip this buffer and continue recording
            Logger.shared.warning("Skipping this audio buffer to continue recording")
            return
        }
    }
    
    private func areFormatsCompatible(_ format1: AVAudioFormat, _ format2: AVAudioFormat) -> Bool {
        let basicCompatibility = format1.sampleRate == format2.sampleRate &&
               format1.channelCount == format2.channelCount &&
               format1.commonFormat == format2.commonFormat
        
        // Also check format settings if available
        if let settings1 = format1.settings as? [String: Any],
           let settings2 = format2.settings as? [String: Any] {
            
            let formatID1 = settings1[AVFormatIDKey] as? AudioFormatID
            let formatID2 = settings2[AVFormatIDKey] as? AudioFormatID
            
            if let id1 = formatID1, let id2 = formatID2, id1 != id2 {
                Logger.shared.debug("Format IDs differ: \(id1) vs \(id2)")
                return false
            }
        }
        
        return basicCompatibility
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            Logger.shared.error("Could not create audio converter from \(buffer.format) to \(targetFormat)")
            return nil
        }
        
        // Calculate the target frame capacity with proper math and buffer space
        let sampleRateRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let baseFrameCapacity = Double(buffer.frameLength) * sampleRateRatio
        
        // Add 50% buffer space to account for converter requirements and rounding
        let targetFrameCapacity = AVAudioFrameCount(ceil(baseFrameCapacity * 1.5))
        
        // Ensure minimum capacity (at least as large as input buffer)
        let minimumCapacity = max(targetFrameCapacity, buffer.frameLength * 2)
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                    frameCapacity: minimumCapacity) else {
            Logger.shared.error("Could not create converted buffer with capacity \(minimumCapacity)")
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        do {
            let status = try converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            switch status {
            case .haveData:
                Logger.shared.debug("Successfully converted buffer: \(buffer.frameLength) -> \(convertedBuffer.frameLength) frames")
                return convertedBuffer
//            case .noDataNow:
//                Logger.shared.warning("Audio converter returned noDataNow")
//                return nil
            case .error:
                Logger.shared.error("Audio conversion error: \(error?.localizedDescription ?? "Unknown error")")
                return nil
            case .inputRanDry:
                Logger.shared.debug("Audio converter input ran dry")
                return convertedBuffer.frameLength > 0 ? convertedBuffer : nil
            case .endOfStream:
                Logger.shared.debug("Audio converter reached end of stream")
                return convertedBuffer.frameLength > 0 ? convertedBuffer : nil
            @unknown default:
                Logger.shared.error("Unknown audio conversion status: \(status.rawValue)")
                return nil
            }
        } catch {
            Logger.shared.error("Audio format conversion failed: \(error)")
            return nil
        }
    }
    
    // Test method to validate conversion capability
    private func testAudioConversion(from inputFormat: AVAudioFormat, to targetFormat: AVAudioFormat) -> Bool {
        // If formats are already compatible, no conversion needed
        if areFormatsCompatible(inputFormat, targetFormat) {
            return true
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Logger.shared.error("Cannot create converter from \(inputFormat) to \(targetFormat)")
            return false
        }
        
        // Create a small test buffer with actual data
        guard let testBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 256) else {
            Logger.shared.error("Cannot create test buffer")
            return false
        }
        
        testBuffer.frameLength = 256
        
        // Fill with test audio data (sine wave)
        if let channelData = testBuffer.floatChannelData?[0] {
            for i in 0..<Int(testBuffer.frameLength) {
                channelData[i] = sin(Float(i) * 0.1) * 0.1 // Quiet sine wave
            }
        }
        
        // Try to convert it
        let convertedBuffer = convertBuffer(testBuffer, to: targetFormat)
        let success = convertedBuffer != nil && convertedBuffer!.frameLength > 0
        
        if success {
            Logger.shared.info("Audio conversion test passed")
        } else {
            Logger.shared.error("Audio conversion test failed")
        }
        
        return success
    }
    
    private func validateAudioContent(_ buffer: AVAudioPCMBuffer) {
        // Check if we're getting actual audio content (not just silence)
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        var hasContent = false
        
        for i in 0..<frameLength {
            if abs(channelData[i]) > 0.001 { // Threshold for meaningful audio
                hasContent = true
                break
            }
        }
        
        if !hasContent && totalSamplesWritten > 44100 { // After 1 second of recording
            Logger.shared.warning("Recording appears to contain only silence")
        }
    }
    
    private func flushAudioBuffers() {
        // Ensure all pending audio data is written to file
        // AVAudioFile handles this internally, but we can trigger a sync
        if let audioFile = audioFile {
            // Force any pending writes to complete
            // This is done automatically by AVAudioFile, but we log it for visibility
            Logger.shared.debug("Flushing audio buffers to disk")
        }
    }
    
    private func closeAudioFile() {
        guard audioFile != nil else { return }
        
        Logger.shared.info("Closing audio file. Total samples written: \(totalSamplesWritten)")
        
        // AVAudioFile closes automatically when deallocated
        // But we explicitly set to nil to trigger deallocation
        audioFile = nil
    }
    
    // MARK: - File Management
    
    private func finalizeRecordingFile() throws {
        guard let tempURL = tempFileURL,
              let finalURL = finalFileURL else {
            throw RecordingError.fileCreationFailed
        }
        
        // Verify temp file exists and has content
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw RecordingError.fileCreationFailed
        }
        
        let fileSize = AudioFileManager.shared.getFileSize(at: tempURL)
        guard fileSize > 0 else {
            throw RecordingError.fileCreationFailed
        }
        
        // Move temp file to final location
        try AudioFileManager.shared.moveFromTemp(tempURL: tempURL, to: finalURL)
        
        Logger.shared.info("Successfully moved recording from temp to final location. Size: \(fileSize) bytes")
        
        // Clean up temp file reference
        tempFileURL = nil
    }
    
    private func validateRecordedAudio(at fileURL: URL) throws {
        // Validate that the audio file is readable and contains actual audio
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            
            // Check basic properties
            guard audioFile.length > 0 else {
                throw RecordingError.fileCreationFailed
            }
            
            // Check if we have reasonable audio duration
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            guard duration > 0.1 else { // At least 100ms
                throw RecordingError.fileCreationFailed
            }
            
            // Validate audio content by reading first few frames
            let frameCount = min(audioFile.length, 4096) // Read first 4096 frames
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                              frameCapacity: AVAudioFrameCount(frameCount)) else {
                throw RecordingError.fileCreationFailed
            }
            
            try audioFile.read(into: buffer)
            
            // Check if buffer contains actual audio data
            var hasAudioData = false
            if let channelData = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) {
                    if abs(channelData[i]) > 0.0001 {
                        hasAudioData = true
                        break
                    }
                }
            }
            
            // Also check our historical audio levels
            let hasRecordedAudio = audioLevelHistory.contains { $0 > 0.01 }
            
            if !hasAudioData && !hasRecordedAudio {
                Logger.shared.warning("Audio file validation: No significant audio content detected")
                // Don't throw error here - might be a very quiet recording
            }
            
            Logger.shared.info("Audio file validation successful - Duration: \(String(format: "%.2f", duration))s, Frames: \(audioFile.length)")
            
        } catch {
            Logger.shared.error("Audio file validation failed: \(error)")
            throw RecordingError.fileCorrupted
        }
    }
    
    // MARK: - Timers (FIXED)
    
    private func startTimers() {
        startAudioLevelTimer()
        startDurationTimer()
    }
    
    private func startAudioLevelTimer() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: AudioConstants.levelMeterUpdateInterval, repeats: true) { _ in
            // Audio level is updated in processAudioBuffer, just post notification
            NotificationCenter.default.post(name: .audioLevelUpdated, object: self.audioLevel)
        }
    }
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        
        // Ensure timer is scheduled on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create and schedule timer on main run loop
            self.durationTimer = Timer.scheduledTimer(
                withTimeInterval: 0.1,
                repeats: true
            ) { _ in
                self.updateRecordingDuration()
            }
            
            // Add to common mode to work during UI tracking
            RunLoop.current.add(self.durationTimer!, forMode: .common)
        }
    }
    
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        let currentDuration = Date().timeIntervalSince(startTime) - pausedDuration
        
        // Direct update since we're already on main thread
        self.recordingDuration = max(0, currentDuration)
        
        if self.recordingDuration >= AudioConstants.maxRecordingDuration {
            self.stopRecording()
        }
    }
    
    private func stopTimers() {
        // Invalidate timers on main thread
        DispatchQueue.main.async { [weak self] in
            self?.audioLevelTimer?.invalidate()
            self?.durationTimer?.invalidate()
            self?.audioLevelTimer = nil
            self?.durationTimer = nil
        }
    }
    
    // MARK: - Error Handling
    
    func handleRecordingError(_ error: Error) {
        Logger.shared.error("Recording error: \(error)")
        
        let recordingError: RecordingError
        if let recError = error as? RecordingError {
            recordingError = recError
        } else {
            recordingError = .unknown(error.localizedDescription)
        }
        
        currentState = .error(recordingError)
        cleanupRecording()
        
        NotificationCenter.default.post(name: .recordingStateChanged, object: recordingError)
    }
    
    // MARK: - Cleanup
    
    private func cleanupRecording() {
        stopTimers()
        audioLevel = 0.0
        recordingStartTime = nil
        pausedDuration = 0.0
        lastPauseTime = nil
        recordingDuration = 0.0
        totalSamplesWritten = 0
        audioLevelHistory.removeAll()
        
        // Clean up file URLs
        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempFileURL = nil
        }
        finalFileURL = nil
        
        backgroundTaskService.endBackgroundTask()
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // App lifecycle
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            if self.currentState.isRecording {
                self.interruptionHandler.prepareForInterruption()
            }
        }
        
        // Background recording warning
        NotificationCenter.default.addObserver(
            forName: .init("backgroundRecordingWarning"),
            object: nil,
            queue: .main
        ) { notification in
            if let timeRemaining = notification.object as? TimeInterval {
                Logger.shared.warning("Background recording time remaining: \(timeRemaining)")
            }
        }
        
        // Background recording expired
        NotificationCenter.default.addObserver(
            forName: .init("backgroundRecordingExpired"),
            object: nil,
            queue: .main
        ) { _ in
            Logger.shared.warning("Background recording time expired")
            if self.currentState.isRecording {
                _ = self.stopRecording()
            }
        }
    }
    
    // MARK: - Public Utility Methods
    
    func getCurrentRecordingInfo() -> (duration: TimeInterval, sampleCount: AVAudioFrameCount, audioLevel: Float) {
        return (recordingDuration, totalSamplesWritten, audioLevel)
    }
    
    func hasValidAudioContent() -> Bool {
        return totalSamplesWritten > 0 && audioLevelHistory.contains { $0 > 0.01 }
    }
}

// MARK: - Additional Recording Errors

extension RecordingError {
    static let fileWriteFailed = RecordingError.unknown("Failed to write audio data to file")
    static let fileCorrupted = RecordingError.unknown("Audio file is corrupted or invalid")
}
