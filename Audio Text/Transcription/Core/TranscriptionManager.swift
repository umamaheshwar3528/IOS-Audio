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
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    // Concurrency control
    private let processingQueue = DispatchQueue(label: "transcription.processing", qos: .userInitiated)
    private let maxConcurrentTranscriptions = TranscriptionConstants.maxConcurrentTranscriptions
    private var activeTranscriptionTasks: Set<UUID> = []
    private let activeTasksQueue = DispatchQueue(label: "transcription.activeTasks", attributes: .concurrent)
    
    // State management
    private var cancellables = Set<AnyCancellable>()
    private var jobTimers: [UUID: Timer] = [:]
    private let jobTimersQueue = DispatchQueue(label: "transcription.jobTimers", attributes: .concurrent)
    
    // Track segments being processed to prevent duplicate processing
    private var processingSegments: Set<UUID> = []
    private let processingSegmentsQueue = DispatchQueue(label: "transcription.processingSegments", attributes: .concurrent)
    
    private init() {
        setupNotificationObservers()
        setupCombineObservers()
        loadPersistedJobs()
    }
    
    // MARK: - Public Interface
    
    func startTranscriptionJob(for session: RecordingSession) -> TranscriptionJob {
        Logger.shared.info("Starting transcription job for session: \(session.id)")
        
        // Check if job already exists
        if let existingJob = activeJobs.first(where: { $0.sessionId == session.id }) {
            Logger.shared.info("Job already exists for session: \(session.id)")
            return existingJob
        }
        
        let job = TranscriptionJob(
            sessionId: session.id,
            preferredService: determinePreferredService(),
            allowFallback: SettingsService.shared.settings.allowServiceFallback
        )
        
        // Update on main thread
        DispatchQueue.main.async { [weak self] in
            self?.activeJobs.append(job)
            self?.isProcessing = true
            self?.processingStatus = "Starting transcription..."
        }
        
        // Start job monitoring
        startJobMonitoring(for: job)
        
        // Begin background task for continuous processing
        beginBackgroundProcessing()
        
        // Trigger immediate segment processing if segments are already available
        processExistingSegments(for: session.id)
        
        // Save state
        saveJobsState()
        
        return job
    }
    
    func stopTranscriptionJob(_ sessionId: UUID) {
        Logger.shared.info("Stopping transcription job for session: \(sessionId)")
        
        if let index = activeJobs.firstIndex(where: { $0.sessionId == sessionId }) {
            var job = activeJobs[index]
            job.markAsCompleted()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activeJobs.remove(at: index)
                self.completedJobs.append(job)
            }
            
            // Cancel any pending segments for this job
            cancelPendingSegments(for: sessionId)
            
            // Stop job monitoring
            stopJobMonitoring(for: job.id)
        }
        
        updateProcessingState()
        saveJobsState()
    }
    
    func retryFailedSegments(for jobId: UUID) async {
        guard let jobIndex = activeJobs.firstIndex(where: { $0.id == jobId }) else {
            Logger.shared.warning("Job not found for retry: \(jobId)")
            return
        }
        
        let job = activeJobs[jobIndex]
        let failedSegments = job.segments.filter { $0.status == .failed && $0.needsRetry }
        
        Logger.shared.info("Retrying \(failedSegments.count) failed segments for job: \(jobId)")
        
        for segment in failedSegments {
            var updatedSegment = segment
            updatedSegment.status = .pending
            updatedSegment.errorMessage = nil
            queueManager.addSegment(updatedSegment)
        }
    }
    
    func getTranscriptionText(for sessionId: UUID) -> String? {
        // Check completed jobs first (they have finalized text)
        if let completedJob = completedJobs.first(where: { $0.sessionId == sessionId }) {
            let text = completedJob.fullTranscriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        
        // Check active jobs
        if let activeJob = activeJobs.first(where: { $0.sessionId == sessionId }) {
            let text = activeJob.fullTranscriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        
        return nil
    }
    
    // MARK: - Segment Processing Workflow
    
    private func processExistingSegments(for sessionId: UUID) {
        // Check if there are already segments for this session in the queue
        let existingSegments = queueManager.pendingSegments.filter { $0.sessionId == sessionId }
        
        if !existingSegments.isEmpty {
            Logger.shared.info("Found \(existingSegments.count) existing segments for session \(sessionId)")
            
            // Add segments to the job
            if let jobIndex = activeJobs.firstIndex(where: { $0.sessionId == sessionId }) {
                for segment in existingSegments {
                    activeJobs[jobIndex].addSegment(segment)
                }
            }
            
            // Start processing
            processQueuedSegments()
        }
    }
    
    private func processNextSegment(_ segment: TranscriptionSegment) {
        // Check if we're already processing this segment
        let isAlreadyProcessing = processingSegmentsQueue.sync {
            return processingSegments.contains(segment.id)
        }
        
        if isAlreadyProcessing {
            Logger.shared.debug("Segment \(segment.segmentIndex) is already being processed, skipping")
            return
        }
        
        let currentTaskCount = activeTasksQueue.sync { activeTranscriptionTasks.count }
        guard currentTaskCount < maxConcurrentTranscriptions else {
            Logger.shared.debug("Max concurrent transcriptions reached, queuing segment \(segment.segmentIndex)")
            return
        }
        
        // Mark as processing
        processingSegmentsQueue.async(flags: .barrier) { [weak self] in
            self?.processingSegments.insert(segment.id)
        }
        
        activeTasksQueue.async(flags: .barrier) { [weak self] in
            self?.activeTranscriptionTasks.insert(segment.id)
        }
        
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
        
        // Remove from active tasks and processing segments
        activeTasksQueue.async(flags: .barrier) { [weak self] in
            self?.activeTranscriptionTasks.remove(segment.id)
        }
        
        processingSegmentsQueue.async(flags: .barrier) { [weak self] in
            self?.processingSegments.remove(segment.id)
        }
        
        // Update job progress
        await updateJobProgress(for: segment.sessionId)
        
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
                
                // Check if this is a permanent failure
                if isPermanentFailure(error) {
                    throw error
                }
                
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
    
    private func isPermanentFailure(_ error: Error) -> Bool {
        if let appleSpeechError = error as? AppleSpeechError {
            switch appleSpeechError {
            case .recognitionFailed(let message):
                // "No speech detected" should be permanent
                return message.contains("No speech detected") || message.contains("no speech")
            case .authorizationDenied, .recognizerUnavailable:
                return true
            default:
                return false
            }
        }
        
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .missingAudioFile, .fileTooLarge, .unauthorized:
                return true
            default:
                return false
            }
        }
        
        return false
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
        if let preferredService = settings.preferredTranscriptionService {
            return preferredService
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
        
        // Mark retry as successful if this was a retry
        retryManager.markRetrySuccessful(for: segment.id)
        
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
        
        // Check if this is a permanent failure or if we've exceeded retry attempts
        let isPermanent = isPermanentFailure(error) || !updatedSegment.needsRetry
        
        if isPermanent {
            // Move to failed permanently
            queueManager.moveSegmentToFailed(updatedSegment)
            updateJobSegment(updatedSegment)
            retryManager.markRetryPermanentlyFailed(for: segment.id)
            
            Logger.shared.info("Segment \(segment.segmentIndex) marked as permanently failed: \(error.localizedDescription)")
            
            // Post failure notification
            NotificationCenter.default.post(
                name: .init("segmentTranscriptionFailed"),
                object: updatedSegment
            )
        } else {
            // Schedule retry with exponential backoff
            retryManager.scheduleRetry(for: updatedSegment) { [weak self] retrySegment in
                self?.queueManager.addSegment(retrySegment)
            }
        }
    }
    
    // MARK: - Job Management
    
    private func updateJobSegment(_ segment: TranscriptionSegment) {
        if let jobIndex = activeJobs.firstIndex(where: { $0.sessionId == segment.sessionId }) {
            activeJobs[jobIndex].updateSegment(segment)
            
            // Trigger UI update on main thread
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
            
            saveJobsState()
        }
    }
    
    private func updateJobProgress(for sessionId: UUID) async {
        guard let jobIndex = activeJobs.firstIndex(where: { $0.sessionId == sessionId }) else { return }
        
        let job = activeJobs[jobIndex]
        let progress = job.progress
        
        await MainActor.run {
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
        
        // Move from active to completed on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let index = self.activeJobs.firstIndex(where: { $0.id == job.id }) {
                self.activeJobs.remove(at: index)
            }
            self.completedJobs.append(completedJob)
        }
        
        // Stop monitoring
        stopJobMonitoring(for: job.id)
        
        // Update processing state
        updateProcessingState()
        
        // Save state
        saveJobsState()
        
        // Post completion notification
        NotificationCenter.default.post(
            name: .init("transcriptionJobCompleted"),
            object: completedJob
        )
    }
    
    private func startJobMonitoring(for job: TranscriptionJob) {
        DispatchQueue.main.async { [weak self] in
            let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                self?.monitorJobProgress(job.id)
            }
            
            self?.jobTimersQueue.async(flags: .barrier) {
                self?.jobTimers[job.id] = timer
            }
        }
    }
    
    private func stopJobMonitoring(for jobId: UUID) {
        jobTimersQueue.async(flags: .barrier) { [weak self] in
            self?.jobTimers[jobId]?.invalidate()
            self?.jobTimers.removeValue(forKey: jobId)
        }
    }
    
    private func monitorJobProgress(_ jobId: UUID) {
        guard let job = activeJobs.first(where: { $0.id == jobId }) else { return }
        
        // Only check for truly stalled segments (not being actively processed)
        let stalledSegments = job.segments.filter { segment in
            let isProcessing = processingSegmentsQueue.sync {
                return processingSegments.contains(segment.id)
            }
            
            // Only consider it stalled if:
            // 1. Status is processing BUT it's not in our active processing set
            // 2. It's been too long since creation
            return segment.status == .processing &&
                   !isProcessing &&
                   Date().timeIntervalSince(segment.createdAt) > (TranscriptionConstants.apiTimeout * 2)
        }
        
        for segment in stalledSegments {
            Logger.shared.warning("Segment \(segment.segmentIndex) appears truly stalled, marking for retry")
            handleTranscriptionFailure(segment, error: TranscriptionError.processingTimeout)
        }
    }
    
    // MARK: - Queue Processing
    
    private func processQueuedSegments() {
        let currentTaskCount = activeTasksQueue.sync { activeTranscriptionTasks.count }
        let availableSlots = maxConcurrentTranscriptions - currentTaskCount
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
        
        // Auto-end background task after 25 seconds to avoid iOS termination
        DispatchQueue.main.asyncAfter(deadline: .now() + 25.0) { [weak self] in
            self?.endBackgroundProcessing()
        }
    }
    
    private func endBackgroundProcessing() {
        guard backgroundTaskIdentifier != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
        
        Logger.shared.info("Ended background transcription processing")
    }
    
    private func updateProcessingState() {
        let hasActiveJobs = !activeJobs.isEmpty
        let currentTaskCount = activeTasksQueue.sync { activeTranscriptionTasks.count }
        let hasActiveTranscriptions = currentTaskCount > 0
        
        DispatchQueue.main.async { [weak self] in
            self?.isProcessing = hasActiveJobs || hasActiveTranscriptions
            
            if !(hasActiveJobs || hasActiveTranscriptions) {
                self?.processingStatus = "Ready"
                self?.currentProgress = 0.0
                self?.endBackgroundProcessing()
            }
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
        Logger.shared.info("Loaded \(activeJobs.count) active and \(completedJobs.count) completed transcription jobs")
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
            .receive(on: DispatchQueue.main)
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
        saveJobsState()
    }
    
    private func handleAppWillEnterForeground() {
        Logger.shared.info("App entering foreground, resuming transcription processing")
        processQueuedSegments()
        
        // Refresh UI
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
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
