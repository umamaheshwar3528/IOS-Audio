import Foundation

extension Notification.Name {
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
    static let audioLevelUpdated = Notification.Name("audioLevelUpdated")
    static let recordingSessionCompleted = Notification.Name("recordingSessionCompleted")
    static let audioPermissionChanged = Notification.Name("audioPermissionChanged")
}
