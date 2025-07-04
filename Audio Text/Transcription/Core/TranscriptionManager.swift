import Foundation
import Combine
import BackgroundTasks
import UIKit

class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    @Published var activeJobs: [TranscriptionJob] = []
    @Published var completedJobs: [TranscriptionJob] = []
    @Published var isProcessing = false
    @Published var currentProgress: Float = 0.0
    @Published var processingStatus = "Ready"
    
    // Service dependencies
    private let openAIService = OpenAITranscriptionService.shared
    private let appleService = AppleTranscriptionService.shared
    private let retryManager = RetryManager.shared
    private let segmentProcessor = AudioSegmentProcessor.shared
    private let queueManager = SegmentQueueManager.shared
    private let networkMonitor = NetworkMonitorService.shared
    
    // Background processing
    private let backgroundTaskService = BackgroundTaskService.shared
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    // Concurrency control
    private let processingQueue = DispatchQueue(label: "transcription.processing", qos: .userInitiated)
    private let maxConcurrentTranscriptions = TranscriptionConstants.maxConcurrentTranscriptions
    private var activeTranscriptionTasks: Set<UUID> = []
    
    // State management
    private var cancellables = Set<AnyCancellable>()
    private var jobTimers: [UUID: Timer] = [:]
    
    private init() {
        setupNotificationObservers()
        setupCombineObservers()
        loadPersistedJobs()
    }
    
    // MARK: - Public Interface
    
    func startTranscriptionJob(for session: RecordingSession) -> TranscriptionJob {
        Logger.shared.info("Starting transcription job for session: \(session.id)")
        
        let job = TranscriptionJob(
            sessionId: session.id,
            preferredService: determinePreferredService(),
            allowFallback: SettingsService.shared.settings.allowServiceFallback
        )
        
        activeJobs.append(job)
        isProcessing = true
        processingStatus = "Starting transcription..."
        
        // Start job monitoring
        startJobMonitoring(for: job)
        
        // Begin background task for continuous processing
        beginBackgroundProcessing()
        
        return job
    }
    
    func stopTranscriptionJob(_ jobId: UUID) {
        Logger.shared.info("Stopping transcription job: \(jobId)")
        
        if let index = activeJobs.firstIndex(where: { $0.id == jobId }) {
            var job = activeJobs[index]
            job.markAsCompleted()
            
            activeJobs.remove(at: index)
            completedJobs.append(job)
            
            // Cancel any pending segments for this job
            cancelPendingSegments(for: job.sessionId)
            
            // Stop job monitoring
            stopJobMonitoring(for: jobId)
        }
        
        updateProcessingState()
    }
    
    func retryFailedSegments(for jobId: UUID) async {
        guard let jobIndex = activeJobs.firstIndex(where: { $0.id == jobId }) else { return }
        
        let job = activeJobs[jobIndex]
        let failedSegments = job.segments.filter { $0.status == .failed && $0.needsRetry }
        
        Logger.shared.info("Retrying \(failedSegments.count) failed segments for job: \(jobId)")
        
        for segment in failedSegments {
            var updatedSegment = segment
            updatedSegment.status = .pending
            queueManager.addSegment(updatedSegment)
        }
    }
    
    func getTranscriptionText(for sessionId: UUID) -> String? {
        // Check active jobs first
        if let activeJob = activeJobs.first(where: { $0.sessionId == sessionId }) {
            return activeJob.fullTranscriptionText.isEmpty ? nil : activeJob.fullTranscriptionText
        }
        
        // Check completed jobs
        if let completedJob = completedJobs.first(where: { $0.sessionId == sessionId }) {
            return completedJob.fullTranscriptionText.isEmpty ? nil : completedJob.fullTranscriptionText
        }
        
        return nil
    }
    
    // MARK: - Segment Processing Workflow
    
    private func processNextSegment(_ segment: TranscriptionSegment) {
        guard activeTranscriptionTasks.count < maxConcurrentTranscriptions else {
            // Queue is full, segment will be processed later
            return
        }
        
        activeTranscriptionTasks.insert(segment.id)
        
        Task {
            await transcribeSegment(segment)
        }
    }
    
    private func transcribeSegment(_ segment: TranscriptionSegment) async {
        Logger.shared.debug("Processing segment \(segment.segmentIndex) for session \(segment.sessionId)")
        
        // Update segment status to processing
        updateSegmentStatus(segment, newStatus: .processing)
        
        do {
            let response = try await performTranscription(segment)
            handleTranscriptionSuccess(segment, response: response)
        } catch {
            handleTranscriptionFailure(segment, error: error)
        }
        
        // Remove from active tasks
        activeTranscriptionTasks.remove(segment.id)
        
        // Update job progress
        updateJobProgress(for: segment.sessionId)
        
        // Process next segment if queue has more
        DispatchQueue.main.async {
            self.processQueuedSegments()
        }
    }
    
    private func performTranscription(_ segment: TranscriptionSegment) async throws -> TranscriptionResponse {
        let services = determineTranscriptionServices(for: segment)
        
        for service in services {
            do {
                let response = try await transcribeWithService(segment, service: service)
                Logger.shared.info("Successfully transcribed segment \(segment.segmentIndex) with \(service.displayName)")
                return response
            } catch {
                Logger.shared.warning("Transcription failed with \(service.displayName): \(error)")
                
                // If this was the last service, throw the error
                if service == services.last {
                    throw error
                }
                
                // Otherwise, continue to next service
                continue
            }
        }
        
        throw TranscriptionError.allServicesFailed
    }
    
    private func transcribeWithService(_ segment: TranscriptionSegment, service: TranscriptionService) async throws -> TranscriptionResponse {
        switch service {
        case .openai:
            return try await openAIService.transcribeSegment(segment)
        case .apple:
            return try await appleService.transcribeSegment(segment)
        case .localWhisper:
            // Would implement local Whisper service here
            throw TranscriptionError.serviceNotImplemented
        case .none:
            throw TranscriptionError.noServiceSelected
        }
    }
    
    // MARK: - Service Selection Logic
    
    private func determinePreferredService() -> TranscriptionService {
        let settings = SettingsService.shared.settings
        
        // Check user preference
        if settings.preferredTranscriptionService != Optional.none {
            return settings.preferredTranscriptionService ?? TranscriptionService.apple
        }
        
        // Auto-select based on availability and network
        if networkMonitor.isConnected && openAIService.isAvailable {
            return .openai
        } else if appleService.isAvailable {
            return .apple
        } else {
            return .none
        }
    }
    
    private func determineTranscriptionServices(for segment: TranscriptionSegment) -> [TranscriptionService] {
        var services: [TranscriptionService] = []
        
        // Get job preferences
        let job = activeJobs.first(where: { $0.sessionId == segment.sessionId })
        let preferredService = job?.preferredService ?? determinePreferredService()
        let allowFallback = job?.allowFallback ?? true
        
        // Add preferred service first
        if isServiceAvailable(preferredService) {
            services.append(preferredService)
        }
        
        // Add fallback services if allowed
        if allowFallback {
            let fallbackServices = TranscriptionConstants.servicePriorityOrder.filter { service in
                service != preferredService && isServiceAvailable(service)
            }
            services.append(contentsOf: fallbackServices)
        }
        
        return services
    }
    
    private func isServiceAvailable(_ service: TranscriptionService) -> Bool {
        switch service {
        case .openai:
            return networkMonitor.isConnected && openAIService.isAvailable
        case .apple:
            return appleService.isAvailable
        case .localWhisper:
            return false // Not implemented yet
        case .none:
            return false
        }
    }
    
    // MARK: - Success/Failure Handling
    
    private func handleTranscriptionSuccess(_ segment: TranscriptionSegment, response: TranscriptionResponse) {
        Logger.shared.info("Transcription successful for segment \(segment.segmentIndex)")
        
        // Update segment with transcription result
        var updatedSegment = segment
        updatedSegment.markAsCompleted(
            text: response.text,
            confidence: response.confidence,
            service: response.service
        )
        
        // Update in queue manager and job
        queueManager.moveSegmentToCompleted(updatedSegment)
        updateJobSegment(updatedSegment)
        
        // Post success notification
        NotificationCenter.default.post(
            name: .init("segmentTranscriptionCompleted"),
            object: updatedSegment
        )
    }
    
    private func handleTranscriptionFailure(_ segment: TranscriptionSegment, error: Error) {
        Logger.shared.error("Transcription failed for segment \(segment.segmentIndex): \(error)")
        
        var updatedSegment = segment
        updatedSegment.markAsFailed(
            error: error.localizedDescription,
            service: .none
        )
        
        // Check if we should retry
        if updatedSegment.needsRetry {
            // Schedule retry with exponential backoff
            retryManager.scheduleRetry(for: updatedSegment) { [weak self] retrySegment in
                self?.queueManager.addSegment(retrySegment)
            }
        } else {
            // Move to failed permanently
            queueManager.moveSegmentToFailed(updatedSegment)
            updateJobSegment(updatedSegment)
            
            // Post failure notification
            NotificationCenter.default.post(
                name: .init("segmentTranscriptionFailed"),
                object: updatedSegment
            )
        }
    }
    
    // MARK: - Job Management
    
    private func updateJobSegment(_ segment: TranscriptionSegment) {
        if let jobIndex = activeJobs.firstIndex(where: { $0.sessionId == segment.sessionId }) {
            activeJobs[jobIndex].updateSegment(segment)
            saveJobsState()
        }
    }
    
    private func updateJobProgress(for sessionId: UUID) {
        guard let jobIndex = activeJobs.firstIndex(where: { $0.sessionId == sessionId }) else { return }
        
        let job = activeJobs[jobIndex]
        let progress = job.progress
        
        DispatchQueue.main.async {
            self.currentProgress = progress
            self.processingStatus = "Transcribing... \(Int(progress * 100))%"
            
            // Check if job is complete
            if job.isCompleted {
                self.completeJob(job)
            }
        }
    }
    
    private func completeJob(_ job: TranscriptionJob) {
        Logger.shared.info("Transcription job completed: \(job.id)")
        
        var completedJob = job
        completedJob.markAsCompleted()
        
        // Move from active to completed
        if let index = activeJobs.firstIndex(where: { $0.id == job.id }) {
            activeJobs.remove(at: index)
        }
        completedJobs.append(completedJob)
        
        // Stop monitoring
        stopJobMonitoring(for: job.id)
        
        // Update processing state
        updateProcessingState()
        
        // Post completion notification
        NotificationCenter.default.post(
            name: .init("transcriptionJobCompleted"),
            object: completedJob
        )
    }
    
    private func startJobMonitoring(for job: TranscriptionJob) {
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.monitorJobProgress(job.id)
        }
        jobTimers[job.id] = timer
    }
    
    private func stopJobMonitoring(for jobId: UUID) {
        jobTimers[jobId]?.invalidate()
        jobTimers.removeValue(forKey: jobId)
    }
    
    private func monitorJobProgress(_ jobId: UUID) {
        guard let job = activeJobs.first(where: { $0.id == jobId }) else { return }
        
        // Check for stalled segments
        let stalledSegments = job.segments.filter { segment in
            segment.status == .processing &&
            Date().timeIntervalSince(segment.createdAt) > TranscriptionConstants.apiTimeout
        }
        
        for segment in stalledSegments {
            Logger.shared.warning("Segment \(segment.segmentIndex) appears stalled, marking for retry")
            handleTranscriptionFailure(segment, error: TranscriptionError.processingTimeout)
        }
    }
    
    // MARK: - Queue Processing
    
    private func processQueuedSegments() {
        let availableSlots = maxConcurrentTranscriptions - activeTranscriptionTasks.count
        guard availableSlots > 0 else { return }
        
        let pendingSegments = Array(queueManager.pendingSegments.prefix(availableSlots))
        
        for segment in pendingSegments {
            queueManager.moveSegmentToProcessing(segment)
            processNextSegment(segment)
        }
    }
    
    private func cancelPendingSegments(for sessionId: UUID) {
        queueManager.pendingSegments.removeAll { $0.sessionId == sessionId }
        queueManager.processingSegments.removeAll { $0.sessionId == sessionId }
    }
    
    private func updateSegmentStatus(_ segment: TranscriptionSegment, newStatus: TranscriptionStatus) {
        var updatedSegment = segment
        updatedSegment.status = newStatus
        
        // Update in appropriate queue
        switch newStatus {
        case .processing:
            queueManager.moveSegmentToProcessing(updatedSegment)
        case .completed:
            queueManager.moveSegmentToCompleted(updatedSegment)
        case .failed:
            queueManager.moveSegmentToFailed(updatedSegment)
        default:
            break
        }
        
        updateJobSegment(updatedSegment)
    }
    
    // MARK: - Background Processing
    
    private func beginBackgroundProcessing() {
        guard backgroundTaskIdentifier == .invalid else { return }
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "TranscriptionProcessing") {
            self.endBackgroundProcessing()
        }
        
        Logger.shared.info("Started background transcription processing")
    }
    
    private func endBackgroundProcessing() {
        guard backgroundTaskIdentifier != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
        
        Logger.shared.info("Ended background transcription processing")
    }
    
    private func updateProcessingState() {
        let hasActiveJobs = !activeJobs.isEmpty
        let hasActiveTranscriptions = !activeTranscriptionTasks.isEmpty
        
        isProcessing = hasActiveJobs || hasActiveTranscriptions
        
        if !isProcessing {
            processingStatus = "Ready"
            currentProgress = 0.0
            endBackgroundProcessing()
        }
    }
    
    // MARK: - Persistence
    
    private func saveJobsState() {
        let jobsData = JobsData(active: activeJobs, completed: completedJobs)
        
        if let encoded = try? JSONEncoder().encode(jobsData) {
            UserDefaults.standard.set(encoded, forKey: "transcriptionJobsState")
        }
    }
    
    private func loadPersistedJobs() {
        guard let data = UserDefaults.standard.data(forKey: "transcriptionJobsState"),
              let jobsData = try? JSONDecoder().decode(JobsData.self, from: data) else {
            return
        }
        
        activeJobs = jobsData.active
        completedJobs = jobsData.completed
        
        // Resume processing for active jobs
        for job in activeJobs {
            startJobMonitoring(for: job)
        }
        
        updateProcessingState()
        Logger.shared.info("Loaded \(activeJobs.count) active transcription jobs")
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Listen for new segments ready for transcription
        NotificationCenter.default.addObserver(
            forName: .init("segmentReadyForTranscription"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let segment = notification.object as? TranscriptionSegment {
                self?.handleNewSegment(segment)
            }
        }
        
        // Listen for queue processing requests
        NotificationCenter.default.addObserver(
            forName: .init("processNextSegment"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let segment = notification.object as? TranscriptionSegment {
                self?.processNextSegment(segment)
            }
        }
        
        // App lifecycle notifications
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillEnterForeground()
        }
    }
    
    private func setupCombineObservers() {
        // Monitor network connectivity changes
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                self?.handleNetworkStatusChange(isConnected)
            }
            .store(in: &cancellables)
    }
    
    private func handleNewSegment(_ segment: TranscriptionSegment) {
        Logger.shared.debug("New segment ready for transcription: \(segment.segmentIndex)")
        
        // Add to appropriate job
        if let jobIndex = activeJobs.firstIndex(where: { $0.sessionId == segment.sessionId }) {
            activeJobs[jobIndex].addSegment(segment)
        }
        
        // Queue for processing
        queueManager.addSegment(segment)
    }
    
    private func handleNetworkStatusChange(_ isConnected: Bool) {
        Logger.shared.info("Network status changed: \(isConnected ? "connected" : "disconnected")")
        
        if isConnected {
            // Resume processing queued segments that require network
            processQueuedSegments()
        } else {
            // Mark network-dependent segments as queued
            let networkDependentSegments = queueManager.processingSegments.filter { segment in
                let job = activeJobs.first(where: { $0.sessionId == segment.sessionId })
                return job?.preferredService.requiresNetwork == true
            }
            
            for segment in networkDependentSegments {
                var queuedSegment = segment
                queuedSegment.markAsQueued()
                updateSegmentStatus(queuedSegment, newStatus: .queued)
            }
        }
    }
    
    private func handleAppDidEnterBackground() {
        Logger.shared.info("App entered background, scheduling background transcription")
        beginBackgroundProcessing()
    }
    
    private func handleAppWillEnterForeground() {
        Logger.shared.info("App entering foreground, resuming transcription processing")
        processQueuedSegments()
    }
}

// MARK: - Supporting Data Structures

private struct JobsData: Codable {
    let active: [TranscriptionJob]
    let completed: [TranscriptionJob]
}

// MARK: - Additional Transcription Errors

extension TranscriptionError {
    static let allServicesFailed = TranscriptionError.apiError("All transcription services failed")
    static let serviceNotImplemented = TranscriptionError.apiError("Service not implemented")
    static let noServiceSelected = TranscriptionError.apiError("No transcription service selected")
}

// MARK: - Settings Extension for Transcription

extension SettingsService {
    var allowServiceFallback: Bool {
        // This would be added to RecordingSettings
        return true // Default to allowing fallback
    }
    
    var preferredTranscriptionService: TranscriptionService? {
        // This would be added to RecordingSettings
        return nil // Auto-select by default
    }
}
