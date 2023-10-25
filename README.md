# Roam

A Roku remote that puts users first

## TODO

- Prepare for AppStore
    - Get AppIcon from Maggie if she wants to
    - Get screenshots from multiple devices, widgets
    - Get presentation images from Fiverr (or procreate?)
- Add watch-os support
    - TabView with 
        - DPadController
        - MediaController
        - App Links
        - Vertical page style + navigation headers
        - Scrollable app links last
        - Tool bar buttons on top and bottom views
        - Maybe gradient containerbackground?? (maybe for ios too)
    - StackView for
        - Settings (https://developer.apple.com/forums/thread/680053)
    - Add small circular widgets configurable for each button
- Bugs
    - When volume zero, volume down press doesn't work to change roku volume
        - Need an approach like this https://developer.apple.com/forums/thread/649183 to sync phone audio with device audio
    - Sometimes I get a big delay with sent keys and then they all queue up and blast through after they aren't relevant anymore
        - Either use ECPSession for button presses
    - Make sure to handle sequence number wrapping in RTP stream

## License

&copy; 2023 Scott Driggers.

This project is licensed under either of

- [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0) ([`LICENSE-APACHE`](LICENSE-APACHE))
- [MIT license](https://opensource.org/licenses/MIT) ([`LICENSE-MIT`](LICENSE-MIT))

at your option.

The [SPDX](https://spdx.dev) license identifier for this project is `MIT OR Apache-2.0`.
