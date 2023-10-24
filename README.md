# Roam

A Roku remote that puts users first

## TODO

- Prepare for AppStore
    - Get AppIcon - Waiting on Fiverr
    - Get AppIcon from Maggie?
    - Get screenshots from multiple devices, widgets
    - Get presentation images from Fiverr (or procreate?)
- Bugs
    - When volume zero, volume down press doesn't work to change roku volume
        - Need an approach like this https://developer.apple.com/forums/thread/649183 to sync phone audio with device audio
    - Sometimes I get a big delay with sent keys and then they all queue up and blast through after they aren't relevant anymore
        - Either use ECPSession for button presses
- Add watch-os support
    - TabView with 
        - DPadController
        - MediaController
        - App Links
    - StackView for
        - Settings (https://developer.apple.com/forums/thread/680053)
    - Add small circular widgets configurable for each button
- Add app launch widget
    - List of recently launched apps
    - Need to record when a device gets launched within swift data
- Next logical steps for private listening
    - Ensure that the `scheduleBuffer(buffer, at: scheduleTime)` is actually scheduling using callbacks and print statements on iOS
        - Maybe look at ioBufferDuration?
        - Maybe look at sampleTime differences in input and output nodes?
        - Use knowledge to resolve this scheduling on iOS
    - Switch to self-controlled playback latency
        - Setup VDLY to a big number (maybe even something huge like 2.5 seconds)
        - Setup the buffer to the standard 0.4 seconds
        - Setup the baseAudioTransit to the standard 0.1 seconds
        - Setup the audioDeviceLatency to the shardedSession.outputLatency
        - Calculate when to schedule the actual packets coming off the line as max(VDLY - buffer - baseAudioTransit - audioDeviceLatency, 0)
    - Need to calculate audio latency on macOS
        - Look at CoreAudio kAudioDevicePropertyLatency, kAudioStreamPropertyLatency, kAudioDevicePropertySafetyOffset, kAudioDevicePropertyBufferFrameSize
    - Look at https://github.com/jnpdx/AudioEngineLoopbackLatencyTest/issues/1

```swift
// Output: 
// kAudioDevicePropertySafetyOffset:    93
// kAudioDevicePropertyLatency:          399
// kAudioStreamPropertyLatency:         0
// kAudioDevicePropertyBufferFrameSize: 512

// Input:
// kAudioDevicePropertySafetyOffset:     66
// kAudioDevicePropertyLatency:            0
// kAudioStreamPropertyLatency:         0
// kAudioDevicePropertyBufferFrameSize:  512
```

- Continued...
    - Handle audio route changes on macOS
        - 
    - Make sure to handle sequence number wrapping
    - Make video delay configurable per device

