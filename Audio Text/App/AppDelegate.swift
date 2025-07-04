import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Setup background app refresh
        setupBackgroundAppRefresh()
        
        // Cleanup temp files on launch
        FileManagerService.shared.cleanupTempFiles()
        
        Logger.shared.info("App launched successfully")
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.shared.info("App entered background")
        
        // The recording manager will handle background recording automatically
        // through the BackgroundTaskService
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        Logger.shared.info("App entering foreground")
        
        // Refresh permission status
        AudioPermissionService.shared.objectWillChange.send()
        
        // Update file manager
        FileManagerService.shared.objectWillChange.send()
    }
    
    private func setupBackgroundAppRefresh() {
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    }
}
