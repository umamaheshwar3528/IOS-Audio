import Foundation
import AVFoundation
import Combine

class OpenAITranscriptionService: ObservableObject {
    static let shared = OpenAITranscriptionService()
    
    @Published var isAvailable = false
    @Published var currentUsage: APIUsage = APIUsage()
    @Published var rateLimitStatus: RateLimitStatus = RateLimitStatus()
    
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let session: URLSession
    private let authManager = AuthenticationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Rate limiting
    private var requestQueue: [TranscriptionRequest] = []
    private var isProcessingQueue = false
    private let maxConcurrentRequests = 3
    private var activeRequests = 0
    
    struct APIUsage {
        var requestsThisMinute = 0
        var requestsThisHour = 0
        var totalRequests = 0
        var lastResetTime = Date()
    }
    
    struct RateLimitStatus {
        var remainingRequests = 50 // OpenAI default
        var resetTime: Date?
        var retryAfter: TimeInterval?
    }
    
    private init() {
        // Configure URLSession for audio uploads
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TranscriptionConstants.apiTimeout
        config.timeoutIntervalForResource = TranscriptionConstants.apiTimeout * 2
        self.session = URLSession(configuration: config)
        
        setupAvailabilityMonitoring()
    }
    
    // MARK: - Public Interface
    
    func transcribeSegment(_ segment: TranscriptionSegment) async throws -> TranscriptionResponse {
        Logger.shared.info("Starting OpenAI transcription for segment \(segment.segmentIndex)")
        
        // Validate API availability
        try await validateAPIAvailability()
        
        // Check rate limits
        try await checkRateLimits()
        
        // Prepare request
        let request = try await prepareTranscriptionRequest(for: segment)
        
        // Execute transcription
        activeRequests += 1
        defer { activeRequests -= 1 }
        
        do {
            let response = try await executeTranscriptionRequest(request)
            updateUsageStats()
            
            Logger.shared.info("Successfully transcribed segment \(segment.segmentIndex)")
            return response
            
        } catch {
            Logger.shared.error("OpenAI transcription failed for segment \(segment.segmentIndex): \(error)")
            throw error
        }
    }
    
    func transcribeAudioData(_ audioData: Data, language: String? = nil) async throws -> TranscriptionResponse {
        let request = TranscriptionRequest(
            audioData: audioData,
            language: language ?? TranscriptionConstants.defaultLanguage,
            prompt: nil,
            temperature: TranscriptionConstants.defaultTemperature,
            format: .m4a
        )
        
        return try await executeTranscriptionRequest(request)
    }
    
    func validateAPIKey() async -> Bool {
        do {
            let testData = createTestAudioData()
            _ = try await transcribeAudioData(testData)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Request Preparation
    
    private func prepareTranscriptionRequest(for segment: TranscriptionSegment) async throws -> TranscriptionRequest {
        guard let audioFileURL = segment.audioFileURL else {
            throw TranscriptionError.missingAudioFile
        }
        
        // Load audio data
        let audioData = try Data(contentsOf: audioFileURL)
        
        // Validate file size
        if audioData.count > TranscriptionConstants.maxFileSize {
            throw TranscriptionError.fileTooLarge
        }
        
        // Get user preferences for language and settings
        let settings = SettingsService.shared.settings
        let language = determineLanguage(for: segment)
        
        return TranscriptionRequest(
            audioData: audioData,
            language: language,
            prompt: generatePrompt(for: segment),
            temperature: TranscriptionConstants.defaultTemperature,
            format: .m4a
        )
    }
    
    private func determineLanguage(for segment: TranscriptionSegment) -> String {
        // Could be enhanced with language detection
        return TranscriptionConstants.defaultLanguage
    }
    
    private func generatePrompt(for segment: TranscriptionSegment) -> String? {
        // Could include context from previous segments
        return nil
    }
    
    // MARK: - API Execution
    
    private func executeTranscriptionRequest(_ request: TranscriptionRequest) async throws -> TranscriptionResponse {
        let startTime = Date()
        
        // Create multipart form data
        let httpRequest = try createHTTPRequest(from: request)
        
        // Execute request with retry logic
        let (data, response) = try await session.data(for: httpRequest)
        
        // Process response
        try validateHTTPResponse(response)
        let apiResponse = try parseTranscriptionResponse(data)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return TranscriptionResponse(
            text: apiResponse.text,
            confidence: nil, // OpenAI doesn't provide confidence scores
            language: apiResponse.language,
            processingTime: processingTime,
            service: .openai,
            segments: apiResponse.segments?.map { segment in
                TranscriptionResponse.TranscriptionSegmentDetail(
                    text: segment.text,
                    startTime: segment.start,
                    endTime: segment.end,
                    confidence: Float(1.0 - segment.noSpeechProb) // Approximate confidence
                )
            }
        )
    }
    
    private func createHTTPRequest(from request: TranscriptionRequest) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw TranscriptionError.invalidURL
        }
        
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        
        // Add authentication header
        guard let apiKey = authManager.openAIAPIKey else {
            throw TranscriptionError.missingAPIKey
        }
        httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        httpRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let httpBody = createMultipartBody(
            audioData: request.audioData,
            language: request.language,
            prompt: request.prompt,
            temperature: request.temperature,
            boundary: boundary
        )
        
        httpRequest.httpBody = httpBody
        
        return httpRequest
    }
    
