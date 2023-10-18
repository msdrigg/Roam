# Better Remote

A Roku remote that puts users first

## TODO

- Need to add multicast capability to my app for real to get access to multicast networking
    - Currently waiting on response from apple in request
    - https://developer.apple.com/account 
    - https://developer.apple.com/forums/thread/663271 
- Non-private listening goals
    - Implement ecp-session with authentication procedure
    - Switch to ecp-session for all keypress activities
        - Implement consuming all tcp bytes and ignoring incoming
        - Create and maintain ecp session with 3 retries
            - Only retry after 3 times when user presses another button
        - Can send keys with "request":"key-press"
        - Can launch apps with "request":"launch"
        - All requests look like: {"param-mode":"async","param-channel-id":"61322","request":"launch","request-id":"51"}
- Next logical steps for private listening
    - 1. Implement starting private session (and stopping it) with command
        - Ensure that this works and datagrams start coming through
    - 2. Setup RTCP handshake
        - Ensure that rtcp messages are valid confirmation is received (logging if not)
        - Ensure that at least at the beginning, rtp messages are coming through (Wireshark)
    - 3. Setup RTCP controller to send continual empty receiver report packets
    - 4. Setup  RTP listener to decode packets
        - Ensure that packets are coming through evenly-spaced and are getting decoded in-order and that RTP timestamp matches expectations
    - 5. Setup RTP listener to continuously receive and decode packets
        - Ensure that packet decoding is valid and doesn’t throw errors on decoding packet to Opus and Opus to PCM buffer
    - 6. Setup AudioPlayerNode + AudioEngine + AVAudioSession to play music
        - Embed a .wav file and then play that on the player node and ensure audio comes out when clicking private listening 
    - 6. Stop playing wave file and instead play audio pcm buffers naively as they come out (in order, but no fanciness with any scheduling or anything)
        - Ensure audio can come out of speakers and works (probably terrible sounding)
    - 7. Start enqueuing buffers using estimated start time intervals
- Each packet is about 10 MS
    - Buffer 3x/4 ms of packets from time-of-arrival to time-of-decoding
    - Decode packets into frames as they come off the line
    - Decoded packets get popped off and enter the audio queue and played frame-by-frame matching 1 packet each 10  ms
    - Decoded packets are assumed to be 48000 Hz, and can get times from https://developer.apple.com/documentation/avfaudio/avaudiotime/1387972-init 
    - Checks:
        - Each packet contains 480 frames? (Maybe 960 if including stereo frames?)
        - Each packet is either 480 frames, 960, or …
    - Sync Time TRY 1
        - Start player with Player.play, engine.start, sharedsession.start, …
        - Get host time with Date.now
        - Get player time with AVAudioPlayerNode.lastRenderTime
        - Now we can map from firstPacketTime -> nodeTime
        - … Receive first packet …
        - Get firstPacketNodeTime as the receivedAt time for the packet mapped to node time space
        - Get the rtpOffsetNode0 by doing firstPacketNodeTime - (packetRTPTime * 480) + vdlySyncDelay - FIXED_TRANSIT_TIME_GUESS
        - For each future packet, calculate the schedule AVTime by rtpOffsetNode0  + (packetRTPTime * 480)
    - Schedule packets with scheduleAt(buffer: buffer, at: FramePosition((48000 * rtpTs / 1000)))
    - Ensure playback starts on-the-dot after the x seconds buffer
    - If this doesn’t work, we could try 
        - timeOffset = rtpTs / 1000 (down to the ms basically)
        - averageHostStartTimeExpectation (initial calculation) = Date.now - packetRTPOffset
        - averageHostStartTimeExpectation (update) += 1/16 * ((Date.now - packetRTPOffset) - averageHostStartTimeExpectation)
        - scheduleAt(buffer: buffer, at: FramePositionHostTime(averageHostStartTimeExpectation + startOffset + vdlySyncDelay - FIXED_TRANSIT_TIME_GUESS))
    - So once we have a packet that needs to be run at audioTime and queued at hostTime, store a looping engine (with a start, stop functionality) to check every 10 ms if packets can be queued and queue them if so
    - Need to also look at loss concealment with Opus.decode(nullPtr, count: 0) if requesting packet that doesn’t exist
- https://stackoverflow.com/questions/41738644/how-to-receive-rtp-packets-which-are-streaming-from-rtp-url-in-ios-device-e-g
- https://github.com/alta/swift-rtp
- https://github.com/Esri/SwiftRTP
- https://github.com/ThiemJson/Audio-RTP/tree/test_rtp_read/testplayaudio
- https://github.com/dnadoba/RTP/blob/master/RTP%20macOS/RTPH264Reciever.swift
- https://github.com/runz0rd/RPListening/blob/main/RPListening/src/main/java/wseemann/media/rplistening/RPListening.java
- https://github.com/alin23/roku-audio-receiver/blob/master/roku.py


