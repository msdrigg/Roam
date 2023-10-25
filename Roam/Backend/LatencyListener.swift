import Foundation
import AVFoundation
import os

#if os(iOS)
class LatencyListener {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: LatencyListener.self)
    )
    
    var latencyChangeHandler: (() -> Void)? = nil
    
    @objc func handleRouteChange(notification: Notification) {
        self.latencyChangeHandler?()
    }
    
    enum Event: String {
        case LatencyChanged
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
    
    func stopListening() {
        Self.logger.info("Stoping Latency observations")
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    var events: AsyncStream<Event>? {
        return AsyncStream { continuation in
            do {
                try startListening()
                self.latencyChangeHandler = {
                    continuation.yield(Event.LatencyChanged)
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

#if os(macOS)
import AppKit
import CoreAudio

class LatencyListener {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: LatencyListener.self)
    )
    
    var latencyChangeHandler: (() -> Void)?
    
    var audioDeviceChangeListener: AudioObjectPropertyListenerBlock?
    
    enum Event: String {
        case LatencyChanged
    }
    
    func startListening() {
        Self.logger.info("Starting Latency observations")
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        audioDeviceChangeListener = { _, _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { // 1200ms delay
                DispatchQueue.main.async {
                    self.latencyChangeHandler?()
                }
            }
        }
        
        let err = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, audioDeviceChangeListener!)
        
        if err != kAudioHardwareNoError {
            Self.logger.error("Error adding audio property listener: \(err)")
        }
    }
    
    func stopListening() {
        Self.logger.info("Stopping Latency observations")
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if let listener = audioDeviceChangeListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
        }
    }
    
    var events: AsyncStream<Event>? {
        return AsyncStream { continuation in
            startListening()
            latencyChangeHandler = {
                continuation.yield(Event.LatencyChanged)
            }
            continuation.onTermination = { @Sendable _ in
                self.stopListening()
            }
        }
    }
}
#endif

