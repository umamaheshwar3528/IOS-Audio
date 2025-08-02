import SwiftUI
import AVFoundation

struct RecordingDetailView: View {
    let session: RecordingSession
    
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showingTranscription = false
    @State private var showingAPIKeySetup = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    // Transcription dependencies
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Header section
                headerSection
                
                // Audio info cards
                audioInfoSection
                
                // Transcription section
                transcriptionSection
                
                // Playback controls
                if session.fileURL != nil {
                    playbackSection
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onDisappear {
            stopPlayback()
        }
        .sheet(isPresented: $showingTranscription) {
            TranscriptionDetailView(session: session)
        }
        .sheet(isPresented: $showingAPIKeySetup) {
            APIKeyConfigurationView()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            checkAutoTranscription()
        }
        .refreshable {
            await refreshTranscriptionState()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(session.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Label(session.startTime.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                
                Label(session.formattedDuration, systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Audio Info Section
    
    private var audioInfoSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            InfoCard(
                icon: "waveform",
                title: "Duration",
                value: session.formattedDuration,
                color: .blue
            )
            
            InfoCard(
                icon: "internaldrive",
                title: "File Size",
                value: session.formattedFileSize,
                color: .green
            )
            
            InfoCard(
                icon: "dial.high",
                title: "Quality",
                value: session.configuration.quality.rawValue.capitalized,
                color: .orange
            )
            
            InfoCard(
                icon: "waveform.badge.magnifyingglass",
                title: "Sample Rate",
                value: "\(Int(session.configuration.sampleRate / 1000))kHz",
                color: .purple
            )
        }
    }
    
    // MARK: - Transcription Section
    
    private var transcriptionSection: some View {
        VStack(spacing: 16) {
            // Header with status
            transcriptionHeader
            
            // Content based on state
            Group {
                if isTranscribing {
                    TranscriptionProgressCard(sessionId: session.id)
                } else if hasTranscription {
                    TranscriptionPreviewCard(
                        text: transcriptionText,
                        job: currentJob,
                        onViewFull: { showingTranscription = true },
                        onShare: shareTranscription
                    )
                } else if hasFailedTranscription {
                    TranscriptionFailedCard(
                        job: currentJob,
                        onRetry: retryFailedSegments,
                        onViewPartial: hasPartialTranscription ? { showingTranscription = true } : nil
                    )
                } else {
                    TranscriptionStartCard(
                        canStart: canStartTranscription,
                        service: preferredTranscriptionService,
                        isNetworkConnected: networkMonitor.isConnected,
                        hasAPIKey: authManager.hasValidOpenAIKey,
                        onStart: startTranscription,
                        onConfigureAPI: { showingAPIKeySetup = true }
                    )
                }
            }
            .animation(.smooth(duration: 0.3), value: transcriptionState)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var transcriptionHeader: some View {
        HStack {
            Image(systemName: "waveform.badge.magnifyingglass")
                .foregroundColor(.blue)
                .font(.title3)
            
            Text("Transcription")
                .font(.headline)
            
            Spacer()
            
            transcriptionStatusBadge
        }
    }
    
    private var transcriptionStatusBadge: some View {
        Group {
            if isTranscribing {
                StatusBadge(text: "Processing", color: .blue, isAnimated: true)
            } else if hasTranscription {
                StatusBadge(text: "Complete", color: .green)
            } else if hasFailedTranscription {
                StatusBadge(text: "Failed", color: .red)
            }
        }
    }
    
    // MARK: - Playback Section
    
    private var playbackSection: some View {
        VStack(spacing: 20) {
            // Progress bar (when playing)
            if isPlaying {
                playbackProgress
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Control buttons
            playbackControls
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var playbackProgress: some View {
        VStack(spacing: 8) {
            ProgressView(value: currentTime, total: session.duration)
                .tint(.blue)
            
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .monospacedDigit()
                
                Spacer()
                
                Text(formatTime(session.duration))
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundColor(.secondary)
        }
    }
    
    private var playbackControls: some View {
        HStack(spacing: 24) {
            // Play/pause button
            Button(action: togglePlayback) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .disabled(session.fileURL == nil || isLoading)
            .scaleEffect(isLoading ? 0.9 : 1.0)
            .animation(.smooth(duration: 0.2), value: isLoading)
            
            Spacer()
            
            // Share button
            Button(action: shareRecording) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(session.fileURL == nil)
            
            // Transcription button (if available)
            if hasTranscription {
                Button(action: { showingTranscription = true }) {
                    Image(systemName: "doc.text")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.completedJobs.first { $0.sessionId == session.id } ??
        transcriptionManager.activeJobs.first { $0.sessionId == session.id }
    }
    
    private var isTranscribing: Bool {
        transcriptionManager.activeJobs.contains { $0.sessionId == session.id }
    }
    
    private var hasTranscription: Bool {
        !transcriptionText.isEmpty
    }
    
    private var hasFailedTranscription: Bool {
        currentJob?.hasFailures == true && currentJob?.completedSegments == 0
    }
    
    private var hasPartialTranscription: Bool {
        currentJob?.hasFailures == true && currentJob?.completedSegments ?? 0 > 0 && !transcriptionText.isEmpty
    }
    
    private var transcriptionText: String {
        if let job = currentJob, !job.fullTranscriptionText.isEmpty {
            return job.fullTranscriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if let managerText = transcriptionManager.getTranscriptionText(for: session.id),
           !managerText.isEmpty {
            return managerText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ""
    }
    
    private var preferredTranscriptionService: TranscriptionService? {
        SettingsService.shared.settings.preferredTranscriptionService ?? determineAutoService()
    }
    
    private var canStartTranscription: Bool {
        guard !isTranscribing else { return false }
        
        if let service = preferredTranscriptionService {
            switch service {
            case .openai:
                return authManager.hasValidOpenAIKey && networkMonitor.isConnected
            case .apple:
                return AppleTranscriptionService.shared.isAvailable
            case .localWhisper:
                return false
            case .none:
                return false
            }
        }
        
        return false
    }
    
    private var transcriptionState: String {
        if isTranscribing { return "transcribing" }
        if hasTranscription { return "complete" }
        if hasFailedTranscription { return "failed" }
        return "ready"
    }
    
    // MARK: - Actions
    
    private func startTranscription() {
        isLoading = true
        let job = transcriptionManager.startTranscriptionJob(for: session)
        Logger.shared.info("Started transcription job: \(job.id)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
        }
    }
    
    private func retryFailedSegments() {
        guard let job = currentJob else { return }
        
        isLoading = true
        Task {
            await transcriptionManager.retryFailedSegments(for: job.id)
            
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    private func shareTranscription() {
        guard !transcriptionText.isEmpty else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [transcriptionText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let fileURL = session.fileURL else {
            showError("Audio file not found")
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showError("Audio file no longer exists")
            return
        }
        
        isLoading = true
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 1.0
            
            let success = audioPlayer?.play() ?? false
            
            if success {
                isPlaying = true
                isLoading = false
                
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let player = self.audioPlayer {
                        self.currentTime = player.currentTime
                        
                        if !player.isPlaying && player.currentTime >= player.duration {
                            self.stopPlayback()
                        }
                    }
                }
            } else {
                isLoading = false
                showError("Failed to start audio playback")
            }
            
        } catch {
            isLoading = false
            showError("Playback error: \(error.localizedDescription)")
        }
    }
    
    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentTime = 0
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    private func shareRecording() {
        guard let fileURL = session.fileURL else {
            showError("Audio file not found")
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showError("Audio file no longer exists")
            return
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func checkAutoTranscription() {
        let settings = SettingsService.shared.settings
        
        if settings.enableAutoTranscription &&
           !hasTranscription &&
           !isTranscribing &&
           canStartTranscription {
            if Date().timeIntervalSince(session.startTime) < 3600 {
                startTranscription()
            }
        }
    }
    
    private func refreshTranscriptionState() async {
        DispatchQueue.main.async {
            self.transcriptionManager.objectWillChange.send()
        }
    }
    
    private func determineAutoService() -> TranscriptionService {
        if networkMonitor.isConnected && authManager.hasValidOpenAIKey {
            return .openai
        } else if AppleTranscriptionService.shared.isAvailable {
            return .apple
        } else {
            return .none
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Supporting Views

struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    let isAnimated: Bool
    
    init(text: String, color: Color, isAnimated: Bool = false) {
        self.text = text
        self.color = color
        self.isAnimated = isAnimated
    }
    
    @State private var opacity = 1.0
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .opacity(opacity)
            .onAppear {
                if isAnimated {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                        opacity = 0.6
                    }
                }
            }
    }
}

struct TranscriptionPreviewCard: View {
    let text: String
    let job: TranscriptionJob?
    let onViewFull: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preview text
            let previewText = String(text.prefix(200))
            Text(previewText + (text.count > 200 ? "..." : ""))
                .font(.body)
                .lineLimit(4)
                .textSelection(.enabled)
            
            // Stats
            if let job = job {
                HStack {
                    Label("\(job.completedSegments)/\(job.totalSegments)", systemImage: "waveform")
                    
                    Spacer()
                    
                    if job.hasFailures {
                        Label("\(job.failedSegments) failed", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                    
                    Label("\(wordCount) words", systemImage: "textformat")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            // Actions
            HStack {
                Button("View Full Text", action: onViewFull)
                    .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}

struct TranscriptionFailedCard: View {
    let job: TranscriptionJob?
    let onRetry: () -> Void
    let onViewPartial: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                
                Text("Transcription failed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            if let job = job {
                Text("Failed to transcribe \(job.failedSegments) of \(job.totalSegments) segments")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                
                if let onViewPartial = onViewPartial {
                    Button("View Partial", action: onViewPartial)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct TranscriptionStartCard: View {
    let canStart: Bool
    let service: TranscriptionService?
    let isNetworkConnected: Bool
    let hasAPIKey: Bool
    let onStart: () -> Void
    let onConfigureAPI: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            if canStart {
                // Ready to start
                VStack(spacing: 8) {
                    Text("Convert your audio to text using AI transcription")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    if let service = service {
                        ServiceIndicator(service: service, isConnected: isNetworkConnected)
                    }
                    
                    Button("Start Transcription", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Blocked state
                VStack(spacing: 8) {
                    if !hasAPIKey && service == .openai {
                        ConfigurationRequired(
                            icon: "key",
                            title: "OpenAI API Key Required",
                            message: "Configure your OpenAI API key to use Whisper transcription",
                            action: onConfigureAPI
                        )
                    } else if !isNetworkConnected && service?.requiresNetwork == true {
                        ConfigurationRequired(
                            icon: "wifi.slash",
                            title: "Network Required",
                            message: "Connect to Wi-Fi or enable cellular data for transcription",
                            action: nil
                        )
                    } else {
                        ConfigurationRequired(
                            icon: "exclamationmark.triangle",
                            title: "Transcription Unavailable",
                            message: "No transcription services are currently available",
                            action: nil
                        )
                    }
                }
            }
        }
    }
}

struct ServiceIndicator: View {
    let service: TranscriptionService
    let isConnected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: serviceIcon)
                .foregroundColor(serviceColor)
            
            Text("Using \(service.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if service.requiresNetwork && !isConnected {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }
    
    private var serviceIcon: String {
        switch service {
        case .openai: return "brain"
        case .apple: return "applelogo"
        case .localWhisper: return "cpu"
        case .none: return "questionmark"
        }
    }
    
    private var serviceColor: Color {
        switch service {
        case .openai: return .green
        case .apple: return .blue
        case .localWhisper: return .purple
        case .none: return .gray
        }
    }
}

struct ConfigurationRequired: View {
    let icon: String
    let title: String
    let message: String
    let action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.orange)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let action = action {
                Button("Configure", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct TranscriptionProgressCard: View {
    let sessionId: UUID
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        VStack(spacing: 12) {
            if let job = currentJob {
                ProgressView(value: job.progress)
                    .tint(.blue)
                
                HStack {
                    Text("\(job.completedSegments) of \(job.totalSegments) segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(job.progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                if job.hasFailures {
                    Text("\(job.failedSegments) segments failed")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text("Starting transcription...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == sessionId }
    }
}
