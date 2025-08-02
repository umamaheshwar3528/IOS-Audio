import SwiftUI
import AVFoundation

struct RecordingView: View {
    @ObservedObject private var recordingManager = AudioRecordingManager.shared
    @ObservedObject private var permissionService = AudioPermissionService.shared
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var fileManagerService = FileManagerService.shared
    
    @State private var showingSessionList = false
    @State private var showingSettings = false
    @State private var showingTranscriptionSettings = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var pulseAnimation = false
    @State private var waveAnimation = false
    @State private var currentSessionTranscription: UUID?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6).opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if permissionService.permissionStatus.isGranted {
                    recordingInterface
                } else {
                    PermissionRequestView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Transcription indicator
                        if transcriptionManager.isProcessing {
                            TranscriptionStatusButton(
                                progress: transcriptionManager.currentProgress,
                                activeJobs: transcriptionManager.activeJobs.count
                            ) {
                                showingTranscriptionSettings = true
                            }
                        }
                        
                        SessionsButton(count: fileManagerService.recordings.count) {
                            showingSessionList = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSessionList) {
                RecordingSessionListView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingTranscriptionSettings) {
                TranscriptionStatusSheet()
            }
            .alert("Recording Error", isPresented: $showingError) {
                Button("OK") {}
                Button("Retry") {
                    retryRecording()
                }
            } message: {
                Text(errorMessage)
            }
            .onReceive(recordingManager.$currentState) { state in
                handleStateChange(state)
            }
        }
    }
    
    private var recordingInterface: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Main recording display
            recordingDisplaySection
            
            Spacer()
            
            // Audio level visualization (only when recording)
            if recordingManager.currentState.isRecording {
                audioVisualizationSection
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Transcription progress (during recording)
            if recordingManager.currentState.isRecording && settingsService.settings.enableAutoTranscription {
                transcriptionProgressSection
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Recent transcription results (after recording)
            if !recordingManager.currentState.isRecording && currentSessionTranscription != nil {
                recentTranscriptionSection
                    .transition(.scale.combined(with: .opacity))
            }
            
            Spacer()
            
            // Controls
            controlsSection
            Spacer(minLength: 10)
            // Status banners
            statusBannersSection
            
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
        .animation(.smooth(duration: 0.4), value: recordingManager.currentState)
        .onReceive(NotificationCenter.default.publisher(for: .recordingSessionCompleted)) { notification in
            if let session = notification.object as? RecordingSession {
                handleRecordingCompleted(session)
            }
        }
    }
    
    // MARK: - Recording Display
    
    private var recordingDisplaySection: some View {
        VStack(spacing: 20) {
            // Record button or status
            recordButton
            
            // Duration display
            if recordingManager.currentState.isRecording || recordingManager.currentState.isPaused {
                durationDisplay
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Status text
            statusText
        }
    }
    
    private var recordButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(recordButtonColor, lineWidth: 4)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .opacity(pulseAnimation ? 0.6 : 1.0)
                
                // Inner button
                Circle()
                    .fill(recordButtonColor)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: recordButtonIcon)
                            .font(.title)
                            .foregroundColor(.white)
                    )
                    .scaleEffect(recordingManager.currentState.isRecording ? 0.9 : 1.0)
            }
        }
        .disabled(!canRecord)
        .onAppear {
            startPulseAnimation()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recordingManager.currentState)
    }
    
    private var durationDisplay: some View {
        Text(recordingManager.recordingDuration.formattedDuration)
            .font(.system(size: 36, weight: .light, design: .monospaced))
            .foregroundColor(.primary)
            .contentTransition(.numericText())
    }
    
    private var statusText: some View {
        Text(recordingManager.currentState.displayText)
            .font(.headline)
            .foregroundColor(statusTextColor)
            .animation(.easeInOut, value: recordingManager.currentState)
    }
    
    // MARK: - Audio Visualization
    
    private var audioVisualizationSection: some View {
        VStack(spacing: 12) {
            Text("Audio Level")
                .font(.caption)
                .foregroundColor(.secondary)
            
            CleanAudioMeter()
                .frame(height: 40)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                        waveAnimation.toggle()
                    }
                }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Transcription Sections
    
    private var transcriptionProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundColor(.blue)
                
                Text("Live Transcription")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let currentSession = recordingManager.currentSession {
                    let activeJob = transcriptionManager.activeJobs.first { $0.sessionId == currentSession.id }
                    if let job = activeJob {
                        Text("\(job.completedSegments) segments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let currentSession = recordingManager.currentSession {
                LiveTranscriptionPreview(sessionId: currentSession.id)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    private var recentTranscriptionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Text("Recording Complete")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("View Details") {
                    showingSessionList = true
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            if let sessionId = currentSessionTranscription {
                TranscriptionResultPreview(sessionId: sessionId)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack(spacing: 40) {
            // Stop button
            ControlButton(
                icon: "stop.fill",
                isEnabled: canStop,
                action: stopRecording
            )
            
            // Settings button
            ControlButton(
                icon: "gearshape.fill",
                isEnabled: true,
                action: { showingSettings = true }
            )
        }
    }
    
    // MARK: - Status Banners
    
    private var statusBannersSection: some View {
        VStack(spacing: 12) {
            // Network status
            if !networkMonitor.isConnected && needsNetwork {
                StatusBanner(
                    icon: "wifi.slash",
                    title: "Offline Mode",
                    message: "Transcription will start when connected",
                    color: .orange
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Transcription progress
            if transcriptionManager.isProcessing {
                TranscriptionProgressBanner()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: networkMonitor.isConnected)
        .animation(.smooth(duration: 0.3), value: transcriptionManager.isProcessing)
    }
    
    // MARK: - Computed Properties
    
    private var recordButtonColor: Color {
        switch recordingManager.currentState {
        case .recording: return .red
        case .paused: return .orange
        case .error: return .red
        default: return .blue
        }
    }
    
    private var recordButtonIcon: String {
        switch recordingManager.currentState {
        case .recording: return "pause.fill"
        case .paused: return "play.fill"
        case .error: return "exclamationmark.triangle.fill"
        default: return "mic.fill"
        }
    }
    
    private var statusTextColor: Color {
        switch recordingManager.currentState {
        case .recording: return .primary
        case .paused: return .orange
        case .error: return .red
        default: return .secondary
        }
    }
    
    private var canRecord: Bool {
        !recordingManager.currentState.isPaused
    }
    
    private var canStop: Bool {
        recordingManager.currentState.isRecording || recordingManager.currentState.isPaused
    }
    
    private var needsNetwork: Bool {
        settingsService.settings.preferredTranscriptionService?.requiresNetwork == true
    }
    
    // MARK: - Actions
    
    private func toggleRecording() {
        Task {
            do {
                switch recordingManager.currentState {
                case .idle, .stopped:
                    try await startRecording()
                case .recording:
                    recordingManager.pauseRecording()
                case .paused:
                    recordingManager.resumeRecording()
                case .error:
                    break
                }
            } catch {
                handleError(error)
            }
        }
    }
    
    private func startRecording() async throws {
        let settings = settingsService.settings
        let config = AudioConfiguration(
            sampleRate: settings.audioQuality.sampleRate,
            bitDepth: settings.audioQuality.bitDepth,
            channels: 1,
            format: kAudioFormatLinearPCM,
            quality: settings.audioQuality
        )
        try await recordingManager.startRecording(with: config)
    }
    
    private func stopRecording() {
        _ = recordingManager.stopRecording()
    }
    
    private func retryRecording() {
        Task {
            try? await startRecording()
        }
    }
    
    private func handleStateChange(_ state: RecordingState) {
        if case .error(let error) = state {
            handleError(error)
        }
    }
    
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
        
        // Haptic feedback for errors
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever()) {
            pulseAnimation = true
        }
    }
    
    private func handleRecordingCompleted(_ session: RecordingSession) {
        // Show transcription status for the completed recording
        currentSessionTranscription = session.id
        
        // Auto-start transcription if enabled
        if settingsService.settings.enableAutoTranscription {
            let _ = transcriptionManager.startTranscriptionJob(for: session)
        }
        
        // Auto-hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if currentSessionTranscription == session.id {
                withAnimation {
                    currentSessionTranscription = nil
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct CleanAudioMeter: View {
    @ObservedObject private var recordingManager = AudioRecordingManager.shared
    
    private let barCount = 15
    private let barSpacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 36
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.1), value: recordingManager.audioLevel)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let normalizedLevel = normalizeAudioLevel(recordingManager.audioLevel)
        let barThreshold = Float(index) / Float(barCount)
        
        if normalizedLevel > barThreshold {
            let intensity = (normalizedLevel - barThreshold) * Float(barCount)
            return minHeight + (maxHeight - minHeight) * CGFloat(min(intensity, 1.0))
        }
        
        return minHeight
    }
    
    private func barColor(for index: Int) -> Color {
        let normalizedLevel = normalizeAudioLevel(recordingManager.audioLevel)
        let barThreshold = Float(index) / Float(barCount)
        
        if normalizedLevel > barThreshold {
            let position = Float(index) / Float(barCount)
            if position < 0.6 {
                return .green
            } else if position < 0.85 {
                return .yellow
            } else {
                return .red
            }
        }
        
        return Color(.systemGray4)
    }
    
    private func normalizeAudioLevel(_ level: Float) -> Float {
        let minDB: Float = -60.0
        let maxDB: Float = 0.0
        let clampedLevel = max(minDB, min(maxDB, level))
        return (clampedLevel - minDB) / (maxDB - minDB)
    }
}

struct ControlButton: View {
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isEnabled ? .primary : .secondary)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(Color(.systemGray6))
                        .opacity(isEnabled ? 1.0 : 0.5)
                )
        }
        .disabled(!isEnabled)
        .scaleEffect(isEnabled ? 1.0 : 0.9)
        .animation(.smooth(duration: 0.2), value: isEnabled)
    }
}

