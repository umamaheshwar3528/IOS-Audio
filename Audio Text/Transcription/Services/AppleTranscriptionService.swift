import Foundation
import Speech
import AVFoundation
import Combine

class AppleTranscriptionService: NSObject, ObservableObject {
    static let shared = AppleTranscriptionService()
    
    @Published var isAvailable = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var supportedLocales: [Locale] = []
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var currentLocale: Locale = Locale(identifier: "en-US")
    private let audioEngine = AVAudioEngine()
    private var recognitionTasks: [UUID: SFSpeechRecognitionTask] = [:]
    
    // Performance tracking
    private var processingStats = ProcessingStats()
    
    struct ProcessingStats {
        var totalRequests = 0
        var successfulRequests = 0
        var averageProcessingTime: TimeInterval = 0
        var lastProcessingTime = Date()
    }
    
    private override init() {
        super.init()
        setupSpeechRecognizer()
        checkAvailability()
    }
    
    // MARK: - Public Interface
    
    func transcribeSegment(_ segment: TranscriptionSegment) async throws -> TranscriptionResponse {
        Logger.shared.info("Starting Apple Speech transcription for segment \(segment.segmentIndex)")
        
        let startTime = Date()
        
        // Validate availability
        try validateServiceAvailability()
        
        // Load audio file
        guard let audioFileURL = segment.audioFileURL else {
            throw AppleSpeechError.missingAudioFile
        }
        
        // Perform transcription
        let result = try await transcribeAudioFile(audioFileURL)
        
        let processingTime = Date().timeIntervalSince(startTime)
        updateProcessingStats(processingTime: processingTime, success: true)
        
        Logger.shared.info("Successfully transcribed segment \(segment.segmentIndex) with Apple Speech")
        
        return TranscriptionResponse(
            text: result.transcription,
            confidence: result.confidence,
            language: currentLocale.identifier,
            processingTime: processingTime,
            service: .apple,
            segments: result.segments?.map { segment in
                TranscriptionResponse.TranscriptionSegmentDetail(
                    text: segment.text,
                    startTime: segment.timestamp,
                    endTime: segment.timestamp + segment.duration,
                    confidence: segment.confidence
                )
            }
        )
    }
    
    func transcribeAudioFile(_ audioFileURL: URL) async throws -> AppleSpeechResult {
        return try await withCheckedThrowingContinuation { continuation in
            transcribeAudioFile(audioFileURL) { result in
                switch result {
                case .success(let speechResult):
                    continuation.resume(returning: speechResult)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    self.updateAvailability()
                    continuation.resume(returning: status)
                }
            }
        }
    }
    
    func setLanguage(_ locale: Locale) throws {
        guard supportedLocales.contains(locale) else {
            throw AppleSpeechError.unsupportedLanguage(locale.identifier)
        }
        
        currentLocale = locale
        setupSpeechRecognizer()
    }
    
    // MARK: - Speech Recognition Setup
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        speechRecognizer?.delegate = self
        
        // Update supported locales
        supportedLocales = SFSpeechRecognizer.supportedLocales().sorted { locale1, locale2 in
            locale1.identifier < locale2.identifier
        }
        
