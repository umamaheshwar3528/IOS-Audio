import Foundation

struct RecordingSession: Identifiable, Codable {
    let id: UUID
    let title: String
    let startTime: Date
    var endTime: Date?
    var fileURL: URL?
    let configuration: AudioConfiguration
    var fileSize: Int64 = 0
    
    init(title: String = "", configuration: AudioConfiguration = .default) {
        self.id = UUID()
        self.title = title.isEmpty ? "Recording \(DateFormatter.recordingTitle.string(from: Date()))" : title
        self.startTime = Date()
        self.configuration = configuration
    }
    
    var duration: TimeInterval {
        guard let endTime = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return endTime.timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        return duration.formattedDuration
    }
    
    var formattedFileSize: String {
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var isComplete: Bool {
        return endTime != nil && fileURL != nil
    }
}
