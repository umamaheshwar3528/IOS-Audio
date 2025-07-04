// Transcription/Views/TranscriptionProgressView.swift
import SwiftUI

struct TranscriptionProgressView: View {
    let sessionId: UUID
    
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var queueManager = SegmentQueueManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Overall Progress
            progressSection
            
            // Service Status
            serviceStatusSection
            
            // Segment Breakdown
            segmentBreakdownSection
            
            // Network Status
            if !networkMonitor.isConnected {
                networkStatusSection
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == sessionId } ??
        transcriptionManager.completedJobs.first { $0.sessionId == sessionId }
    }
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundColor(.blue)
                
                Text("Transcription Progress")
                    .font(.headline)
                
                Spacer()
                
                if let job = currentJob {
                    Text("\(job.completedSegments)/\(job.totalSegments)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let job = currentJob {
                ProgressView(value: job.progress)
                    .tint(.blue)
                
                Text(transcriptionManager.processingStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
    
    private var serviceStatusSection: some View {
        HStack(spacing: 12) {
            ServiceStatusIndicator(
                service: .openai,
                isActive: currentJob?.preferredService == .openai
            )
            
            ServiceStatusIndicator(
                service: .apple,
                isActive: currentJob?.preferredService == .apple
            )
            
            if networkMonitor.isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text(networkMonitor.connectionType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var segmentBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Segments")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 16) {
                StatusCount(
                    count: queueManager.completedSegments.filter { $0.sessionId == sessionId }.count,
                    status: .completed,
                    label: "Done"
                )
                
                StatusCount(
                    count: queueManager.processingSegments.filter { $0.sessionId == sessionId }.count,
                    status: .processing,
                    label: "Processing"
                )
                
                StatusCount(
                    count: queueManager.pendingSegments.filter { $0.sessionId == sessionId }.count,
                    status: .pending,
                    label: "Waiting"
                )
                
                StatusCount(
                    count: queueManager.failedSegments.filter { $0.sessionId == sessionId }.count,
                    status: .failed,
                    label: "Failed"
                )
            }
        }
    }
    
    private var networkStatusSection: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .foregroundColor(.orange)
            
            Text("Offline - Transcription will resume when connected")
                .font(.caption)
                .foregroundColor(.orange)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ServiceStatusIndicator: View {
    let service: TranscriptionService
    let isActive: Bool
    
    @ObservedObject private var openAIService = OpenAITranscriptionService.shared
    @ObservedObject private var appleService = AppleTranscriptionService.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(service.displayName)
                .font(.caption)
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }
    
    private var statusColor: Color {
        switch service {
        case .openai:
            return openAIService.isAvailable && networkMonitor.isConnected ? .green : .red
        case .apple:
            return appleService.isAvailable ? .green : .red
        case .localWhisper:
            return .gray // Not implemented
        case .none:
            return .gray
        }
    }
}

struct StatusCount: View {
    let count: Int
    let status: TranscriptionStatus
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(statusColor)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .queued:
            return .purple
        }
    }
}

// MARK: - TranscriptionDetailView

struct TranscriptionDetailView: View {
    let session: RecordingSession
    
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @State private var showingRawSegments = false
    @State private var searchText = ""
    @State private var selectedSegment: TranscriptionSegment?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Progress (if still transcribing)
                    if isTranscribing {
                        TranscriptionProgressView(sessionId: session.id)
                    }
                    
                    // Transcription Result
                    transcriptionTextSection
                    
                    // Segments View Toggle
                    segmentToggleSection
                    
