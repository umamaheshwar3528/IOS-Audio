import SwiftUI

struct RecordingSessionListView: View {
    @ObservedObject private var fileManagerService = FileManagerService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false
    @State private var sessionToDelete: RecordingSession?
    
    var body: some View {
        NavigationView {
            List {
                if filteredRecordings.isEmpty {
                    emptyStateView
                } else {
                    ForEach(groupedRecordings.keys.sorted(by: >), id: \.self) { date in
                        Section(header: Text(date, style: .date)) {
                            ForEach(groupedRecordings[date] ?? []) { session in
                                RecordingSessionRow(session: session)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) {
                                            sessionToDelete = session
                                            showingDeleteConfirmation = true
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recordings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(fileManagerService.recordings.count) sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .refreshable {
                // Refresh recordings
                fileManagerService.objectWillChange.send()
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
        }
    }
    
    private var filteredRecordings: [RecordingSession] {
        if searchText.isEmpty {
            return fileManagerService.recordings
        } else {
            return fileManagerService.recordings.filter { session in
                session.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var groupedRecordings: [Date: [RecordingSession]] {
        Dictionary(grouping: filteredRecordings) { session in
            Calendar.current.startOfDay(for: session.startTime)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Recordings")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Your recordings will appear here after you make them.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func deleteRecording(_ session: RecordingSession) {
        do {
            try fileManagerService.deleteRecording(session)
        } catch {
            Logger.shared.error("Failed to delete recording: \(error)")
        }
    }
}

struct RecordingSessionRow: View {
    let session: RecordingSession
    
    var body: some View {
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
        }
        .padding(.vertical, 2)
    }
}
