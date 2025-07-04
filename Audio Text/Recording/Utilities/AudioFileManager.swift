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
        
        // Don't create an empty file here - let AVAudioFile create it properly
        // Just return the URL where the file should be created
        
        Logger.shared.info("Generated recording file path: \(fileURL.path)")
        return fileURL
    }
    
    func moveFromTemp(tempURL: URL, to finalURL: URL) throws {
        // Validate temp file exists and has content
        guard fileManager.fileExists(atPath: tempURL.path) else {
            throw AudioFileError.tempFileNotFound
        }
        
        let fileSize = getFileSize(at: tempURL)
        guard fileSize > 0 else {
            throw AudioFileError.tempFileEmpty
        }
        
        // Validate temp file is a valid audio file
        try validateAudioFile(at: tempURL)
        
        // Remove final file if it already exists
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
            Logger.shared.info("Removed existing file at final location")
        }
        
        // Move temp file to final location
        try fileManager.moveItem(at: tempURL, to: finalURL)
        
        // Verify the move was successful
        guard fileManager.fileExists(atPath: finalURL.path) else {
            throw AudioFileError.moveOperationFailed
        }
        
        let finalSize = getFileSize(at: finalURL)
        guard finalSize == fileSize else {
            throw AudioFileError.fileCorruptedDuringMove
        }
        
        Logger.shared.info("Successfully moved file from temp to final location. Size: \(finalSize) bytes")
    }
    
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        // Remove destination if it exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        // Copy the file
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        
        // Verify the copy
        let sourceSize = getFileSize(at: sourceURL)
        let destSize = getFileSize(at: destinationURL)
        
        guard sourceSize == destSize && destSize > 0 else {
            try? fileManager.removeItem(at: destinationURL) // Clean up failed copy
            throw AudioFileError.copyOperationFailed
        }
        
        Logger.shared.info("Successfully copied file. Size: \(destSize) bytes")
    }
    
    func deleteRecording(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            Logger.shared.warning("Attempted to delete non-existent file: \(url.path)")
            return
        }
        
        try fileManager.removeItem(at: url)
        Logger.shared.info("Successfully deleted recording: \(url.lastPathComponent)")
    }
    
    func getFileSize(at url: URL) -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            Logger.shared.error("Failed to get file size for \(url.path): \(error)")
            return 0
        }
    }
    
    func getFileCreationDate(at url: URL) -> Date? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.creationDate] as? Date
        } catch {
            Logger.shared.error("Failed to get file creation date for \(url.path): \(error)")
            return nil
        }
    }
    
    func getFileModificationDate(at url: URL) -> Date? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date
        } catch {
            Logger.shared.error("Failed to get file modification date for \(url.path): \(error)")
            return nil
        }
    }
    
    // MARK: - Storage Management
    
    func availableStorageSpace() -> Int64 {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            return systemAttributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            Logger.shared.error("Failed to get available storage space: \(error)")
            return 0
        }
    }
    
    func totalStorageSpace() -> Int64 {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            return systemAttributes[.systemSize] as? Int64 ?? 0
        } catch {
            Logger.shared.error("Failed to get total storage space: \(error)")
            return 0
        }
    }
    
    func hasInsufficientStorage() -> Bool {
        return availableStorageSpace() < AudioConstants.minStorageRequired
    }
    
    func getStorageUsageByRecordings() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let files = try fileManager.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            
            for file in files {
                totalSize += getFileSize(at: file)
            }
        } catch {
            Logger.shared.error("Failed to calculate recordings storage usage: \(error)")
        }
        
        return totalSize
    }
    
    // MARK: - Audio File Validation
    
    func validateAudioFile(at url: URL) throws {
        // Check if file exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw AudioFileError.fileNotFound
        }
        
        // Check file size
        let fileSize = getFileSize(at: url)
        guard fileSize > 0 else {
            throw AudioFileError.fileEmpty
        }
        
        // Try to open with AVAudioFile to validate format
        do {
            let audioFile = try AVAudioFile(forReading: url)
            
            // Validate basic properties
            guard audioFile.length > 0 else {
                throw AudioFileError.invalidAudioFormat
            }
            
            guard audioFile.fileFormat.sampleRate > 0 else {
                throw AudioFileError.invalidAudioFormat
            }
            
            guard audioFile.fileFormat.channelCount > 0 else {
                throw AudioFileError.invalidAudioFormat
            }
            
            // Calculate duration
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            guard duration > 0 else {
                throw AudioFileError.invalidAudioFormat
            }
            
            Logger.shared.info("Audio file validation successful - Duration: \(String(format: "%.2f", duration))s, Sample Rate: \(audioFile.fileFormat.sampleRate)Hz, Channels: \(audioFile.fileFormat.channelCount)")
            
        } catch let error as AudioFileError {
            throw error
        } catch {
            Logger.shared.error("Audio file validation failed: \(error)")
            throw AudioFileError.invalidAudioFormat
        }
    }
    
    func getAudioFileInfo(at url: URL) -> AudioFileInfo? {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let fileSize = getFileSize(at: url)
            let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            
            return AudioFileInfo(
                url: url,
                fileSize: fileSize,
                duration: duration,
                sampleRate: audioFile.fileFormat.sampleRate,
                channelCount: Int(audioFile.fileFormat.channelCount),
                frameCount: AVAudioFrameCount(audioFile.length),
                format: String(describing: audioFile.fileFormat.commonFormat)
            )
        } catch {
            Logger.shared.error("Failed to get audio file info: \(error)")
            return nil
        }
    }
    
    // MARK: - File Discovery
    
    func getAllRecordingFiles() -> [URL] {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter for audio files only
            return files.filter { url in
                let pathExtension = url.pathExtension.lowercased()
                return AudioConstants.supportedAudioExtensions.contains(pathExtension)
            }.sorted { file1, file2 in
                // Sort by creation date, newest first
                let date1 = getFileCreationDate(at: file1) ?? Date.distantPast
                let date2 = getFileCreationDate(at: file2) ?? Date.distantPast
                return date1 > date2
            }
        } catch {
            Logger.shared.error("Failed to get recording files: \(error)")
            return []
        }
    }
    
    func findRecordingFile(for sessionId: UUID) -> URL? {
        let files = getAllRecordingFiles()
        return files.first { url in
            url.lastPathComponent.contains(sessionId.uuidString)
        }
    }
    
    // MARK: - Cleanup Operations
    
    func cleanupTempFiles() {
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            var cleanedCount = 0
            var cleanedSize: Int64 = 0
            
            for file in tempFiles {
                let fileSize = getFileSize(at: file)
                try fileManager.removeItem(at: file)
                cleanedCount += 1
                cleanedSize += fileSize
            }
            
            Logger.shared.info("Cleaned up \(cleanedCount) temp files, freed \(ByteCountFormatter.string(fromByteCount: cleanedSize, countStyle: .file))")
        } catch {
            Logger.shared.error("Failed to cleanup temp files: \(error)")
        }
    }
    
    func cleanupOldRecordings(olderThan timeInterval: TimeInterval) {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        let files = getAllRecordingFiles()
        var cleanedCount = 0
        var cleanedSize: Int64 = 0
        
        for file in files {
            if let creationDate = getFileCreationDate(at: file),
               creationDate < cutoffDate {
                let fileSize = getFileSize(at: file)
                do {
                    try deleteRecording(at: file)
                    cleanedCount += 1
                    cleanedSize += fileSize
                } catch {
                    Logger.shared.error("Failed to delete old recording \(file.lastPathComponent): \(error)")
                }
            }
        }
        
        Logger.shared.info("Cleaned up \(cleanedCount) old recordings, freed \(ByteCountFormatter.string(fromByteCount: cleanedSize, countStyle: .file))")
    }
    
    func cleanupCorruptedFiles() {
        let files = getAllRecordingFiles()
        var cleanedCount = 0
        var cleanedSize: Int64 = 0
        
        for file in files {
            do {
                try validateAudioFile(at: file)
            } catch {
                // File is corrupted, delete it
                let fileSize = getFileSize(at: file)
                do {
                    try deleteRecording(at: file)
                    cleanedCount += 1
                    cleanedSize += fileSize
                    Logger.shared.info("Deleted corrupted file: \(file.lastPathComponent)")
                } catch {
                    Logger.shared.error("Failed to delete corrupted file \(file.lastPathComponent): \(error)")
                }
            }
        }
        
        Logger.shared.info("Cleaned up \(cleanedCount) corrupted files, freed \(ByteCountFormatter.string(fromByteCount: cleanedSize, countStyle: .file))")
    }
    
    // MARK: - Private Helpers
    
    private func generateFileName(for session: RecordingSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: session.startTime)
        return "Recording_\(timestamp).\(AudioConstants.audioFileExtension)"
    }
    
    // MARK: - File System Monitoring
    
    func monitorDiskUsage() -> DiskUsageInfo {
        let totalSpace = totalStorageSpace()
        let availableSpace = availableStorageSpace()
        let usedSpace = totalSpace - availableSpace
        let recordingsSpace = getStorageUsageByRecordings()
        
        return DiskUsageInfo(
            totalSpace: totalSpace,
            availableSpace: availableSpace,
            usedSpace: usedSpace,
            recordingsSpace: recordingsSpace,
            usagePercentage: totalSpace > 0 ? Double(usedSpace) / Double(totalSpace) : 0
        )
    }
}

