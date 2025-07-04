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
            if let transcriptionText = transcriptionText, !transcriptionText.isEmpty {
                // Preview text (first 200 characters)
                let previewText = String(transcriptionText.prefix(200))
                let hasMore = transcriptionText.count > 200
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(previewText + (hasMore ? "..." : ""))
                        .font(.body)
                        .lineLimit(4)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                    
                    if let job = currentJob {
                        HStack {
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
                    }
                }
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
            HStack(spacing: 30) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.blue))
                
                Button(action: shareRecording) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                }
                .buttonStyle(ControlButtonStyle(isEnabled: true))
                
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
    
    // MARK: - Computed Properties
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == session.id } ??
        transcriptionManager.completedJobs.first { $0.sessionId == session.id }
    }
    
    private var isTranscribing: Bool {
        transcriptionManager.activeJobs.contains { $0.sessionId == session.id }
    }
    
    private var hasTranscription: Bool {
        transcriptionText != nil && !transcriptionText!.isEmpty
    }
    
    private var hasFailedTranscription: Bool {
        currentJob?.hasFailures == true && currentJob?.completedSegments == 0
    }
    
    private var hasPartialTranscription: Bool {
        currentJob?.hasFailures == true && currentJob?.completedSegments ?? 0 > 0
    }
    
    private var transcriptionText: String? {
        transcriptionManager.getTranscriptionText(for: session.id)
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
    
    // MARK: - Actions
    
    private func startTranscription() {
        let _ = transcriptionManager.startTranscriptionJob(for: session)
    }
    
    private func retryFailedSegments() {
        guard let job = currentJob else { return }
        
        Task {
            await transcriptionManager.retryFailedSegments(for: job.id)
        }
    }
    
    private func shareTranscription() {
        guard let text = transcriptionText else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Playback Methods (Unchanged)
    
    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let fileURL = session.fileURL else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.play()
            isPlaying = true
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if let player = audioPlayer {
                    currentTime = player.currentTime
                    if !player.isPlaying {
                        stopPlayback()
                    }
                }
            }
        } catch {
            Logger.shared.error("Failed to start playback: \(error)")
        }
    }
    
    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        timer?.invalidate()
        currentTime = 0
    }
    
    private func shareRecording() {
        guard let fileURL = session.fileURL else { return }
        
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
