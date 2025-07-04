import AVFoundation
import Foundation
import Combine

enum AudioPermissionStatus {
    /// The user has not yet been asked for recording permission.
    case notDetermined
    /// The user has explicitly denied recording permission.
    case denied
    /// The user has granted recording permission.
    case granted
    
    /// Query the system’s current AVAudioSession permission.
    static var current: AudioPermissionStatus {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined: return .notDetermined
        case .denied:       return .denied
        case .granted:      return .granted
        @unknown default:   return .notDetermined
        }
    }
    
    /// Whether we already have permission to record.
    var isGranted: Bool {
        self == .granted
    }
    
    /// Whether we should go ahead and call `requestRecordPermission(_:)`.
    var needsRequest: Bool {
        self == .notDetermined
    }
}

class AudioPermissionService: ObservableObject {
    static let shared = AudioPermissionService()
    
    @Published var permissionStatus: AudioPermissionStatus = .notDetermined
    
    private init() {
        updatePermissionStatus()
    }
    
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.updatePermissionStatus()
                    NotificationCenter.default.post(name: .audioPermissionChanged, object: granted)
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    private func updatePermissionStatus() {
        permissionStatus = AudioPermissionStatus.current
    }
    
    func checkAndRequestPermissionIfNeeded() async -> Bool {
        updatePermissionStatus()
        
        if permissionStatus.isGranted {
            return true
        }
        
        if permissionStatus.needsRequest {
            return await requestPermission()
        }
        
        return false
    }
}
