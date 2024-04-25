//
//  PaddedHoverButtonStyle.swift
//  Roam
//
//  Created by Scott Driggers on 3/17/24.
//

#if os(macOS)
    import SwiftUI

    struct PaddedHoverButtonStyle: ButtonStyle {
        var padding: EdgeInsets

        func makeBody(configuration: Self.Configuration) -> some View {
            configuration.label
                .padding(padding)
                .background(HoverEffectBackground(configuration: configuration))
                .cornerRadius(5) // Mimic accessoryBar style corner radius
        }

        private struct HoverEffectBackground: View {
            @State private var isHovered = false
            let configuration: ButtonStyle.Configuration

            var body: some View {
                Rectangle()
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.4) : isHovered ? Color.secondary
                        .opacity(0.2) : Color.clear)
                    .preciseHovered { hover in
                        isHovered = hover
                    }
                    .animation(.easeInOut, value: isHovered || configuration.isPressed)
            }
        }
    }
#endif
