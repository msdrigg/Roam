import SwiftUI

func getKeypressForKey(key: Character) -> String {
    if key == KeyEquivalent.return.character {
        print("Getting abcabc return")
    }
    // All of these keys are gauranteed to have api values
    #if !os(watchOS)
        let keyMap: [Character: String] = [
            "\u{7F}": RemoteButton.backspace.apiValue!,
            KeyEquivalent.delete.character: RemoteButton.backspace.apiValue!,
            KeyEquivalent.deleteForward.character: RemoteButton.backspace.apiValue!,
            KeyEquivalent.escape.character: RemoteButton.backspace.apiValue!,
            KeyEquivalent.space.character: "LIT_ ",
            KeyEquivalent.downArrow.character: RemoteButton.down.apiValue!,
            KeyEquivalent.upArrow.character: RemoteButton.up.apiValue!,
            KeyEquivalent.rightArrow.character: RemoteButton.right.apiValue!,
            KeyEquivalent.leftArrow.character: RemoteButton.left.apiValue!,
            KeyEquivalent.home.character: RemoteButton.home.apiValue!,
            KeyEquivalent.return.character: RemoteButton.select.apiValue!,
        ]
    #else
        let keyMap: [Character: String] = [
            "\u{7F}": RemoteButton.backspace.apiValue!,
        ]
    #endif

    if let mappedString = keyMap[key] {
        return mappedString
    }

    return "LIT_\(key)"
}
