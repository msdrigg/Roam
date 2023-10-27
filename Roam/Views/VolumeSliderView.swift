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
                    .opacity(showSlider ? 1 : 0)
                    .frame(maxHeight: 150)
                Spacer()
            }
            Spacer()
            Spacer()
            Spacer()
            Spacer()
        }
        .transition(.move(edge: .leading))
        .onChange(of: volume) { oldVolume, newVolume in
            if targetVolume == 0 || targetVolume == nil {
                targetVolume = newVolume
            }
            
            if let tv = targetVolume, volume != tv && !inBackground {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    volume = tv
                }
            }
        }
        .onChange(of: scenePhase) { _oldPhase, newPhase in
            targetVolume = audioSession.outputVolume
            inBackground = newPhase != .active
        }
        .task(id: inBackground || !controlVolumeWithHWButtons) {
            if inBackground || !controlVolumeWithHWButtons {
                return
            }
            if let stream = await VolumeListener(session: AVAudioSession.sharedInstance()).events {
                for await volumeEvent in stream {
                    if volumeEvent.volume != targetVolume {
                        changeVolume(volumeEvent)
                    }
                }
            } else {
                logger.error("Unable to get volume events stream")
            }
        }
    }
}

#endif
