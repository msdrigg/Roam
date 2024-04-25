import Foundation
import SwiftUI

public enum RemoteButton: String, CaseIterable, Sendable, Encodable, Hashable {
    case up = "Up"
    case left = "Left"
    case right = "Right"
    case down = "Down"

    case select = "Select"
    case home = "Home"
    case back = "Back"
    case powerOff = "PowerOff"
    case powerOn = "PowerOn"
    case power = "Power"

    case mute = "VolumeMute"
    case volumeUp = "VolumeUp"
    case volumeDown = "VolumeDown"

    case options = "Info"
    case instantReplay = "InstantReplay"
    case rewind = "Rev"
    case fastForward = "Fwd"
    case playPause = "Play"

    case findRemote = "FindRemote"
    case backspace = "Backspace"
    case search = "Search"
    case enter = "Enter"

    case channelUp = "ChannelUp"
    case channelDown = "ChannelDown"

    case inputTuner = "InputTuner"
    case inputHDMI1 = "InputHDMI1"
    case inputHDMI2 = "InputHDMI2"
    case inputHDMI3 = "InputHDMI3"
    case inputHDMI4 = "InputHDMI4"
    case inputAV1 = "InputAV1"
    case headphonesMode = "Headphones Mode"

    public static var typeDisplayName: String = "Button"

    public static var caseDisplayRepresentations: [RemoteButton: String] = [
        .up: "Up",
        .left: "Left",
        .right: "Right",
        .down: "Down",
        .select: "Ok",
        .home: "Home",
        .back: "Back",
        .power: "Power On/Off",
        .powerOn: "Power On",
        .powerOff: "Power Off",
        .mute: "Mute/Unmute",
        .volumeUp: "Volume Up",
        .volumeDown: "Volume Down",
        .options: "Options",
        .instantReplay: "Instant Replay",
        .rewind: "Rewind",
        .fastForward: "Fast Forward",
        .playPause: "Play/Pause",
        .findRemote: "Find Remote",
        .backspace: "Backspace",
        .search: "Search",
        .enter: "Enter",
        .channelUp: "Channel Up",
        .channelDown: "Channel Down",
        .inputTuner: "Input Tuner",
        .inputHDMI1: "Input HDMI 1",
        .inputHDMI2: "Input HDMI 2",
        .inputHDMI3: "Input HDMI 3",
        .inputHDMI4: "Input HDMI 4",
        .inputAV1: "Input AV 1",
        .headphonesMode: "Headphones Mode",
    ]

    public static var systemIcons: [RemoteButton: String?] = [
        .up: "chevron.up",
        .left: "chevron.left",
        .right: "chevron.right",
        .down: "chevron.down",
        .select: nil,
        .home: "house",
        .back: "arrow.left",
        .power: "power",
        .powerOn: "power",
        .powerOff: "power",
        .mute: "speaker.slash",
        .volumeUp: "speaker.plus",
        .volumeDown: "speaker.minus",
        .options: "asterisk",
        .instantReplay: "arrow.uturn.left",
        .rewind: "backward",
        .fastForward: "forward",
        .playPause: "playpause",
        .findRemote: "av.remote",
        .backspace: "delete.left",
        .search: "magnifyingglass",
        .enter: "return",
        .channelUp: "arrowtriangle.up",
        .channelDown: "arrowtriangle.down",
        .headphonesMode: "headphones",
        .inputTuner: nil,
        .inputHDMI1: nil,
        .inputHDMI2: nil,
        .inputHDMI3: nil,
        .inputHDMI4: nil,
        .inputAV1: nil,
    ]

    public static var buttonApiDescription: [RemoteButton: String] = [
        .up: "Up",
        .left: "Left",
        .right: "Right",
        .down: "Down",
        .select: "Select",
        .home: "Home",
        .back: "Back",
        .power: "Power",
        .powerOn: "PowerOn",
        .powerOff: "PowerOff",
        .mute: "VolumeMute",
        .volumeUp: "VolumeUp",
        .volumeDown: "VolumeDown",
        .options: "Info",
        .instantReplay: "InstantReplay",
        .rewind: "Rev",
        .fastForward: "Fwd",
        .playPause: "Play",
        .findRemote: "FindRemote",
        .backspace: "Backspace",
        .search: "Search",
        .enter: "Enter",
        .channelUp: "ChannelUp",
        .channelDown: "ChannelDown",
        .inputTuner: "InputTuner",
        .inputHDMI1: "InputHDMI1",
        .inputHDMI2: "InputHDMI2",
        .inputHDMI3: "InputHDMI3",
        .inputHDMI4: "InputHDMI4",
        .inputAV1: "InputAV1",
    ]

    public var apiValue: String? {
        Self.buttonApiDescription[self]
    }

    public var systemIcon: String? {
        // Why do I have to do this
        if let icon = Self.systemIcons[self] {
            icon
        } else {
            nil
        }
    }

    public static func fromCharacter(character: Character) -> RemoteButton? {
        #if !os(watchOS)
            let keyMap: [Character: RemoteButton] = [
                "\u{7F}": RemoteButton.backspace,
                KeyEquivalent.delete.character: RemoteButton.backspace,
                KeyEquivalent.deleteForward.character: RemoteButton.backspace,
                KeyEquivalent.escape.character: RemoteButton.backspace,
                KeyEquivalent.downArrow.character: RemoteButton.down,
                KeyEquivalent.upArrow.character: RemoteButton.up,
                KeyEquivalent.rightArrow.character: RemoteButton.right,
                KeyEquivalent.leftArrow.character: RemoteButton.left,
                KeyEquivalent.home.character: RemoteButton.home,
                KeyEquivalent.return.character: RemoteButton.select,
            ]
        #else
            let keyMap: [Character: RemoteButton] = [
                "\u{7F}": RemoteButton.backspace,
            ]
        #endif

        if let mappedString = keyMap[character] {
            return mappedString
        }

        return nil
    }

    @ViewBuilder
    public var label: some View {
        if let systemIcon {
            Label(description, systemImage: systemIcon)
        } else {
            Text(description)
        }
    }

    public var description: String {
        Self.caseDisplayRepresentations[self]!
    }
}
