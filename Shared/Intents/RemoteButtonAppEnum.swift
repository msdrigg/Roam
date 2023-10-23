import AppIntents

enum RemoteButtonAppEnum: String, AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(stringLiteral: "RemoteButtonAppEnum")
        
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
    case privateListening = "PrivateListening"
    
    
    public static var typeDisplayName: String = "Button"
    
    public static var caseDisplayRepresentations: [RemoteButtonAppEnum: DisplayRepresentation] = [
        .up: "Up",
        .left: "Left",
        .right: "Right",
        .down: "Down",
        .select: "Select",
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
        .privateListening: "Private Listening"
    ]
    
    var button: RemoteButton {
        switch self {
        case .up:
            return .up
        case .left:
            return .left
        case .right:
            return .right
        case .down:
            return .down
        case .select:
            return .select
        case .home:
            return .home
        case .back:
            return .back
        case .power:
            return .power
        case .powerOn:
            return .powerOn
        case .powerOff:
            return .powerOff
        case .mute:
            return .mute
        case .volumeUp:
            return .volumeUp
        case .volumeDown:
            return .volumeDown
        case .options:
            return .options
        case .instantReplay:
            return .instantReplay
        case .rewind:
            return .rewind
        case .fastForward:
            return .fastForward
        case .playPause:
            return .playPause
        case .findRemote:
            return .findRemote
        case .backspace:
            return .backspace
        case .search:
            return .search
        case .enter:
            return .enter
        case .channelUp:
            return .channelUp
        case .channelDown:
            return .channelDown
        case .inputTuner:
            return .inputTuner
        case .inputHDMI1:
            return .inputHDMI1
        case .inputHDMI2:
            return .inputHDMI2
        case .inputHDMI3:
            return .inputHDMI3
        case .inputHDMI4:
            return .inputHDMI4
        case .inputAV1:
            return .inputAV1
        case .privateListening:
            return .privateListening
        }
    }
    
    init(_ button: RemoteButton) {
        switch button {
        case .up:
            self = .up
        case .left:
            self = .left
        case .right:
            self = .right
        case .down:
            self = .down
        case .select:
            self = .select
        case .home:
            self = .home
        case .back:
            self = .back
        case .power:
            self = .power
        case .powerOn:
            self = .powerOn
        case .powerOff:
            self = .powerOff
        case .mute:
            self = .mute
        case .volumeUp:
            self = .volumeUp
        case .volumeDown:
            self = .volumeDown
        case .options:
            self = .options
        case .instantReplay:
            self = .instantReplay
        case .rewind:
            self = .rewind
        case .fastForward:
            self = .fastForward
        case .playPause:
            self = .playPause
        case .findRemote:
            self = .findRemote
        case .backspace:
            self = .backspace
        case .search:
            self = .search
        case .enter:
            self = .enter
        case .channelUp:
            self = .channelUp
        case .channelDown:
            self = .channelDown
        case .inputTuner:
            self = .inputTuner
        case .inputHDMI1:
            self = .inputHDMI1
        case .inputHDMI2:
            self = .inputHDMI2
        case .inputHDMI3:
            self = .inputHDMI3
        case .inputHDMI4:
            self = .inputHDMI4
        case .inputAV1:
            self = .inputAV1
        case .privateListening:
            self = .privateListening
        }
    }

}