    private func createMultipartBody(
        audioData: Data,
        language: String?,
        prompt: String?,
        temperature: Float?,
        boundary: String
    ) -> Data {
        var body = Data()
        
        // Model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Language parameter
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Prompt parameter
        if let prompt = prompt {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        // Temperature parameter
        if let temperature = temperature {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(temperature)\r\n".data(using: .utf8)!)
        }
        
        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    // MARK: - Response Processing
    
    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        
        // Update rate limit status from headers
        updateRateLimitStatus(from: httpResponse)
        
        switch httpResponse.statusCode {
        case 200:
            return
        case 400:
            throw TranscriptionError.badRequest
        case 401:
            throw TranscriptionError.unauthorized
        case 429:
            throw TranscriptionError.rateLimitExceeded
        case 500...599:
            throw TranscriptionError.serverError
        default:
            throw TranscriptionError.httpError(httpResponse.statusCode)
        }
    }
    
    private func parseTranscriptionResponse(_ data: Data) throws -> WhisperAPIResponse {
        do {
            return try JSONDecoder().decode(WhisperAPIResponse.self, from: data)
        } catch {
            // Try to parse error response
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw TranscriptionError.apiError(errorResponse.error.message)
            }
            throw TranscriptionError.invalidResponse
        }
    }
    
    private func updateRateLimitStatus(from response: HTTPURLResponse) {
        if let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining-requests"),
           let remainingInt = Int(remaining) {
            rateLimitStatus.remainingRequests = remainingInt
        }
        
        if let resetTime = response.value(forHTTPHeaderField: "x-ratelimit-reset-requests") {
            rateLimitStatus.resetTime = parseRateLimitResetTime(resetTime)
        }
        
        if let retryAfter = response.value(forHTTPHeaderField: "retry-after"),
           let retryAfterInt = TimeInterval(retryAfter) {
            rateLimitStatus.retryAfter = retryAfterInt
        }
    }
    