// MARK: - Supporting Data Structures

struct AudioFileInfo {
    let url: URL
    let fileSize: Int64
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int
    let frameCount: AVAudioFrameCount
    let format: String
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
    
    var formattedFileSize: String {
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct DiskUsageInfo {
    let totalSpace: Int64
    let availableSpace: Int64
    let usedSpace: Int64
    let recordingsSpace: Int64
    let usagePercentage: Double
    
    var isLowOnSpace: Bool {
        return availableSpace < AudioConstants.minStorageRequired
    }
    
    var formattedTotalSpace: String {
        return ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file)
    }
    
    var formattedAvailableSpace: String {
        return ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
    }
    
    var formattedRecordingsSpace: String {
        return ByteCountFormatter.string(fromByteCount: recordingsSpace, countStyle: .file)
    }
}

// MARK: - Audio File Errors

enum AudioFileError: Error, LocalizedError {
    case fileNotFound
    case fileEmpty
    case tempFileNotFound
    case tempFileEmpty
    case invalidAudioFormat
    case moveOperationFailed
    case copyOperationFailed
    case fileCorruptedDuringMove
    case insufficientSpace
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .fileEmpty:
            return "Audio file is empty"
        case .tempFileNotFound:
            return "Temporary audio file not found"
        case .tempFileEmpty:
            return "Temporary audio file is empty"
        case .invalidAudioFormat:
            return "Invalid or corrupted audio file format"
        case .moveOperationFailed:
            return "Failed to move audio file"
        case .copyOperationFailed:
            return "Failed to copy audio file"
        case .fileCorruptedDuringMove:
            return "Audio file was corrupted during move operation"
        case .insufficientSpace:
            return "Insufficient storage space"
        case .permissionDenied:
            return "Permission denied to access audio file"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound, .tempFileNotFound:
            return "Try recording again"
        case .fileEmpty, .tempFileEmpty:
            return "Ensure the recording was not interrupted"
        case .invalidAudioFormat:
            return "Try recording with different settings"
        case .moveOperationFailed, .copyOperationFailed, .fileCorruptedDuringMove:
            return "Try again or restart the app"
        case .insufficientSpace:
            return "Free up storage space and try again"
        case .permissionDenied:
            return "Check app permissions in Settings"
        }
    }
}

extension URL {
    var isAudioFile: Bool {
        let pathExtension = self.pathExtension.lowercased()
        return AudioConstants.supportedAudioExtensions.contains(pathExtension)
    }
}
