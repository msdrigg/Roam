import SwiftUI
import Foundation

func DataImage(from data: Data?, fallback: String) -> Image {
    if let data = data {
#if os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
        } else {
            Image(systemName: fallback)
        }
#else
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
        } else {
            Image(systemName: fallback)
        }
#endif
    } else {
        Image(systemName: fallback)
    }
}

