import Network
import Combine

/// Lightweight WiFi/cellular detection. Zero polling — NWPathMonitor fires only on network changes.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published private(set) var isWiFi = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isWiFi = !path.usesInterfaceType(.cellular) }
        }
        monitor.start(queue: DispatchQueue(label: "net", qos: .utility))
    }

    deinit { monitor.cancel() }
}