    private func parseRateLimitResetTime(_ resetString: String) -> Date? {
        // OpenAI returns reset time in different formats
        if let timeInterval = TimeInterval(resetString) {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return nil
    }
    
    // MARK: - Rate Limiting & Availability
    
    private func validateAPIAvailability() async throws {
        guard isAvailable else {
            throw TranscriptionError.serviceUnavailable
        }
        
        guard authManager.hasValidOpenAIKey else {
            throw TranscriptionError.missingAPIKey
        }
    }
    
    private func checkRateLimits() async throws {
        // Check if we've hit rate limits
        if rateLimitStatus.remainingRequests <= 0 {
            if let resetTime = rateLimitStatus.resetTime,
               resetTime > Date() {
                throw TranscriptionError.rateLimitExceeded
            }
        }
        
        // Check if we need to wait due to retry-after header
        if let retryAfter = rateLimitStatus.retryAfter,
           retryAfter > 0 {
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
        }
        
        // Update usage tracking
        updateUsageTracking()
    }
    
    private func updateUsageTracking() {
        let now = Date()
        
        // Reset counters if needed
        if now.timeIntervalSince(currentUsage.lastResetTime) > 3600 { // 1 hour
            currentUsage.requestsThisHour = 0
            currentUsage.lastResetTime = now
        }
        
        if now.timeIntervalSince(currentUsage.lastResetTime) > 60 { // 1 minute
            currentUsage.requestsThisMinute = 0
        }
        
        currentUsage.requestsThisMinute += 1
        currentUsage.requestsThisHour += 1
        currentUsage.totalRequests += 1
    }
    
    private func updateUsageStats() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    private func setupAvailabilityMonitoring() {
        // Monitor network connectivity
        NetworkMonitorService.shared.$isConnected
            .sink { [weak self] isConnected in
                self?.isAvailable = isConnected
            }
            .store(in: &cancellables)
        
        // Monitor API key availability
        authManager.$hasValidOpenAIKey
            .sink { [weak self] hasKey in
                if !hasKey {
                    self?.isAvailable = false
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Test & Utility Methods
    
    private func createTestAudioData() -> Data {
        // Create minimal valid audio data for API key validation
        let sampleRate = 44100.0
        let duration = 1.0
        let frameCount = Int(sampleRate * duration)
        
        var audioData = Data()
        for _ in 0..<frameCount {
            let sample: Int16 = 0 // Silence
            withUnsafeBytes(of: sample.littleEndian) { bytes in
                audioData.append(contentsOf: bytes)
            }
        }
        
        return audioData
    }
    
    func estimateProcessingTime(for audioData: Data) -> TimeInterval {
        // Estimate based on file size and historical data
        let fileSizeMB = Double(audioData.count) / (1024 * 1024)
        return max(2.0, fileSizeMB * 0.5) // Roughly 0.5 seconds per MB
    }
    
    func getServiceStatus() -> (isHealthy: Bool, message: String) {
        if !isAvailable {
            return (false, "Service unavailable")
        }
        
        if rateLimitStatus.remainingRequests <= 5 {
            return (false, "Rate limit approaching")
        }
        
        if activeRequests >= maxConcurrentRequests {
            return (false, "At maximum capacity")
        }
        
        return (true, "Service operational")
    }
}

// MARK: - Transcription Errors

enum TranscriptionError: Error, LocalizedError {
    case missingAudioFile
    case fileTooLarge
    case invalidURL
    case missingAPIKey
    case invalidResponse
    case badRequest
    case unauthorized
    case rateLimitExceeded
    case serverError
    case serviceUnavailable
    case networkUnavailable
    case httpError(Int)
    case apiError(String)
    case processingTimeout
    
    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            return "Audio file not found"
        case .fileTooLarge:
            return "Audio file exceeds maximum size limit (25MB)"
        case .invalidURL:
            return "Invalid API endpoint URL"
        case .missingAPIKey:
            return "OpenAI API key not configured"
        case .invalidResponse:
            return "Invalid response from transcription service"
        case .badRequest:
            return "Invalid request format"
        case .unauthorized:
            return "Invalid or expired API key"
        case .rateLimitExceeded:
            return "API rate limit exceeded. Please try again later"
        case .serverError:
            return "Transcription service temporarily unavailable"
        case .serviceUnavailable:
            return "Transcription service is not available"
        case .networkUnavailable:
            return "No internet connection available"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .processingTimeout:
            return "Transcription request timed out"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .missingAPIKey:
            return "Please add your OpenAI API key in Settings"
        case .rateLimitExceeded:
            return "Wait a few minutes before trying again"
        case .unauthorized:
            return "Check your API key in Settings"
        case .networkUnavailable:
            return "Check your internet connection"
        case .fileTooLarge:
            return "Try recording shorter segments"
        default:
            return "Please try again later"
        }
    }
}
