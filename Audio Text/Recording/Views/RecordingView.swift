import SwiftUI
import AVFoundation

struct RecordingView: View {
    @ObservedObject private var recordingManager = AudioRecordingManager.shared
    @ObservedObject private var permissionService = AudioPermissionService.shared
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var showingSessionList = false
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var pulseAnimation = false
    @State private var waveAnimation = false
    
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
                            TranscriptionStatusButton {
                                // Show transcription details
                            }
                        }
                        
                        SessionsButton(count: recordingManager.totalSessions) {
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
            
            Spacer()
            
            // Controls
            controlsSection
            
            // Status banners
            statusBannersSection
            
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
        .animation(.smooth(duration: 0.4), value: recordingManager.currentState)
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
        !recordingManager.currentState.isError
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
    let action: () -> Void
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                
                Text("\(Int(transcriptionManager.currentProgress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
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
                }
            }
            .foregroundColor(.primary)
        }
    }
}

// MARK: - Extensions

extension RecordingState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

extension AudioRecordingManager {
    var totalSessions: Int {
        // This would need to be implemented to return total session count
        return 0
    }
}
