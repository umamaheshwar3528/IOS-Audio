import Foundation
import os.log

class Logger {
    static let shared = Logger()
    
    private let osLog: OSLog
    
    private init() {
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "AudioText", category: "Recording")
    }
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log("[DEBUG] %{public}@ - %{public}@:%d %{public}@", log: osLog, type: .debug,
               URL(fileURLWithPath: file).lastPathComponent, function, line, message)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log("[INFO] %{public}@ - %{public}@:%d %{public}@", log: osLog, type: .info,
               URL(fileURLWithPath: file).lastPathComponent, function, line, message)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log("[ERROR] %{public}@ - %{public}@:%d %{public}@", log: osLog, type: .error,
               URL(fileURLWithPath: file).lastPathComponent, function, line, message)
    }
    
    func fault(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log("[FAULT] %{public}@ - %{public}@:%d %{public}@", log: osLog, type: .fault,
               URL(fileURLWithPath: file).lastPathComponent, function, line, message)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        os_log("[WARNING] %{public}@ - %{public}@:%d %{public}@", log: osLog, type: .default,
               URL(fileURLWithPath: file).lastPathComponent, function, line, message)
    }
}