        updateAvailability()
    }
    
    private func checkAvailability() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        updateAvailability()
    }
    
    private func updateAvailability() {
        isAvailable = authorizationStatus == .authorized &&
                     speechRecognizer?.isAvailable == true
    }
    
    // MARK: - Core Transcription Logic
    
    private func transcribeAudioFile(
        _ audioFileURL: URL,
        completion: @escaping (Result<AppleSpeechResult, Error>) -> Void
    ) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            completion(.failure(AppleSpeechError.recognizerUnavailable))
            return
        }
        
        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = determineOnDeviceRequirement()
        
        // Configure request for better accuracy
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // Start recognition task
        let taskId = UUID()
        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognitionResult(
                taskId: taskId,
                result: result,
                error: error,
                completion: completion
            )
        }
        
        recognitionTasks[taskId] = recognitionTask
    }
    
    private func handleRecognitionResult(
        taskId: UUID,
        result: SFSpeechRecognitionResult?,
        error: Error?,
        completion: @escaping (Result<AppleSpeechResult, Error>) -> Void
    ) {
        defer {
            recognitionTasks.removeValue(forKey: taskId)
        }
        
        if let error = error {
            Logger.shared.error("Apple Speech recognition failed: \(error)")
            completion(.failure(AppleSpeechError.recognitionFailed(error.localizedDescription)))
            updateProcessingStats(processingTime: 0, success: false)
            return
        }
        
        guard let result = result else {
            completion(.failure(AppleSpeechError.noResult))
            return
        }
        
        // Process the result
        let speechResult = processRecognitionResult(result)
        completion(.success(speechResult))
    }
    
    private func processRecognitionResult(_ result: SFSpeechRecognitionResult) -> AppleSpeechResult {
        let bestTranscription = result.bestTranscription
        
        // Break down complex confidence calculation
        let confidenceValues = bestTranscription.segments.map { $0.confidence }
        let confidenceSum = confidenceValues.reduce(0, +)
        let averageConfidence = Double(confidenceSum) / Double(bestTranscription.segments.count)
        let confidence = Float(averageConfidence)
        
        // Extract segments with timing information
        let segments = bestTranscription.segments.map { segment in
            AppleSpeechResult.AppleSpeechSegment(
                text: segment.substring,
                confidence: Float(segment.confidence),
                timestamp: segment.timestamp,
                duration: segment.duration
            )
        }
        
        return AppleSpeechResult(
            transcription: bestTranscription.formattedString,
            confidence: confidence,
            isFinal: result.isFinal,
            segments: segments
        )
    }
    
    // MARK: - Configuration Helpers
    
    private func determineOnDeviceRequirement() -> Bool {
        // Use on-device recognition when possible for privacy
        // and when network is not available
        if #available(iOS 13.0, *) {
            return !NetworkMonitorService.shared.isConnected ||
                   SettingsService.shared.settings.preferLocalProcessing
        }
        return false
    }
    
    private func validateServiceAvailability() throws {
        guard authorizationStatus == .authorized else {
            throw AppleSpeechError.authorizationDenied
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }
        
        // Check device capabilities
        if determineOnDeviceRequirement() && !recognizer.supportsOnDeviceRecognition {
            throw AppleSpeechError.onDeviceNotSupported
        }
    }
    
    // MARK: - Performance Monitoring
    
    private func updateProcessingStats(processingTime: TimeInterval, success: Bool) {
        processingStats.totalRequests += 1
        
        if success {
            processingStats.successfulRequests += 1
            
            // Update rolling average
            let totalTime = processingStats.averageProcessingTime * Double(processingStats.successfulRequests - 1)
            processingStats.averageProcessingTime = (totalTime + processingTime) / Double(processingStats.successfulRequests)
        }
        
        processingStats.lastProcessingTime = Date()
    }
    
    // MARK: - Utility Methods
    
    func getServiceStatus() -> (isHealthy: Bool, message: String) {
        switch authorizationStatus {
        case .notDetermined:
            return (false, "Speech recognition permission not requested")
        case .denied, .restricted:
            return (false, "Speech recognition permission denied")
        case .authorized:
            break
        @unknown default:
            return (false, "Unknown authorization status")
        }
        
        guard let recognizer = speechRecognizer else {
            return (false, "Speech recognizer not available")
        }
        
        if !recognizer.isAvailable {
            return (false, "Speech recognizer temporarily unavailable")
        }
        
        if recognitionTasks.count >= 5 { // Arbitrary limit
            return (false, "Too many concurrent recognition tasks")
        }
        
        return (true, "Service operational")
    }
    
    func getProcessingStats() -> ProcessingStats {
        return processingStats
    }
    
    func cancelAllTasks() {
        for (_, task) in recognitionTasks {
            task.cancel()
        }
        recognitionTasks.removeAll()
    }
    
    func estimateProcessingTime(for audioFileURL: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: audioFileURL)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            
            // Apple Speech is generally faster than audio duration
            return min(duration * 0.3, 10.0) // Max 10 seconds processing time
        } catch {
            return 5.0 // Default estimate
        }
    }
    
    // MARK: - Language Support
    
    func getSupportedLanguages() -> [String] {
        return supportedLocales.map { $0.identifier }
    }
    
    func isLanguageSupported(_ languageCode: String) -> Bool {
        return supportedLocales.contains { $0.identifier.hasPrefix(languageCode) }
    }
    
    func getBestMatchingLocale(for languageCode: String) -> Locale? {
        return supportedLocales.first { $0.identifier.hasPrefix(languageCode) }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension AppleTranscriptionService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            self.updateAvailability()
            Logger.shared.info("Apple Speech recognizer availability changed: \(available)")
        }
    }
}

// MARK: - Apple Speech Errors

enum AppleSpeechError: Error, LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case missingAudioFile
    case unsupportedLanguage(String)
    case recognitionFailed(String)
    case noResult
    case onDeviceNotSupported
    case audioFileCorrupted
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission denied"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .missingAudioFile:
            return "Audio file not found"
        case .unsupportedLanguage(let language):
            return "Language '\(language)' is not supported"
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        case .noResult:
            return "No transcription result received"
        case .onDeviceNotSupported:
            return "On-device recognition is not supported on this device"
        case .audioFileCorrupted:
            return "Audio file is corrupted or unreadable"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authorizationDenied:
            return "Please enable Speech Recognition in Settings"
        case .recognizerUnavailable:
            return "Try again in a few moments"
        case .missingAudioFile:
            return "Ensure the audio file exists and is accessible"
        case .unsupportedLanguage:
            return "Choose a supported language in Settings"
        case .recognitionFailed:
            return "Check audio quality and try again"
        case .noResult:
            return "Try re-recording with clearer audio"
        case .onDeviceNotSupported:
            return "Use cloud-based recognition or upgrade device"
        case .audioFileCorrupted:
            return "Re-record the audio segment"
        }
    }
}

// MARK: - Settings Extension

extension SettingsService {
    var preferLocalProcessing: Bool {
        // This would be added to RecordingSettings
        return true // Default to local processing for privacy
    }
}
