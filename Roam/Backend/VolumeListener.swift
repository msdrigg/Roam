#if os(iOS)
import Foundation
import AVFoundation
import os

enum VolumeClicked: String, CaseIterable {
    case Up
    case Down
}

struct VolumeEvent {
    let direction: VolumeClicked
    let volume: Float
}

actor VolumeListener {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: VolumeListener.self)
    )
    
    var volumeObservation: NSKeyValueObservation? = nil
    var lastVolume: Float = 0.5
    var volumeChangeHandler: ((VolumeClicked, Float) -> Void)? = nil
    let session: AVAudioSession
    
    init(session: AVAudioSession) {
        self.session = session
    }
    
    func startListening() throws {
        do {
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            lastVolume = session.outputVolume
        } catch {
            Self.logger.error("Cannot activate audiosession to listen to volume: \(error)")
            throw error
        }
        Self.logger.info("Starting volume observations")
        
        volumeObservation = session.observe(\.outputVolume, options: [.new], changeHandler: { [weak self] (session, value) in
            guard let self = self else { return }
            
            Task {
                if !Task.isCancelled {
                    await self.newVolumeObserved(session.outputVolume)
                }
            }
        })
    }
    
    func newVolumeObserved(_ newVolume: Float) {
        if newVolume > self.lastVolume {
            self.volumeChangeHandler?(.Up, newVolume)
        } else if newVolume < self.lastVolume {
            self.volumeChangeHandler?(.Down, newVolume)
        }
        
        self.lastVolume = newVolume
    }
    
    func stopListening() {
        Self.logger.info("Stoping volume observations")
        volumeObservation?.invalidate()
        volumeObservation = nil
    }
    
    var events: AsyncStream<VolumeEvent>? {
        return AsyncStream { continuation in
            do {
                try startListening()
                self.volumeChangeHandler = { direction, volume in
                    continuation.yield(VolumeEvent(direction: direction, volume: volume))
                }
                continuation.onTermination = { @Sendable _ in
                    Task {
                        await self.stopListening()
                    }
                }
            } catch {
                
            }
        }
    }
}


class LatencyListener {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: LatencyListener.self)
    )
    
    var latencyObservation: NSKeyValueObservation? = nil
    var latencyChangeHandler: ((Double) -> Void)? = nil
    let session: AVAudioSession
    
    init(session: AVAudioSession) {
        self.session = session
    }
    
    @objc func handleRouteChange(notification: Notification) {
        self.newLatencyObserved(session.outputLatency)
    }
    
    func startListening() throws {
        Self.logger.info("Starting Latency observations")
        // Get the default notification center instance.
        NotificationCenter.default.addObserver(
           self,
           selector: #selector(handleRouteChange),
           name: AVAudioSession.routeChangeNotification,
           object: nil
        )
    }
    
    func newLatencyObserved(_ newLatency: Double) {
        self.latencyChangeHandler?(newLatency)
    }
    
    func stopListening() {
        Self.logger.info("Stoping Latency observations")
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    var events: AsyncStream<Double>? {
        return AsyncStream { continuation in
            do {
                try startListening()
                self.latencyChangeHandler = { latency in
                    continuation.yield(latency)
                }
                continuation.onTermination = { @Sendable _ in
                    self.stopListening()
                }
            } catch {
                
            }
        }
    }
}
#endif
