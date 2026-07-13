#if !os(watchOS)
import SwiftUI
import OSLog

enum TextEditStatus: Equatable, Hashable {
    case editing(TextEditState)
    case off

    var isActive: Bool {
        return switch self {
        case .editing: true
        case .off: false
        }
    }

    var text: String? {
        return switch self {
        case let .editing(state): state.text ?? ""
        case .off: nil
        }
    }

    var texteditId: String? {
        return switch self {
        case let .editing(state):
            if state.texteditId == "none" || state.texteditId == "" {
                nil
            } else {
                state.texteditId
            }
        case .off: nil
        }
    }
}

@MainActor @Observable
final class ECPMonitor {
    var status: ECPWebsocketState = .disconnected(.distantPast)
    var textEditStatus: TextEditStatus = .off
    var ecpClient: ECPWebsocketClient?

    // Incremented every time the monitor switches clients. Callbacks and the
    // reconnect loop capture the value they were created under and become
    // no-ops once it moves on, so a retired client's late state updates can
    // never stomp the current client's state.
    private var generation = 0
    private var reconnectTask: Task<Void, Never>?

    func setDevice(_ device: Device?) {
        // Re-selecting the device we're already pointed at (pager pages
        // re-appearing, scene re-activation) must not tear down the session —
        // if it's unhealthy, the reconnect loop is already reviving it.
        if let device, let current = ecpClient, current.location.absoluteString == device.location {
            return
        }

        generation += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        let oldEcpClient = self.ecpClient
        self.ecpClient = nil

        guard let device, let url = URL(string: device.location) else {
            if device != nil {
                Log.connection.error("Could not parse URL for selected device \(device?.location ?? "nil", privacy: .public)")
            }
            status = .disconnected(.now)
            textEditStatus = .off
            Task {
                await oldEcpClient?.shutdown()
            }
            return
        }
        let generation = self.generation
        let ecpClient = ECPWebsocketClient(
            location: url,
            macs: device.macs(),
            websocketStateUpdated: {[weak self] state in
                Log.connection.notice("Getting new ws state \(state.debugDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self?.handleStateChange(state, generation: generation)
                }
            },
            notificationHandler: {[weak self] notification in
                DispatchQueue.main.async {
                    self?.handleNotification(notification, generation: generation)
                }
            }
        )
        self.ecpClient = ecpClient
        self.status = .connecting(.now)
        self.textEditStatus = .off
        // One serialized task so the old client is always retired before the
        // new one starts. If a later `setDevice` races in, it can only shut
        // this client down (its `start()` then refuses to run) — it can never
        // interleave into a resurrected orphan connection.
        Task {
            await oldEcpClient?.shutdown()
            await ecpClient.start()
            do {
                try await ecpClient.requestEventsNotify()
            } catch {
                Log.connection.error("Error requesting events notify \(error, privacy: .public)")
            }
        }
    }

    private func handleStateChange(_ state: ECPWebsocketState, generation: Int) {
        guard generation == self.generation else {
            Log.connection.notice("Ignoring ws state \(state.debugDescription, privacy: .public) from retired client")
            return
        }
        status = state
        switch state {
        case .connected:
            reconnectTask?.cancel()
            reconnectTask = nil
        case .disconnected:
            scheduleReconnect(generation: generation)
        case .connecting:
            break
        }
    }

    private func handleNotification(_ notification: ECPNotification, generation: Int) {
        guard generation == self.generation else { return }
        switch notification {
        case .texteditChanged(let state), .texteditOpened(let state):
            textEditStatus = .editing(state)
        case .texteditClosed:
            textEditStatus = .off
        }
    }

    /// The session must never stay dead waiting for user input: whenever the
    /// current client reports disconnected, retry `start()` on an exponential
    /// backoff until it connects or the monitor moves to another device.
    private func scheduleReconnect(generation: Int) {
        guard reconnectTask == nil else { return }
        Log.connection.notice("Scheduling ECP reconnect loop")
        reconnectTask = Task { [weak self] in
            for await _ in exponentialBackoff(min: 2, max: 60) {
                guard let self, !Task.isCancelled, generation == self.generation,
                      let client = self.ecpClient else { return }
                if case .connected = self.status { return }
                Log.connection.notice("Attempting ECP reconnect after backoff")
                await client.start()
            }
        }
    }
}
#endif
