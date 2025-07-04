import SwiftUI

struct RecordingSessionListView: View {
    @ObservedObject private var fileManagerService = FileManagerService.shared
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false
    @State private var sessionToDelete: RecordingSession?
    @State private var selectedSession: RecordingSession?
    @State private var filterOption: FilterOption = .all
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case transcribed = "Transcribed"
        case notTranscribed = "Not Transcribed"
        case processing = "Processing"
        
        var systemImage: String {
            switch self {
            case .all: return "list.bullet"
            case .transcribed: return "checkmark.circle"
            case .notTranscribed: return "circle"
            case .processing: return "clock"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter Pills
                filterSection
                
                // List
                List {
                    if filteredRecordings.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(groupedRecordings.keys.sorted(by: >), id: \.self) { date in
                            Section(header: sectionHeader(for: date)) {
                                ForEach(groupedRecordings[date] ?? []) { session in
                                    RecordingSessionRow(session: session)
                                        .onTapGesture {
                                            selectedSession = session
                                        }
                                        .contextMenu {
                                            contextMenuActions(for: session)
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            swipeActions(for: session)
                                        }
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recordings or transcriptions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Text("\(filteredRecordings.count) sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Menu {
                            ForEach(FilterOption.allCases, id: \.self) { option in
                                Button(action: { filterOption = option }) {
                                    Label(option.rawValue, systemImage: option.systemImage)
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .refreshable {
                fileManagerService.objectWillChange.send()
                transcriptionManager.objectWillChange.send()
            }
            .alert("Delete Recording", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        deleteRecording(session)
                    }
                }
            } message: {
                Text("This action cannot be undone.")
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
    
    // MARK: - View Components
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    FilterPill(
                        option: option,
                        isSelected: filterOption == option,
                        count: countForFilter(option)
                    ) {
                        filterOption = option
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private func sectionHeader(for date: Date) -> some View {
        HStack {
            Text(date, style: .date)
                .font(.headline)
            
            Spacer()
            
            let sessionsForDate = groupedRecordings[date] ?? []
            let transcribedCount = sessionsForDate.filter { hasTranscription(for: $0) }.count
            
            if transcribedCount > 0 {
                Text("\(transcribedCount)/\(sessionsForDate.count) transcribed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(emptyStateTitle)
                .font(.title2)
                .fontWeight(.medium)
            
            Text(emptyStateMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateIcon: String {
        switch filterOption {
        case .all:
            return "mic.slash"
        case .transcribed:
            return "doc.text"
        case .notTranscribed:
            return "text.badge.xmark"
        case .processing:
            return "clock"
        }
    }
    
    private var emptyStateTitle: String {
        switch filterOption {
        case .all:
            return "No Recordings"
        case .transcribed:
            return "No Transcribed Recordings"
        case .notTranscribed:
            return "All Recordings Transcribed"
        case .processing:
            return "No Processing Recordings"
        }
    }
    
    private var emptyStateMessage: String {
        switch filterOption {
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
    
    // MARK: - Context Menu and Swipe Actions
    
    @ViewBuilder
    private func contextMenuActions(for session: RecordingSession) -> some View {
        if hasTranscription(for: session) {
            Button("View Transcription") {
                selectedSession = session
            }
            
            Button("Share Transcription") {
                shareTranscription(for: session)
            }
        } else if !isTranscribing(session: session) {
            Button("Start Transcription") {
                startTranscription(for: session)
            }
        }
        
        Divider()
        
        Button("Share Recording") {
            shareRecording(session)
        }
        
        Button("Delete", role: .destructive) {
            sessionToDelete = session
            showingDeleteConfirmation = true
        }
    }
    
    @ViewBuilder
    private func swipeActions(for session: RecordingSession) -> some View {
        if hasTranscription(for: session) {
            Button("View") {
                selectedSession = session
            }
            .tint(.blue)
        } else if !isTranscribing(session: session) {
            Button("Transcribe") {
                startTranscription(for: session)
            }
            .tint(.green)
        }
        
        Button("Delete") {
            sessionToDelete = session
            showingDeleteConfirmation = true
        }
        .tint(.red)
    }
    
    // MARK: - Computed Properties
    
    private var filteredRecordings: [RecordingSession] {
        let recordings = fileManagerService.recordings.filter { session in
            // Apply text search
            if !searchText.isEmpty {
                let matchesTitle = session.title.localizedCaseInsensitiveContains(searchText)
                let matchesTranscription = transcriptionManager.getTranscriptionText(for: session.id)?
                    .localizedCaseInsensitiveContains(searchText) ?? false
                
                if !matchesTitle && !matchesTranscription {
                    return false
                }
            }
            
            // Apply filter
            switch filterOption {
            case .all:
                return true
            case .transcribed:
                return hasTranscription(for: session)
            case .notTranscribed:
                return !hasTranscription(for: session) && !isTranscribing(session: session)
            case .processing:
                return isTranscribing(session: session)
            }
        }
        
        return recordings
    }
    
    private var groupedRecordings: [Date: [RecordingSession]] {
        Dictionary(grouping: filteredRecordings) { session in
            Calendar.current.startOfDay(for: session.startTime)
        }
    }
    
    // MARK: - Helper Methods
    
    private func hasTranscription(for session: RecordingSession) -> Bool {
        let text = transcriptionManager.getTranscriptionText(for: session.id)
        return text != nil && !text!.isEmpty
    }
    
    private func isTranscribing(session: RecordingSession) -> Bool {
        return transcriptionManager.activeJobs.contains { $0.sessionId == session.id }
    }
    
    private func countForFilter(_ option: FilterOption) -> Int {
        fileManagerService.recordings.filter { session in
            switch option {
            case .all:
                return true
            case .transcribed:
                return hasTranscription(for: session)
            case .notTranscribed:
                return !hasTranscription(for: session) && !isTranscribing(session: session)
            case .processing:
                return isTranscribing(session: session)
            }
        }.count
    }
    
    // MARK: - Actions
    
    private func deleteRecording(_ session: RecordingSession) {
        do {
            // Also cleanup any transcription data
            transcriptionManager.stopTranscriptionJob(session.id)
            AudioSegmentProcessor.shared.cleanupSegmentFiles(for: session.id)
            
            try fileManagerService.deleteRecording(session)
        } catch {
            Logger.shared.error("Failed to delete recording: \(error)")
        }
    }
    
    private func startTranscription(for session: RecordingSession) {
        let _ = transcriptionManager.startTranscriptionJob(for: session)
    }
    
    private func shareTranscription(for session: RecordingSession) {
        guard let text = transcriptionManager.getTranscriptionText(for: session.id) else { return }
        
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
    
    private func shareRecording(_ session: RecordingSession) {
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

// MARK: - Supporting Views

struct FilterPill: View {
    let option: RecordingSessionListView.FilterOption
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: option.systemImage)
                    .font(.caption)
                
                Text(option.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("(\(count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RecordingSessionRow: View {
    let session: RecordingSession
    
    @ObservedObject private var transcriptionManager = TranscriptionManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(session.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(session.startTime, style: .time)
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
                transcriptionStatusView
            }
            
            // Transcription indicator
            VStack {
                transcriptionIndicator
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
    
    private var transcriptionStatusView: some View {
        Group {
            if let job = currentJob {
                if job.isCompleted {
                    if job.hasFailures && job.completedSegments == 0 {
                        // Completely failed
                        Label("Transcription failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else if job.hasFailures {
                        // Partially failed
                        Label("Partial transcription (\(job.completedSegments)/\(job.totalSegments))", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        // Completely successful
                        Label("Transcription complete", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                } else {
                    // In progress
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        
                        Text("Transcribing... \(Int(job.progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            } else if hasTranscription {
                // Has transcription but no job (legacy or external)
                Label("Transcription available", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
    }
    
    private var transcriptionIndicator: some View {
        Group {
            if let job = currentJob {
                if job.isCompleted {
                    if job.hasFailures && job.completedSegments == 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                    } else if job.hasFailures {
                        Image(systemName: "checkmark.circle.badge.exclamationmark")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            } else if hasTranscription {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
    }
    
    // MARK: - Computed Properties
    
    private var currentJob: TranscriptionJob? {
        transcriptionManager.activeJobs.first { $0.sessionId == session.id } ??
        transcriptionManager.completedJobs.first { $0.sessionId == session.id }
    }
    
    private var hasTranscription: Bool {
        let text = transcriptionManager.getTranscriptionText(for: session.id)
        return text != nil && !text!.isEmpty
    }
}
