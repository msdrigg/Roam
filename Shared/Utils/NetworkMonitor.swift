import Network
import OSLog
import SwiftUI

class NetworkMonitor: ObservableObject {
    @Published var networkConnection: NetworkType = .local
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: NetworkMonitor.self)
    )

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi), !path.isExpensive {
                        self?.networkConnection = .local
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        self?.networkConnection = .local
                    } else if path.usesInterfaceType(.cellular) {
                        self?.networkConnection = .remote
                    } else {
                        self?.networkConnection = .other
                    }
                } else {
                    self?.networkConnection = .none
                }
                Self.logger
                    .info(
                        "Getting new network \(String(describing: path)). Updating self type to \(String(describing: self?.networkConnection))"
                    )
            }
        }
    }

    func startMonitoring() {
        Self.logger.info("Starting to monitor network path updates for display")
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    enum NetworkType {
        case local
        case remote
        case other
        case none
    }
}