                    // Segments List (if showing)
                    if showingRawSegments {
                        SegmentListView(sessionId: session.id)
                    }
                }
                .padding()
            }
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search transcription")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Export Text") {
                            exportTranscription()
                        }
                        
                        Button("Share") {
                            shareTranscription()
                        }
                        
                        if hasFailedSegments {
                            Button("Retry Failed") {
                                retryFailedSegments()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == session.id } ??
        transcriptionManager.completedJobs.first { $0.sessionId == session.id }
    }
    
    private var isTranscribing: Bool {
        transcriptionManager.activeJobs.contains { $0.sessionId == session.id }
    }
    
    private var hasFailedSegments: Bool {
        currentJob?.hasFailures == true
    }
    
    private var transcriptionText: String {
        return transcriptionManager.getTranscriptionText(for: session.id) ?? "No transcription available"
    }
    
    private var filteredText: String {
        guard !searchText.isEmpty else { return transcriptionText }
        
        // Simple text highlighting - in production, you'd want more sophisticated search
        return transcriptionText.replacingOccurrences(
            of: searchText,
            with: "**\(searchText)**",
            options: .caseInsensitive
        )
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(session.title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(session.startTime, style: .date)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let job = currentJob {
                HStack {
                    Text("Duration: \(session.formattedDuration)")
                    Spacer()
                    Text("Segments: \(job.totalSegments)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private var transcriptionTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcription")
                    .font(.headline)
                
                Spacer()
                
                if let job = currentJob, job.isCompleted {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            ScrollView {
                Text(filteredText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 200)
        }
    }
    
    private var segmentToggleSection: some View {
        Button(action: {
            withAnimation {
                showingRawSegments.toggle()
            }
        }) {
            HStack {
                Text("Show Segments")
                    .font(.subheadline)
                
                Spacer()
                
                Image(systemName: showingRawSegments ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(.blue)
        }
    }
    
    private func exportTranscription() {
        let text = transcriptionText
        
        // Create a temporary file
        let fileName = "\(session.title)_transcription.txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            
            let activityVC = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            Logger.shared.error("Failed to export transcription: \(error)")
        }
    }
    
    private func shareTranscription() {
        let text = transcriptionText
        
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
    
    private func retryFailedSegments() {
        guard let job = currentJob else { return }
        
        Task {
            await transcriptionManager.retryFailedSegments(for: job.id)
        }
    }
}

// MARK: - SegmentListView

struct SegmentListView: View {
    let sessionId: UUID
    
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var retryManager = RetryManager.shared
    @State private var selectedSegment: TranscriptionSegment?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Segments")
                .font(.headline)
            
            LazyVStack(spacing: 8) {
                ForEach(sortedSegments, id: \.id) { segment in
                    SegmentRowView(
                        segment: segment,
                        onRetry: { retrySegment(segment) },
                        onTap: { selectedSegment = segment }
                    )
                }
            }
        }
        .sheet(item: $selectedSegment) { segment in
            SegmentDetailSheet(segment: segment)
        }
    }
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == sessionId } ??
        transcriptionManager.completedJobs.first { $0.sessionId == sessionId }
    }
    
    private var sortedSegments: [TranscriptionSegment] {
        currentJob?.segments.sorted { $0.segmentIndex < $1.segmentIndex } ?? []
    }
    
    private func retrySegment(_ segment: TranscriptionSegment) {
        guard segment.needsRetry else { return }
        
        retryManager.scheduleRetry(for: segment) { retrySegment in
            // Add back to queue for processing
            SegmentQueueManager.shared.addSegment(retrySegment)
        }
    }
}

// MARK: - TranscriptionLanguageInfoView

struct TranscriptionLanguageInfoView: View {
    let service: TranscriptionService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(service.supportedLanguages, id: \.self) { language in
                        Text(language)
                    }
                } header: {
                    Text("Supported Languages")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estimated Processing Time:")
                            .font(.headline)
                        Text("\(service.estimatedProcessingTime.formatted()) seconds for 30 seconds of audio")
                        
                        if service.requiresNetwork {
                            Text("⚠️ Requires internet connection")
                                .foregroundColor(.orange)
                        } else {
                            Text("✅ Works offline")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle(service.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views for Advanced Settings

struct TranscriptionStatisticsView: View {
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @ObservedObject private var retryManager = RetryManager.shared
    @ObservedObject private var queueManager = SegmentQueueManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section("Overview") {
                StatRow(label: "Total Jobs", value: "\(transcriptionManager.activeJobs.count + transcriptionManager.completedJobs.count)")
                StatRow(label: "Active Jobs", value: "\(transcriptionManager.activeJobs.count)")
                StatRow(label: "Completed Jobs", value: "\(transcriptionManager.completedJobs.count)")
            }
            
            Section("Queue Status") {
                StatRow(label: "Pending Segments", value: "\(queueManager.pendingSegments.count)")
                StatRow(label: "Processing Segments", value: "\(queueManager.processingSegments.count)")
                StatRow(label: "Completed Segments", value: "\(queueManager.completedSegments.count)")
                StatRow(label: "Failed Segments", value: "\(queueManager.failedSegments.count)")
                
                StatRow(label: "Success Rate", value: String(format: "%.1f%%", queueManager.completionRate * 100))
            }
            
            Section("Retry Statistics") {
                StatRow(label: "Active Retries", value: "\(retryManager.activeRetries.count)")
                StatRow(label: "Total Retries", value: "\(retryManager.retryStatistics.totalRetries)")
                StatRow(label: "Successful Retries", value: "\(retryManager.retryStatistics.successfulRetries)")
                StatRow(label: "Retry Success Rate", value: String(format: "%.1f%%", retryManager.retryStatistics.successRate * 100))
            }
        }
        .navigationTitle("Transcription Statistics")
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

struct ServiceDiagnosticsView: View {
    @ObservedObject private var openAIService = OpenAITranscriptionService.shared
    @ObservedObject private var appleService = AppleTranscriptionService.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var authManager = AuthenticationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            // OpenAI Whisper Section
            Section {
                DiagnosticRow(label: "Status", value: openAIService.isAvailable ? "Available" : "Unavailable", isHealthy: openAIService.isAvailable)
                DiagnosticRow(label: "API Key", value: authManager.hasValidOpenAIKey ? "Configured" : "Not Configured", isHealthy: authManager.hasValidOpenAIKey)
                DiagnosticRow(label: "Rate Limit", value: "\(openAIService.rateLimitStatus.remainingRequests) requests remaining", isHealthy: openAIService.rateLimitStatus.remainingRequests > 10)
            } header: {
                Text("OpenAI Whisper")
            }

            // Apple Speech Recognition Section
            Section {
                DiagnosticRow(
                    label: "Status",
                    value: appleService.isAvailable ? "Available" : "Unavailable",
                    isHealthy: appleService.isAvailable
                )
                DiagnosticRow(
                    label: "Authorization",
                    value: appleService.authorizationStatus.rawValue.description,
                    isHealthy: appleService.authorizationStatus == .authorized
                )
                DiagnosticRow(
                    label: "Supported Locales",
                    value: "\(appleService.supportedLocales.count)",
                    isHealthy: true
                )
            } header: {
                Text("Apple Speech Recognition")
            }
            
            // Network Section
            Section {
                DiagnosticRow(label: "Connection", value: networkMonitor.isConnected ? "Connected" : "Offline", isHealthy: networkMonitor.isConnected)
                DiagnosticRow(label: "Type", value: networkMonitor.connectionType.displayName, isHealthy: true)
                DiagnosticRow(label: "Quality Score", value: String(format: "%.1f", networkMonitor.getNetworkQualityScore()), isHealthy: networkMonitor.getNetworkQualityScore() > 0.5)
            } header: {
                Text("Network")
            }
        }
        .navigationTitle("Service Diagnostics")
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

// MARK: - SegmentRowView

struct SegmentRowView: View {
    let segment: TranscriptionSegment
    let onRetry: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Segment \(segment.segmentIndex + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(segment.formattedTimeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                statusIndicator
                
                if let text = segment.transcriptionText, !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundColor(.secondary)
                } else {
                    Text(segment.status.description)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                
                Spacer()
                
                if segment.needsRetry {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture(perform: onTap)
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch segment.status {
        case .pending, .queued:
            return .orange
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

// MARK: - SegmentDetailSheet

struct SegmentDetailSheet: View {
    let segment: TranscriptionSegment
    
    var body: some View {
        NavigationView {
            List {
                Section("Details") {
                    DetailRow(label: "Segment", value: "\(segment.segmentIndex + 1)")
                    DetailRow(label: "Time Range", value: segment.formattedTimeRange)
                    DetailRow(label: "Duration", value: "\(segment.duration.formatted()) seconds")
                    DetailRow(label: "Status", value: segment.status.description)
                }
                
                if let text = segment.transcriptionText {
                    Section("Transcription") {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                
                if let confidence = segment.confidence {
                    Section("Confidence") {
                        ProgressView(value: confidence, total: 1.0)
                        Text(String(format: "%.1f%%", confidence * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = segment.errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("Service") {
                    Text(segment.service.displayName)
                }
            }
            .navigationTitle("Segment Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { }
                }
            }
        }
    }
}

// MARK: - Helper Views

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

extension TranscriptionStatus {
    var description: String {
        switch self {
        case .pending: return "Pending"
        case .queued: return "Queued"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}


// MARK: - Helper Views

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String
    let isHealthy: Bool
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(isHealthy ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(value)
                    .foregroundColor(.secondary)
            }
        }
    }
}

extension TimeInterval {
    func formatted() -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "0"
    }
}
