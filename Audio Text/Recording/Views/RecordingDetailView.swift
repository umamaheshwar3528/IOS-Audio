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
    @State private var playbackError: String?
    
    // Transcription dependencies
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var authManager = AuthenticationManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Audio Info
                audioInfoSection
                
                // Transcription Section
                transcriptionSection
                
                // Playback Controls
                if session.fileURL != nil {
                    playbackControlsSection
                }
                
                // Error Display
                if let error = playbackError {
                    errorSection(error)
                }
                
                Spacer(minLength: 50)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopPlayback()
        }
        .sheet(isPresented: $showingTranscription) {
            TranscriptionDetailView(session: session)
        }
        .sheet(isPresented: $showingAPIKeySetup) {
            APIKeyConfigurationView()
        }
        .onAppear {
            checkAutoTranscription()
        }
        .refreshable {
            // Force refresh transcription state
            await refreshTranscriptionState()
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(session.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text(session.startTime, style: .date)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var audioInfoSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(session.formattedDuration)
                        .font(.title3)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("File Size")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(session.formattedFileSize)
                        .font(.title3)
                        .fontWeight(.medium)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(session.configuration.quality.rawValue)
                        .font(.title3)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Sample Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(session.configuration.sampleRate)) Hz")
                        .font(.title3)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var transcriptionSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundColor(.blue)
                
                Text("Transcription")
                    .font(.headline)
                
                Spacer()
                
                transcriptionStatusIndicator
            }
            
            // Content based on transcription state
            if isTranscribing {
                // Show progress
                TranscriptionProgressView(sessionId: session.id)
            } else if hasTranscription {
                // Show completed transcription preview
                transcriptionPreviewSection
            } else if hasFailedTranscription {
                // Show failed state with retry option
                transcriptionFailedSection
            } else {
                // Show start transcription option
                transcriptionStartSection
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var transcriptionStatusIndicator: some View {
        Group {
            if isTranscribing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            } else if hasTranscription {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Complete")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else if hasFailedTranscription {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Failed")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    private var transcriptionPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !transcriptionText.isEmpty {
                // Preview text (first 300 characters for better preview)
                let previewText = String(transcriptionText.prefix(300))
                let hasMore = transcriptionText.count > 300
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(previewText + (hasMore ? "..." : ""))
                        .font(.body)
                        .lineLimit(6)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .textSelection(.enabled) // Allow text selection
                    
                    // Show transcription stats
                    HStack {
                        if let job = currentJob {
                            Text("\(job.completedSegments) of \(job.totalSegments) segments")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if job.hasFailures {
                                Text("\(job.failedSegments) failed")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Text("Words: \(wordCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Fallback if no text available
                Text("Transcription completed but no text available")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
            }
            
            // Action buttons
            HStack {
                Button("View Full Transcription") {
                    showingTranscription = true
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button(action: shareTranscription) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(transcriptionText.isEmpty)
            }
        }
    }
    
    private var transcriptionFailedSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                
                Text("Transcription failed")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                
                Spacer()
            }
            
            if let job = currentJob {
                Text("Failed to transcribe \(job.failedSegments) of \(job.totalSegments) segments")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Retry Failed Segments") {
                    retryFailedSegments()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if hasPartialTranscription {
                    Button("View Partial Results") {
                        showingTranscription = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private var transcriptionStartSection: some View {
        VStack(spacing: 12) {
            if !canStartTranscription {
                transcriptionBlockedSection
            } else {
                VStack(spacing: 8) {
                    Text("Convert your audio to text using AI transcription")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Service indicator
                    if let preferredService = preferredTranscriptionService {
                        HStack {
                            Image(systemName: serviceIcon(for: preferredService))
                                .foregroundColor(serviceColor(for: preferredService))
                            
                            Text("Using \(preferredService.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if preferredService.requiresNetwork && !networkMonitor.isConnected {
                                Image(systemName: "wifi.slash")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    Button("Start Transcription") {
                        startTranscription()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStartTranscription)
                }
            }
        }
    }
    
    private var transcriptionBlockedSection: some View {
        VStack(spacing: 12) {
            if !authManager.hasValidOpenAIKey && preferredTranscriptionService == .openai {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "key")
                            .foregroundColor(.orange)
                        
                        Text("OpenAI API Key Required")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    
                    Text("Configure your OpenAI API key to use Whisper transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Configure API Key") {
                        showingAPIKeySetup = true
                    }
                    .buttonStyle(.bordered)
                }
            } else if !networkMonitor.isConnected && preferredTranscriptionService?.requiresNetwork == true {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                        
                        Text("Network Required")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    
                    Text("Connect to Wi-Fi or enable cellular data for transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        
                        Text("Transcription Unavailable")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    
                    Text("No transcription services are currently available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private var playbackControlsSection: some View {
        VStack(spacing: 16) {
            // Audio progress if playing
            if isPlaying {
                VStack(spacing: 8) {
                    HStack {
                        Text(formatTime(currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatTime(session.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: currentTime, total: session.duration)
                        .tint(.blue)
                }
            }
            
            HStack(spacing: 30) {
                // Main play/pause button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .background(Circle().fill(session.fileURL != nil ? Color.blue : Color.gray))
                .disabled(session.fileURL == nil)
                
                // Share recording button
                Button(action: shareRecording) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                }
                .buttonStyle(ControlButtonStyle(isEnabled: session.fileURL != nil))
                .disabled(session.fileURL == nil)
                
                // View transcription button (only if has transcription)
                if hasTranscription {
                    Button(action: { showingTranscription = true }) {
                        Image(systemName: "doc.text")
                            .font(.title2)
                    }
                    .buttonStyle(ControlButtonStyle(isEnabled: true))
                }
            }
        }
    }
    
    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
            
            Spacer()
            
            Button("Dismiss") {
                playbackError = nil
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Computed Properties
    
    private var currentJob: TranscriptionJob? {
        // First check completed jobs, then active jobs
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
        if let job = currentJob {
            return job.hasFailures && job.completedSegments == 0
        }
        return false
    }
    
    private var hasPartialTranscription: Bool {
        if let job = currentJob {
            return job.hasFailures && job.completedSegments > 0 && !transcriptionText.isEmpty
        }
        return false
    }
    
    private var transcriptionText: String {
        // Try multiple ways to get transcription text
        if let job = currentJob, !job.fullTranscriptionText.isEmpty {
            return job.fullTranscriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if let managerText = transcriptionManager.getTranscriptionText(for: session.id),
           !managerText.isEmpty {
            return managerText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ""
    }
    
    private var wordCount: Int {
        return transcriptionText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    private var preferredTranscriptionService: TranscriptionService? {
        let settings = SettingsService.shared.settings
        return settings.preferredTranscriptionService ?? determineAutoService()
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
                return false // Not implemented yet
            case .none:
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Helper Methods
    
    private func determineAutoService() -> TranscriptionService {
        if networkMonitor.isConnected && authManager.hasValidOpenAIKey {
            return .openai
        } else if AppleTranscriptionService.shared.isAvailable {
            return .apple
        } else {
            return .none
        }
    }
    
    private func serviceIcon(for service: TranscriptionService) -> String {
        switch service {
        case .openai: return "brain"
        case .apple: return "applelogo"
        case .localWhisper: return "cpu"
        case .none: return "questionmark"
        }
    }
    
    private func serviceColor(for service: TranscriptionService) -> Color {
        switch service {
        case .openai: return .green
        case .apple: return .blue
        case .localWhisper: return .purple
        case .none: return .gray
        }
    }
    
    private func checkAutoTranscription() {
        let settings = SettingsService.shared.settings
        
        // Auto-start transcription for new recordings if enabled
        if settings.enableAutoTranscription &&
           !hasTranscription &&
           !isTranscribing &&
           canStartTranscription {
            // Check if this is a recent recording (within last hour)
            if Date().timeIntervalSince(session.startTime) < 3600 {
                startTranscription()
            }
        }
    }
    
    private func refreshTranscriptionState() async {
        // Force refresh the transcription manager state
        DispatchQueue.main.async {
            self.transcriptionManager.objectWillChange.send()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Actions
    
    private func startTranscription() {
        let job = transcriptionManager.startTranscriptionJob(for: session)
        Logger.shared.info("Started transcription job: \(job.id)")
    }
    
    private func retryFailedSegments() {
        guard let job = currentJob else { return }
        
        Task {
            await transcriptionManager.retryFailedSegments(for: job.id)
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
    
    // MARK: - Playback Methods (Fixed)
    
    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let fileURL = session.fileURL else {
            playbackError = "Audio file not found"
            return
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            playbackError = "Audio file no longer exists"
            return
        }
        
        do {
            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Create and configure audio player
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 1.0
            
            // Start playback
            let success = audioPlayer?.play() ?? false
            
            if success {
                isPlaying = true
                playbackError = nil
                
                // Start timer for progress tracking
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let player = self.audioPlayer {
                        self.currentTime = player.currentTime
                        
                        // Check if playback finished
                        if !player.isPlaying && player.currentTime >= player.duration {
                            self.stopPlayback()
                        }
                    }
                }
            } else {
                playbackError = "Failed to start audio playback"
            }
            
        } catch {
            playbackError = "Playback error: \(error.localizedDescription)"
            Logger.shared.error("Failed to start playback: \(error)")
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
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    private func shareRecording() {
        guard let fileURL = session.fileURL else {
            playbackError = "Audio file not found"
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            playbackError = "Audio file no longer exists"
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
}
