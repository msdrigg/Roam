#if os(iOS)
import SwiftUI
import MediaPlayer
import Dispatch
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: String(describing: CustomVolumeSlider.self)
)



struct CustomVolumeSlider: UIViewRepresentable {
    @Binding var volume: Float
    @Binding var isTouched: Bool

    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
            slider.addTarget(context.coordinator, action: #selector(Coordinator.touchStarted(_:)), for: .touchDown)
            slider.addTarget(context.coordinator, action: #selector(Coordinator.touchEnded(_:)), for: .touchUpInside)
            slider.setThumbImage(UIImage(), for: .normal)
        }
        volumeView.transform = CGAffineTransform(rotationAngle: .pi / -2) // Rotate to vertical
        
        return volumeView
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        if let slider = view.subviews.first(where: { $0 is UISlider }) as? UISlider, !isTouched {
            slider.value = volume
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var customVolumeSlider: CustomVolumeSlider

        init(_ customVolumeSlider: CustomVolumeSlider) {
            self.customVolumeSlider = customVolumeSlider
        }

        @objc func valueChanged(_ sender: UISlider) {
            customVolumeSlider.volume = sender.value
        }

        @objc func touchStarted(_ sender: UISlider) {
            customVolumeSlider.isTouched = true
        }

        @objc func touchEnded(_ sender: UISlider) {
            customVolumeSlider.isTouched = false
        }
    }
}

let VOLUME_EPSILON: Float = 0.005

struct CustomVolumeSliderOverlay: View {
    private let showSlider: Bool = false
    private let audioSession: AVAudioSession = AVAudioSession.sharedInstance()

    @Binding var volume: Float
    var changeVolume: (VolumeEvent) -> Void
    
    @State private var isTouched: Bool = false
    @State var targetVolume: Float? = nil
    @State var inBackground: Bool = false
    
    @AppStorage(UserDefaultKeys.shouldControlVolumeWithHWButtons) private var controlVolumeWithHWButtons: Bool = true
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        VStack {
            Spacer()
            HStack {
                CustomVolumeSlider(volume: $volume, isTouched: $isTouched)
                    .frame(maxHeight: 150)
                Spacer()
            }
            Spacer()
            Spacer()
            Spacer()
            Spacer()
        }
        .offset(x: -800)
        .onChange(of: volume) { oldVolume, newVolume in
            if targetVolume == 0 || targetVolume == nil {
                logger.info("Changing empty target from \(String(describing: targetVolume)) to \(audioSession.outputVolume)")
                targetVolume = newVolume
            }
            
            if inBackground || !controlVolumeWithHWButtons {
                return
            }
            
            logger.info("Getting volume change \(volume) with target \(String(describing: targetVolume))")
            if let tv = targetVolume, volume != tv && !inBackground {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    logger.info("Setting volume to new value \(volume) with target \(tv)")
                    volume = tv
                }
            }
        }
        .task(id: inBackground || !controlVolumeWithHWButtons) {
            if inBackground || !controlVolumeWithHWButtons {
                return
            }
            if let stream = await VolumeListener(session: AVAudioSession.sharedInstance()).events {
                for await volumeEvent in stream {
                    let volume = volumeEvent.volume
                    if let tv = targetVolume {
                        if abs(volume - tv) > VOLUME_EPSILON {
                            if volume > tv {
                                changeVolume(VolumeEvent(direction: .Up, volume: volume))
                            } else {
                                changeVolume(VolumeEvent(direction: .Down, volume: volume))
                            }
                        }
                    }
                }
            } else {
                logger.error("Unable to get volume events stream")
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            inBackground = newPhase != .active
            logger.info("New scene phase \(String(describing: newPhase))")
            if oldPhase != .active && newPhase == .active {
                logger.info("Changing target from \(String(describing: targetVolume)) to \(audioSession.outputVolume)")
                targetVolume = audioSession.outputVolume
            }
        }
    }
}
#endif
