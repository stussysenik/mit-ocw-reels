import Network
import Combine

/// Lightweight WiFi/cellular detection. Zero polling — NWPathMonitor fires only on network changes.
///
/// `connectionQuality` drives adaptive video quality:
/// - `.excellent` (WiFi) → hd1080
/// - `.good` (fast cellular) → medium (360p)
/// - `.poor` (constrained/Low Data Mode) → small (240p)
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    enum ConnectionQuality { case excellent, good, poor }

    @Published private(set) var isWiFi = true
    @Published private(set) var connectionQuality: ConnectionQuality = .excellent
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isWiFi = !path.usesInterfaceType(.cellular)
                if !path.isExpensive {
                    self.connectionQuality = .excellent
                } else if path.isConstrained {
                    self.connectionQuality = .poor
                } else {
                    self.connectionQuality = .good
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "net", qos: .utility))
    }

    deinit { monitor.cancel() }
}
