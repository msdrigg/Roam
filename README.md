# Roam

A Roku remote that puts users first

## TODO

- Bugs
    - When volume zero, volume down press doesn't work to change roku volume
        - Need an approach like this https://developer.apple.com/forums/thread/649183 to sync phone audio with device audio
    - Sometimes I get a big delay with sent keys and then they all queue up and blast through after they aren't relevant anymore
        - Either use ECPSession for button presses
- Add watch-os support
    - Add 3 sliding views
        - Main Controller (like small widget)
        - Button Grid (like small widget)
        - App Links (scrollable list sorted by most recently opened)
    - Add small circular widgets configurable for each button
- Add app launch widget
    - List of recently launched apps
- Next logical steps for private listening
    - Make video delay configurable per device
    - Update the xdly when connected device changes
        - Use actual scheduling on iphone ....
    - Make sure to handle sequence number wrapping

