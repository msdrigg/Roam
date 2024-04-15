---
hide_table_of_contents: true
---

# Upcoming Roam Updates

-   Update Info/status management to better handle volatile state
    -   On disconnect, select, button click, move to foreground, app opened -> Restart reconnect loop if disconnected
    -   Reconnect loop is to exponentially backoff retrying failing connections (0.5s, double, 10s backoff)
    -   Reconnect loop = Backing off Exponentially attempt to reconnect to reconnect ECP
        -   Reconnect ECP first
        -   Listen to notify second
            -   Handle +power-mode-changed,+textedit-opened,+textedit-changed,+textedit-closed,+device-name-changed
            -   Make sure we can handle each of these requests and their format…
        -   Refresh device state third
        -   Refresh query-textedit-state fourth
            -   Update textedit state
        -   Refresh device icons fifth
    -   On all changes after reconnecting (through notify or anything)
        -   Update Device (stored) and DeviceState (voilatile)
    -   After reconnecting/disconnecting, update online status in remote view
-   More Apple Integrations
    -   App Clip
-   Update user messaging when errors may occur
    -   When clicking on a disabled button, open popover to show why it’s disabled
        -   Show a info indicator on the button to indicate that information can be received when it’s clicked?
        -   Headphones mode disabled -> because device doesn’t support headphones mode to this app
        -   Volume control disabled -> because the audio is outputting over HDMI which does not support volume controls?
    -   When connected to the device, always disable the network warnings
    -   When trying to connect to the device, or trying to power on the device, show spinning information icon instead of gray dot
    -   When powering on the device and succeeding, show an animation on transition from gray -> spinning -> green
    -   When powering on the device with WOL and not connecting after 5 seconds, or when powering on the device and immediately failing, show a warning message underneath the wifi one
        -   “We weren’t able to wake your Roku” (Find out more) (Don’t show again for this device), (X)
        -   Find out more shows some reasons why
            -   You aren’t connected to the same network (Show last device network name. Ask if the user is connected to this network)
            -   Your device is in deep sleep (wasn’t powered down recently) and can’t be woken up
                -   Your device doesn’t support WWOL and is connected to wifi
                -   Your device doesn’t support WWOL or WOL
            -   Your network isn’t setup in a way to allow us to send wakeup commands to the device
    -   When actively scanning for devices and no new ones are found show a warning message underneath the device list
        -   “We weren’t able to wake your Roku” (Find out why), (X)
        -   Find out more shows a popup with some reasons why this may be happening
            -   Make sure your device is powered on and connected to the same wifi network as your app. If this still doesn't work, try adding the device manually.
            -   Link https://roam.msd3.io/manually-add-tv.md and https://support.roku.com/article/115001480188 for more troubleshooting
-   Add badge for supportsWakeOnWLAN and supportsMute
-   Update keyboard handling to support ecp-textedit (All but macOS)
    -   Show keyboard when textedit is opened
    -   Hide keyboard when textedit closed
    -   If ecp-textedit is supported, allow selecting, deleting text and moving cursor. Just re-send text each time it changes if this is supported.
-   Add live feedback option for users to chat with me directly through discord's API
    -   Clients create a thread-per-client and interact with the discord API via a cloudflare workers proxy
    -   User devices access TS API hosted on cloudflare workers (discord.js)
        -   Definitely handles thread create, thread pull, message create, and message listening
            -   Message listening is done when users connect to the websocket JS API and listen
            -   Message sending/pulling/creating is done using discords js api
                -   Pulling is done AFTER=last_msg_id
                -   Listening is done on messageCreate and filtered by channel id
                -   Roam uses the /messages API most of the time and ONLY uses websockets when client is actively opening the chat app
            -   Sends APNS notification to the device APNS key associated with the device
                -   Wake the device up and display notification if not in foreground
                -   Display bolded "dev chat" message in the top center if there is an "unread message" tracked by "last message"
    -   Example chat swiftui apps
        -   https://github.com/mrcflorian/swiftUI-tutorials/tree/master/Tutorials/ChatViewTutorial/ChatViewTutorial
        -   https://github.com/cometchat-pro-tutorials/swift-ui-chat

Keyboard ECP Session Commands (notes)

```
- {"request":"request-events","request-id":"4","param-events":"+language-changed,+language-changing,+media-player-state-changed,+plugin-ui-run,+plugin-ui-run-script,+plugin-ui-exit,+screensaver-run,+screensaver-exit,+plugins-changed,+sync-completed,+power-mode-changed,+volume-changed,+tvinput-ui-run,+tvinput-ui-exit,+tv-channel-changed,+textedit-opened,+textedit-changed,+textedit-closed,+textedit-closed,+ecs-microphone-start,+ecs-microphone-stop,+device-name-changed,+device-location-changed,+audio-setting-changed,+audio-settings-invalidated"}
    - {"notify":"textedit-opened","param-masked":"false","param-max-length":"75","param-selection-end":"0","param-selection-start":"0","param-text":"","param-textedit-id":"12","param-textedit-type":"full","timestamp":"608939.003"}
- {"request":"query-textedit-state","request-id":"10"}
    - {"content-data":"eyJ0ZXh0ZWRpdC1zdGF0ZSI6eyJ0ZXh0ZWRpdC1pZCI6Im5vbmUifX0=","content-type":"application/json; charset=\"utf-8\"","response":"query-textedit-state","response-id":"10","status":"200","status-msg":"OK"}
- {"param-text":"h","param-textedit-id":"12","request":"set-textedit-text","request-id":"20"}
    - {"response":"set-textedit-text","response-id":"29","status":"200","status-msg":"OK"}
```