import Foundation
import Combine

class FileManagerService: ObservableObject {
    static let shared = FileManagerService()
    
    @Published var availableSpace: Int64 = 0
    @Published var recordings: [RecordingSession] = []
    
    private let audioFileManager = AudioFileManager.shared
    private var storageMonitorTimer: Timer?
    
    private init() {
        updateAvailableSpace()
        startStorageMonitoring()
        loadRecordings()
    }
    
    deinit {
        storageMonitorTimer?.invalidate()
    }
    
    // MARK: - Storage Monitoring
    
    private func startStorageMonitoring() {
        storageMonitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            self.updateAvailableSpace()
        }
    }
    
    private func updateAvailableSpace() {
        availableSpace = audioFileManager.availableStorageSpace()
    }
    
    func hasInsufficientStorage() -> Bool {
        return audioFileManager.hasInsufficientStorage()
    }
    
    // MARK: - Recording Management
    
    func createRecordingFile(for session: RecordingSession) throws -> URL {
        if hasInsufficientStorage() {
            throw RecordingError.insufficientStorage
        }
        
        guard let fileURL = audioFileManager.createRecordingFile(for: session) else {
            throw RecordingError.fileCreationFailed
        }
        
        return fileURL
    }
    
    func saveRecording(_ session: RecordingSession) {
        recordings.append(session)
        recordings.sort { $0.startTime > $1.startTime }
        saveRecordingsToDefaults()
    }
    
    func deleteRecording(_ session: RecordingSession) throws {
        if let fileURL = session.fileURL {
            try audioFileManager.deleteRecording(at: fileURL)
        }
        
        recordings.removeAll { $0.id == session.id }
        saveRecordingsToDefaults()
    }
    
    func updateRecording(_ session: RecordingSession) {
        if let index = recordings.firstIndex(where: { $0.id == session.id }) {
            recordings[index] = session
            saveRecordingsToDefaults()
        }
    }
    
    // MARK: - Persistence
    
    private func loadRecordings() {
        guard let data = UserDefaults.standard.data(forKey: "savedRecordings"),
              let decodedRecordings = try? JSONDecoder().decode([RecordingSession].self, from: data) else {
            return
        }
        
        recordings = decodedRecordings.sorted { $0.startTime > $1.startTime }
    }
    
    private func saveRecordingsToDefaults() {
        if let encodedData = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(encodedData, forKey: "savedRecordings")
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupTempFiles() {
        audioFileManager.cleanupTempFiles()
    }
}
