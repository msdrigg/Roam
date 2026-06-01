---
hide_table_of_contents: true
---

# Roam Roadmap

## Coming Soon

-   Add long-press options to keys
    -   Long-press right arrow to ff
    -   Long-press left arrow to rr
    -   Long-press mute to long-mute
        -   Make the +30 configurable to 30, 15, 60 second mute options
        -   Show banner with +30 sec, x to cancel, background linear progress indicator
            -   Show underneath the main button panel so it's close to mute
        -   Cancels when muting again (and also does api call)
-   Provide an optional Minimalist view on iOS that replicates siri remote's view closely
    -   https://support.apple.com/guide/tv/use-ios-or-ipados-control-center-atvb701cadc1/tvos
    -   Support visionos gestures as well...
    -   Make standard buttons larger

## General Future Ideas

-   Make custom menu bar icon
-   How to do voice-to-text or general voice commands?
    -   See /docs/notes/voice-search


## Improve user messaging around info/status/capabilities management

-   Look at copying some of the descriptive features of other Roku remotes
    -   Explanations for local network permissions, etc…
    -   See Desktop -> RokuScanning -> 3rd party comparison
    -   Bottom sheet popup when you click on "Local network permissions not granted"
        -   Explain how to fix it
        -   Dismiss it from there
    -   WatchOS popup explaining when limited mode is on for devices (query /device/apps and check if it returns 4xx error)
        -   Whole entry flow where you click "Try again" after entering or "Cancel"
    -   Embed links to roam.msd3.io for concerns (instead of just listing them)
        -   Change info bubbles to disclosure buttons (drop down below) and from that disclosure, say "Click here to read more" to open roam
    -   On macOS (and maybe others), +add a device manually doesn't take you into that device view
    -   Remove info from device detail view
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
        -   Link https://roam.msd3.io/manually-add-tv.md and https://support.roku.com/article/115001480188 for more troubleshooting or chat
