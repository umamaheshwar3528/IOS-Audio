import SwiftUI

struct RecordingSessionListView: View {
    @ObservedObject private var fileManagerService = FileManagerService.shared
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: RecordingSession?
    @State private var selectedSession: RecordingSession?
    @State private var showingError = false
    @State private var errorMessage = ""
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case transcribed = "Transcribed"
        case notTranscribed = "Not Transcribed"
        case processing = "Processing"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .transcribed: return "checkmark.circle"
            case .notTranscribed: return "circle"
            case .processing: return "clock"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .blue
            case .transcribed: return .green
            case .notTranscribed: return .gray
            case .processing: return .orange
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter bar
                filterBar
                
                // Content
                contentView
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done", action: { dismiss() })
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    summaryText
                }
            }
            .searchable(text: $searchText, prompt: "Search recordings or transcriptions")
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await refreshData()
            }
            .alert("Delete Recording", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        deleteRecording(session)
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $selectedSession) { session in
                NavigationView {
                    RecordingDetailView(session: session)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    selectedSession = nil
                                }
                            }
                        }
                }
            }
        }
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FilterOption.allCases) { filter in
                    FilterChip(
                        filter: filter,
                        isSelected: selectedFilter == filter,
                        count: countForFilter(filter)
                    ) {
                        withAnimation(.smooth(duration: 0.3)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        Group {
            if filteredRecordings.isEmpty {
                EmptyStateView(filter: selectedFilter, searchText: searchText)
            } else {
                recordingsList
            }
        }
    }
    
    private var recordingsList: some View {
        List {
            ForEach(groupedRecordings.keys.sorted(by: >), id: \.self) { date in
                Section {
                    ForEach(groupedRecordings[date] ?? []) { session in
                        SessionRow(session: session)
                            .listRowBackground(Color(.systemBackground))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .onTapGesture {
                                selectedSession = session
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                swipeActions(for: session)
                            }
                            .contextMenu {
                                contextMenuActions(for: session)
                            }
                    }
                } header: {
                    SectionHeader(
                        date: date,
                        sessions: groupedRecordings[date] ?? [],
                        transcriptionManager: transcriptionManager
                    )
                }
            }
        }
        .listStyle(.plain)
        .animation(.smooth(duration: 0.3), value: filteredRecordings.count)
    }
    
    private var summaryText: some View {
        Text("\(filteredRecordings.count)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(.systemGray5))
            )
    }
    
    // MARK: - Computed Properties
    
    private var filteredRecordings: [RecordingSession] {
        let recordings = fileManagerService.recordings.filter { session in
            // Text search
            if !searchText.isEmpty {
                let titleMatch = session.title.localizedCaseInsensitiveContains(searchText)
                let transcriptionMatch = transcriptionManager.getTranscriptionText(for: session.id)?
                    .localizedCaseInsensitiveContains(searchText) ?? false
                
                if !titleMatch && !transcriptionMatch {
                    return false
                }
            }
            
            // Filter
            switch selectedFilter {
            case .all:
                return true
            case .transcribed:
                return hasTranscription(for: session)
            case .notTranscribed:
                return !hasTranscription(for: session) && !isTranscribing(session)
            case .processing:
                return isTranscribing(session)
            }
        }
        
        return recordings.sorted { $0.startTime > $1.startTime }
    }
    
    private var groupedRecordings: [Date: [RecordingSession]] {
        Dictionary(grouping: filteredRecordings) { session in
            Calendar.current.startOfDay(for: session.startTime)
        }
    }
    
    // MARK: - Helper Methods
    
    private func hasTranscription(for session: RecordingSession) -> Bool {
        if let text = transcriptionManager.getTranscriptionText(for: session.id) {
            return !text.isEmpty
        }
        return false
    }
    
    private func isTranscribing(_ session: RecordingSession) -> Bool {
        return transcriptionManager.activeJobs.contains { $0.sessionId == session.id }
    }
    
    private func countForFilter(_ filter: FilterOption) -> Int {
        fileManagerService.recordings.filter { session in
            switch filter {
            case .all:
                return true
            case .transcribed:
                return hasTranscription(for: session)
            case .notTranscribed:
                return !hasTranscription(for: session) && !isTranscribing(session)
            case .processing:
                return isTranscribing(session)
            }
        }.count
    }
    
    // MARK: - Actions
    
    private func deleteRecording(_ session: RecordingSession) {
        do {
            transcriptionManager.stopTranscriptionJob(session.id)
            AudioSegmentProcessor.shared.cleanupSegmentFiles(for: session.id)
            try fileManagerService.deleteRecording(session)
        } catch {
            showError("Failed to delete recording: \(error.localizedDescription)")
        }
    }
    
    private func startTranscription(for session: RecordingSession) {
        _ = transcriptionManager.startTranscriptionJob(for: session)
    }
    
    private func shareTranscription(for session: RecordingSession) {
        guard let text = transcriptionManager.getTranscriptionText(for: session.id) else { return }
        shareContent([text])
    }
    
    private func shareRecording(_ session: RecordingSession) {
        guard let fileURL = session.fileURL else { return }
        shareContent([fileURL])
    }
    
    private func shareContent(_ items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func refreshData() async {
        DispatchQueue.main.async {
            self.fileManagerService.objectWillChange.send()
            self.transcriptionManager.objectWillChange.send()
        }
    }
    
    // MARK: - Context Actions
    
    @ViewBuilder
    private func swipeActions(for session: RecordingSession) -> some View {
        if hasTranscription(for: session) {
            Button("View") {
                selectedSession = session
            }
            .tint(.blue)
        } else if !isTranscribing(session) {
            Button("Transcribe") {
                startTranscription(for: session)
            }
            .tint(.green)
        }
        
        Button("Delete") {
            sessionToDelete = session
            showingDeleteAlert = true
        }
        .tint(.red)
    }
    
    @ViewBuilder
    private func contextMenuActions(for session: RecordingSession) -> some View {
        Button("Open", action: { selectedSession = session })
        
        Divider()
        
        if hasTranscription(for: session) {
            Button("Share Transcription", action: { shareTranscription(for: session) })
        } else if !isTranscribing(session) {
            Button("Start Transcription", action: { startTranscription(for: session) })
        }
        
        Button("Share Recording", action: { shareRecording(session) })
        
        Divider()
        
        Button("Delete", role: .destructive) {
            sessionToDelete = session
            showingDeleteAlert = true
        }
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let filter: RecordingSessionListView.FilterOption
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                
                Text(filter.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? filter.color : Color(.systemGray6))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let date: Date
    let sessions: [RecordingSession]
    let transcriptionManager: TranscriptionManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(relativeDateText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if transcribedCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text("\(transcribedCount)/\(sessions.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
    
    private var transcribedCount: Int {
        sessions.filter { session in
            if let text = transcriptionManager.getTranscriptionText(for: session.id) {
                return !text.isEmpty
            }
            return false
        }.count
    }
    
    private var relativeDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.year())
        }
    }
}

struct SessionRow: View {
    let session: RecordingSession
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            statusIndicator
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Title and duration
                HStack {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(session.formattedDuration)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )
                }
                
                // Time and size
                HStack {
                    Text(session.startTime.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if session.fileSize > 0 {
                        Text(session.formattedFileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Transcription status
                transcriptionStatus
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 40, height: 40)
            
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundColor(statusColor)
        }
    }
    
    private var transcriptionStatus: some View {
        Group {
            if let job = currentJob {
                if job.isCompleted {
                    if job.hasFailures && job.completedSegments == 0 {
                        statusLabel("Failed", color: .red, icon: "exclamationmark.triangle.fill")
                    } else if job.hasFailures {
                        statusLabel("Partial (\(job.completedSegments)/\(job.totalSegments))",
                                  color: .orange, icon: "checkmark.circle.badge.exclamationmark")
                    } else {
                        statusLabel("Transcribed", color: .green, icon: "checkmark.circle.fill")
                    }
                } else {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        
                        Text("Transcribing \(Int(job.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            } else if hasTranscription {
                statusLabel("Transcribed", color: .green, icon: "doc.text.fill")
            }
        }
    }
    
    private func statusLabel(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
    }
    
    // MARK: - Computed Properties
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == session.id } ??
        transcriptionManager.completedJobs.first { $0.sessionId == session.id }
    }
    
    private var hasTranscription: Bool {
        if let text = transcriptionManager.getTranscriptionText(for: session.id) {
            return !text.isEmpty
        }
        return false
    }
    
    private var statusColor: Color {
        if let job = currentJob {
            if job.isCompleted {
                return job.hasFailures ? (job.completedSegments > 0 ? .orange : .red) : .green
            } else {
                return .blue
            }
        } else if hasTranscription {
            return .green
        } else {
            return .gray
        }
    }
    
    private var statusIcon: String {
        if let job = currentJob {
            if job.isCompleted {
                if job.hasFailures && job.completedSegments == 0 {
                    return "exclamationmark.triangle.fill"
                } else if job.hasFailures {
                    return "checkmark.circle.badge.exclamationmark"
                } else {
                    return "checkmark.circle.fill"
                }
            } else {
                return "clock.fill"
            }
        } else if hasTranscription {
            return "doc.text.fill"
        } else {
            return "waveform"
        }
    }
}

struct EmptyStateView: View {
    let filter: RecordingSessionListView.FilterOption
    let searchText: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: emptyIcon)
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text(emptyTitle)
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text(emptyMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptyIcon: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        }
        
        switch filter {
        case .all: return "mic.slash"
        case .transcribed: return "doc.text"
        case .notTranscribed: return "text.badge.xmark"
        case .processing: return "clock"
        }
    }
    
    private var emptyTitle: String {
        if !searchText.isEmpty {
            return "No Results"
        }
        
        switch filter {
        case .all: return "No Recordings"
        case .transcribed: return "No Transcriptions"
        case .notTranscribed: return "All Transcribed"
        case .processing: return "Nothing Processing"
        }
    }
    
    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "Try adjusting your search terms or filters."
        }
        
        switch filter {
        case .all:
            return "Your recordings will appear here after you make them."
        case .transcribed:
            return "Recordings with completed transcriptions will appear here."
        case .notTranscribed:
            return "Great! All your recordings have been transcribed."
        case .processing:
            return "Recordings currently being transcribed will appear here."
        }
    }
}
