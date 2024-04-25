import Foundation
import os.log

#if os(iOS) || os(tvOS) || os(visionOS)
    import AVFoundation

    class LatencyListener {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: String(describing: LatencyListener.self)
        )

        var latencyChangeHandler: ((Double) -> Void)?
        let audioSession = AVAudioSession.sharedInstance()

        @objc func handleRouteChange(notification _: Notification) {
            latencyChangeHandler?(audioSession.outputLatency)
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

        var events: AsyncStream<Double>? {
            AsyncStream { continuation in
                do {
                    try startListening()
                    self.latencyChangeHandler = { newValue in
                        continuation.yield(newValue)
                    }
                    continuation.onTermination = { @Sendable _ in
                        self.stopListening()
                    }
                } catch {}
            }
        }
    }
#endif

#if os(macOS)
    import CoreAudio

    class LatencyListener {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: String(describing: LatencyListener.self)
        )

        var latencyChangeHandler: ((Double) -> Void)?
        var audioDeviceChangeListener: AudioObjectPropertyListenerBlock?

        var defaultDeviceAddress: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        }

        func getDeviceLatency(deviceID: AudioDeviceID) -> Double? {
            var latency: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyLatency,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propSize, &latency)
            if err != kAudioHardwareNoError {
                Self.logger.error("Failed to get latency for device \(deviceID), error: \(err)")
                return nil
            }

            var sampleRate: Float64 = 0
            var size = UInt32(MemoryLayout.size(ofValue: sampleRate))
            var sampleRateAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            let sampleRateErr = AudioObjectGetPropertyData(deviceID, &sampleRateAddress, 0, nil, &size, &sampleRate)
            if sampleRateErr != kAudioHardwareNoError {
                Self.logger
                    .error("Failed to get sample rate for device \(deviceID), error: \(err). Defaulting to 48000")
                sampleRate = 48000
            }

            return Double(latency) / sampleRate
        }

        func startListening() {
            Self.logger.info("Starting Latency observations")

            var defaultDeviceAddress = defaultDeviceAddress

            audioDeviceChangeListener = { _, _ in
                DispatchQueue.main.async {
                    var size = UInt32(MemoryLayout<AudioDeviceID>.size)

                    // Listener for latency changes on the default output device
                    var listeningDeviceId: AudioDeviceID = 0
                    AudioObjectGetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &defaultDeviceAddress,
                        0,
                        nil,
                        &size,
                        &listeningDeviceId
                    )

                    DispatchQueue.main.async {
                        self.latencyChangeHandler?(self.getDeviceLatency(deviceID: listeningDeviceId) ?? 0)
                    }
                }
            }

            let err = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultDeviceAddress,
                nil,
                audioDeviceChangeListener!
            )

            if err != kAudioHardwareNoError {
                Self.logger.error("Error adding audio property listener for default output device: \(err)")
            }
        }

        func stopListening() {
            Self.logger.info("Stopping Latency observations")

            var defaultDeviceAddress = defaultDeviceAddress

            DispatchQueue.main.async {
                if let listener = self.audioDeviceChangeListener {
                    AudioObjectRemovePropertyListenerBlock(
                        AudioObjectID(kAudioObjectSystemObject),
                        &defaultDeviceAddress,
                        nil,
                        listener
                    )
                }
            }
        }

        var events: AsyncStream<Double>? {
            AsyncStream { continuation in
                startListening()
                latencyChangeHandler = { newValue in
                    continuation.yield(newValue)
                }
                continuation.onTermination = { @Sendable _ in
                    self.stopListening()
                }
            }
        }
    }
#endif
