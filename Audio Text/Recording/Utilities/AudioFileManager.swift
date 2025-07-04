import AVFoundation
import Foundation

class AudioFileManager {
    static let shared = AudioFileManager()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Directory Management
    
    var recordingsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent(AudioConstants.audioDirectoryName)
        
        if !fileManager.fileExists(atPath: recordingsPath.path) {
            try? fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }
        
        return recordingsPath
    }
    
    var tempDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tempPath = documentsPath.appendingPathComponent(AudioConstants.tempDirectoryName)
        
        if !fileManager.fileExists(atPath: tempPath.path) {
            try? fileManager.createDirectory(at: tempPath, withIntermediateDirectories: true)
        }
        
        return tempPath
    }
    
    // MARK: - File Operations
    
    func createRecordingFile(for session: RecordingSession) -> URL? {
        let fileName = generateFileName(for: session)
        let fileURL = recordingsDirectory.appendingPathComponent(fileName)
        
        // Create empty file
        fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        
        return fileURL
    }
    
    func moveFromTemp(tempURL: URL, to finalURL: URL) throws {
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: tempURL, to: finalURL)
    }
    
    func deleteRecording(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
    
    func getFileSize(at url: URL) -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    func availableStorageSpace() -> Int64 {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            return systemAttributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    func hasInsufficientStorage() -> Bool {
        return availableStorageSpace() < AudioConstants.minStorageRequired
    }
    
    // MARK: - Cleanup
    
    func cleanupTempFiles() {
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in tempFiles {
                try? fileManager.removeItem(at: file)
            }
        } catch {
            Logger.shared.error("Failed to cleanup temp files: \(error)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func generateFileName(for session: RecordingSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: session.startTime)
        return "Recording_\(timestamp).\(AudioConstants.audioFileExtension)"
    }
}