struct StatusBanner: View {
    let icon: String
    let title: String
    let message: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct TranscriptionProgressBanner: View {
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribing")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Int(transcriptionManager.currentProgress * 100))% complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

struct TranscriptionStatusButton: View {
    let progress: Float
    let activeJobs: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                    
                    if activeJobs > 1 {
                        Text("\(activeJobs) jobs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .foregroundColor(.blue)
        }
    }
}

struct SessionsButton: View {
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.caption)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray5))
                        )
                }
            }
            .foregroundColor(.primary)
        }
    }
}

// MARK: - Live Transcription Views

struct LiveTranscriptionPreview: View {
    let sessionId: UUID
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if let latestText = latestTranscriptionText {
                ScrollView {
                    Text(latestText)
                        .font(.body)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text("Waiting for transcription...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
            }
            
            // Progress indicator
            if let job = activeJob {
                HStack {
                    Text("Processing segments")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        
                        Text("Live")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
    
    private var activeJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == sessionId }
    }
    
    private var latestTranscriptionText: String? {
        guard let job = activeJob else { return nil }
        
        let completedSegments = job.segments
            .filter { $0.status == .completed }
            .sorted { $0.segmentIndex < $1.segmentIndex }
        
        // Return the latest completed segment text or partial job text
        if let latestSegment = completedSegments.last {
            return latestSegment.transcriptionText
        }
        
        // Return partial job text if available
        let partialText = job.fullTranscriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return partialText.isEmpty ? nil : partialText
    }
}

struct TranscriptionResultPreview: View {
    let sessionId: UUID
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let job = currentJob {
                // Progress
                ProgressView(value: job.progress)
                    .tint(.blue)
                
                HStack {
                    Text("\(job.completedSegments) of \(job.totalSegments) segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if job.hasFailures {
                        Text("\(job.failedSegments) failed")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("\(Int(job.progress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
                
                // Preview text
                if let transcriptionText = transcriptionText, !transcriptionText.isEmpty {
                    let previewText = String(transcriptionText.prefix(100))
                    Text(previewText + (transcriptionText.count > 100 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .padding(.top, 4)
                }
            } else {
                Text("Starting transcription...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == sessionId } ??
        transcriptionManager.completedJobs.first { $0.sessionId == sessionId }
    }
    
    private var transcriptionText: String? {
        transcriptionManager.getTranscriptionText(for: sessionId)
    }
}

struct TranscriptionStatusSheet: View {
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Overall status
                    overallStatusCard
                    
                    // Active jobs
                    if !transcriptionManager.activeJobs.isEmpty {
                        activeJobsCard
                    }
                    
                    // Network status
                    networkStatusCard
                }
                .padding()
            }
            .navigationTitle("Transcription Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var overallStatusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Overall Status")
                    .font(.headline)
                
                Spacer()
                
                if transcriptionManager.isProcessing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                } else {
                    Text("Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if transcriptionManager.isProcessing {
                ProgressView(value: transcriptionManager.currentProgress)
                    .tint(.blue)
                
                Text(transcriptionManager.processingStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
    
    private var activeJobsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Jobs")
                .font(.headline)
            
            ForEach(transcriptionManager.activeJobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Session \(job.sessionId.uuidString.prefix(8))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(job.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    ProgressView(value: job.progress)
                        .tint(.blue)
                    
                    HStack {
                        Text("\(job.completedSegments)/\(job.totalSegments) segments")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if job.hasFailures {
                            Text("\(job.failedSegments) failed")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
    
    private var networkStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Network Status")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(networkMonitor.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(networkMonitor.isConnected ? "Connected" : "Offline")
                        .font(.caption)
                        .foregroundColor(networkMonitor.isConnected ? .green : .red)
                }
            }
            
            if !networkMonitor.isConnected {
                Text("Segments will be queued until connection is restored")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}
