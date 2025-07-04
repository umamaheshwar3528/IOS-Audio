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
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0.0
    private var lastPauseTime: Date?
    private var audioLevelTimer: Timer?
    private var durationTimer: Timer?
    
    private let sessionManager = AudioSessionManager.shared
    private let permissionService = AudioPermissionService.shared
    private let fileManagerService = FileManagerService.shared
    private let backgroundTaskService = BackgroundTaskService.shared
    private let interruptionHandler = AudioInterruptionHandler.shared
    private let routeChangeHandler = AudioRouteChangeHandler.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationObservers()
    }
    
    deinit {
        stopRecording()
        audioLevelTimer?.invalidate()
        durationTimer?.invalidate()
    }
    
    // MARK: - Recording Control
    
    func startRecording(with configuration: AudioConfiguration = .default) async throws {
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
            
            // Setup audio engine
            try await setupAudioEngine(with: configuration)
            
            // Create file
            let fileURL = try fileManagerService.createRecordingFile(for: session)
            currentSession?.fileURL = fileURL
            
            // Start background task
            backgroundTaskService.beginBackgroundTask(name: "AudioRecording")
            
            // Start recording
            try startAudioEngineRecording()
            
            // Reset timers and start recording
            recordingStartTime = Date()
            pausedDuration = 0.0
            lastPauseTime = nil
            recordingDuration = 0.0
            
            // Update state and start timers
            currentState = .recording
            startTimers()
            
            Logger.shared.info("Recording started successfully")
            
        } catch {
            Logger.shared.error("Failed to start recording: \(error)")
            currentState = .error(.audioEngineStartFailed)
            cleanup()
            throw error
        }
    }
    
    func stopRecording() -> RecordingSession? {
        Logger.shared.info("Stopping recording")
        
        guard currentState.isRecording || currentState.isPaused else {
            Logger.shared.warning("No active recording to stop")
            return nil
        }
        
        // Stop audio engine
        stopAudioEngineRecording()
        
        // Calculate final duration
        if let startTime = recordingStartTime {
            let totalDuration = Date().timeIntervalSince(startTime) - pausedDuration
            recordingDuration = totalDuration
        }
        
        // Update session
        if var session = currentSession {
            session.endTime = Date()
            if let fileURL = session.fileURL {
                session.fileSize = AudioFileManager.shared.getFileSize(at: fileURL)
            }
            
            // Save to file manager
            fileManagerService.saveRecording(session)
            
            // Update state
            currentState = .stopped
            stopTimers()
            cleanup()
            
            // Post notification
            NotificationCenter.default.post(name: .recordingSessionCompleted, object: session)
            
            Logger.shared.info("Recording stopped successfully. Duration: \(session.formattedDuration)")
            
            let completedSession = session
            currentSession = nil
            return completedSession
        }
        
        return nil
    }
    
    func pauseRecording() {
        guard currentState.isRecording else { return }
        
        audioEngine?.pause()
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
    
    private func setupAudioEngine(with configuration: AudioConfiguration) async throws {
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine,
              let format = configuration.createAVAudioFormat() else {
            throw RecordingError.audioEngineStartFailed
        }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap for audio level monitoring and recording
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, at: time)
        }
        
        engine.prepare()
    }
    
    private func startAudioEngineRecording() throws {
        guard let engine = audioEngine,
              let session = currentSession,
              let fileURL = session.fileURL,
              let format = session.configuration.createAVAudioFormat() else {
            throw RecordingError.audioEngineStartFailed
        }
        
        // Create audio file
        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        
        try engine.start()
    }
    
    private func stopAudioEngineRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioFile = nil
        audioEngine = nil
        
        backgroundTaskService.endBackgroundTask()
        sessionManager.deactivateSession()
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        // Write to file only if recording (not paused)
        if currentState.isRecording, let audioFile = audioFile {
            do {
                try audioFile.write(from: buffer)
            } catch {
                Logger.shared.error("Failed to write audio buffer: \(error)")
            }
        }
        
        // Calculate audio level (always, for UI feedback)
        if let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0.0
            
            for i in 0..<frameLength {
                sum += abs(channelData[i])
            }
            
            let averageLevel = sum / Float(frameLength)
            let decibelLevel = averageLevel > 0 ? 20 * log10(averageLevel) : AudioConstants.silenceThreshold
            
            DispatchQueue.main.async {
                self.audioLevel = max(decibelLevel, AudioConstants.silenceThreshold)
            }
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
        cleanup()
        
        NotificationCenter.default.post(name: .recordingStateChanged, object: recordingError)
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        stopTimers()
        audioLevel = 0.0
        recordingStartTime = nil
        pausedDuration = 0.0
        lastPauseTime = nil
        recordingDuration = 0.0
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
}
