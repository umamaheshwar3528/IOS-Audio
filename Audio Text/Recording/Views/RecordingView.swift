import SwiftUI

struct RecordingView: View {
    @ObservedObject private var recordingManager = AudioRecordingManager.shared
    @ObservedObject private var permissionService = AudioPermissionService.shared
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var segmentProcessor = AudioSegmentProcessor.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var showingSessionList = false
    @State private var showingSettings = false
    @State private var showingTranscriptionSettings = false
    @State private var currentSessionTranscription: UUID?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
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
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        // Transcription status indicator
                        if transcriptionManager.isProcessing {
                            Button(action: { showingTranscriptionSettings = true }) {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Transcribing")
                                        .font(.caption)
                                }
                            }
                            .foregroundColor(.blue)
                        }
                        
                        Button("Sessions") {
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
        }
    }
    
    private var recordingInterface: some View {
        VStack(spacing: 40) {
            // Status Section
            statusSection
            
            // Audio Level Meter
            if recordingManager.currentState.isRecording {
                audioLevelSection
            }
            
            // Transcription Progress (during recording)
            if recordingManager.currentState.isRecording && settingsService.settings.enableAutoTranscription {
                transcriptionProgressSection
            }
            
            // Recent Transcription Results (after recording)
            if !recordingManager.currentState.isRecording && currentSessionTranscription != nil {
                recentTranscriptionSection
            }
            
            Spacer()
            
            // Recording Controls
            RecordingControlsView()
            
            // Network Status
            if !networkMonitor.isConnected && settingsService.settings.preferredTranscriptionService?.requiresNetwork == true {
                networkStatusBanner
            }
            
            Spacer()
        }
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .recordingSessionCompleted)) { notification in
            if let session = notification.object as? RecordingSession {
                handleRecordingCompleted(session)
            }
        }
    }
    
    // MARK: - View Components
    
    private var statusSection: some View {
        VStack(spacing: 16) {
            Text(recordingManager.currentState.displayText)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
            
            if recordingManager.currentState.isRecording || recordingManager.currentState.isPaused {
                Text(recordingManager.recordingDuration.formattedDuration)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundColor(.primary)
                    .animation(.none, value: recordingManager.recordingDuration)
            }
        }
    }
    
    private var statusColor: Color {
        switch recordingManager.currentState {
        case .recording:
            return .red
        case .paused:
            return .orange
        case .stopped:
            return .green
        case .error:
            return .red
        default:
            return .primary
        }
    }
    
    private var audioLevelSection: some View {
        VStack(spacing: 12) {
            Text("Audio Level")
                .font(.caption)
                .foregroundColor(.secondary)
            
            AudioLevelMeterView()
        }
        .transition(.opacity)
    }
    
    private var transcriptionProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundColor(.blue)
                
                Text("Live Transcription")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if segmentProcessor.isProcessingSegments {
                    Text("\(segmentProcessor.currentSegmentIndex + 1) segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let currentSession = recordingManager.currentSession {
                LiveTranscriptionView(sessionId: currentSession.id)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .transition(.opacity)
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
                    // Navigate to the completed session
                    showingSessionList = true
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
            }
            
            if let sessionId = currentSessionTranscription {
                TranscriptionPreviewCard(sessionId: sessionId)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .transition(.opacity)
    }
    
    private var networkStatusBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline Mode")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                
                Text("Transcription will start when connected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Settings") {
                showingTranscriptionSettings = true
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
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

struct LiveTranscriptionView: View {
    let sessionId: UUID
    
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var segmentProcessor = AudioSegmentProcessor.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if let latestTranscription = latestCompletedSegmentText {
                ScrollView {
                    Text(latestTranscription)
                        .font(.body)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 60)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text("Waiting for first segment...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
            
            // Segment processing indicator
            HStack {
                Text("Processing segments in real-time")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if segmentProcessor.isProcessingSegments {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: Date())
                        
                        Text("Live")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
    
    private var latestCompletedSegmentText: String? {
        let segments = transcriptionManager.completedJobs
            .first { $0.sessionId == sessionId }?
            .segments
            .filter { $0.status == .completed }
            .sorted { $0.segmentIndex < $1.segmentIndex }
        
        return segments?.last?.transcriptionText
    }
}

struct TranscriptionPreviewCard: View {
    let sessionId: UUID
    
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let job = currentJob {
                // Progress bar
                ProgressView(value: job.progress)
                    .tint(.blue)
                
                HStack {
                    Text("\(job.completedSegments) of \(job.totalSegments) segments transcribed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if job.hasFailures {
                        Text("\(job.failedSegments) failed")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // Preview text
                if let transcriptionText = transcriptionText, !transcriptionText.isEmpty {
                    let previewText = String(transcriptionText.prefix(100))
                    Text(previewText + (transcriptionText.count > 100 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                        .lineLimit(2)
                }
            } else {
                Text("Transcription not started")
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
    @ObservedObject private var queueManager = SegmentQueueManager.shared
    @ObservedObject private var retryManager = RetryManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Overall status
                overallStatusSection
                
                // Active jobs
                if !transcriptionManager.activeJobs.isEmpty {
                    activeJobsSection
                }
                
                // Queue status
                queueStatusSection
                
                // Network status
                networkStatusSection
                
                Spacer()
            }
            .padding()
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
    
    private var overallStatusSection: some View {
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var activeJobsSection: some View {
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
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
    }
    
    private var queueStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queue Status")
                .font(.headline)
            
            HStack {
                VStack {
                    Text("\(queueManager.pendingSegments.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("Pending")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack {
                    Text("\(queueManager.processingSegments.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Processing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack {
                    Text("\(queueManager.completedSegments.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack {
                    Text("\(queueManager.failedSegments.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("Failed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            if !retryManager.activeRetries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Retries Scheduled: \(retryManager.activeRetries.count)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    let nextRetry = retryManager.activeRetries.values.min { $0.nextRetryTime < $1.nextRetryTime }
                    if let nextRetry = nextRetry {
                        Text("Next retry in: \(nextRetry.nextRetryTime.timeIntervalSinceNow.formattedDuration)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var networkStatusSection: some View {
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
            
            if networkMonitor.isConnected {
                HStack {
                    Text("Connection Type:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(networkMonitor.connectionType.displayName)
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if networkMonitor.isExpensive {
                        Text("Cellular")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundColor(.orange)
                    }
                }
            } else {
                Text("Segments will be queued until connection is restored")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
