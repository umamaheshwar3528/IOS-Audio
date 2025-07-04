import Foundation
import Network
import Combine

class NetworkMonitorService: ObservableObject {
    static let shared = NetworkMonitorService()
    
    @Published var isConnected = false
    @Published var connectionType: ConnectionType = .unknown
    @Published var isExpensive = false
    @Published var isConstrained = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.monitor")
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case other
        case unknown
        
        var displayName: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "Cellular"
            case .ethernet: return "Ethernet"
            case .other: return "Other"
            case .unknown: return "Unknown"
            }
        }
    }
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path)
            }
        }
        
        monitor.start(queue: queue)
        Logger.shared.info("Network monitoring started")
    }
    
    private func stopMonitoring() {
        monitor.cancel()
        Logger.shared.info("Network monitoring stopped")
    }
    
    private func updateNetworkStatus(_ path: NWPath) {
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        connectionType = determineConnectionType(path)
        
        Logger.shared.debug("Network status updated - Connected: \(isConnected), Type: \(connectionType.displayName)")
        
        // Post network change notification
        NotificationCenter.default.post(
            name: .init("networkStatusChanged"),
            object: NetworkStatus(
                isConnected: isConnected,
                type: connectionType,
                isExpensive: isExpensive,
                isConstrained: isConstrained
            )
        )
    }
    
    private func determineConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.other) {
            return .other
        } else {
            return .unknown
        }
    }
    
    // MARK: - Public Interface
    
    func isOptimalForTranscription() -> Bool {
        return isConnected && !isConstrained && (connectionType == .wifi || !isExpensive)
    }
    
    func shouldUseCloudTranscription() -> Bool {
        return isConnected && (connectionType == .wifi || SettingsService.shared.settings.allowCellularTranscription)
    }
    
    func getNetworkQualityScore() -> Float {
        guard isConnected else { return 0.0 }
        
        var score: Float = 1.0
        
        // Penalize expensive connections
        if isExpensive {
            score *= 0.7
        }
        
        // Penalize constrained connections
        if isConstrained {
            score *= 0.5
        }
        
        // Adjust for connection type
        switch connectionType {
        case .wifi:
            break // No adjustment
        case .ethernet:
            score *= 1.1 // Slightly prefer ethernet
        case .cellular:
            score *= 0.8
        case .other, .unknown:
            score *= 0.6
        }
        
        return min(score, 1.0)
    }
}

struct NetworkStatus {
    let isConnected: Bool
    let type: NetworkMonitorService.ConnectionType
    let isExpensive: Bool
    let isConstrained: Bool
}
