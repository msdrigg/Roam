//
//  SmallButtons.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/17/23.
//

import Foundation
import SwiftUI
import SwiftData
import AppIntents
import WidgetKit

struct SmallRemoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.betterremote.small-remote",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            SmallRemoteView(device: entry.device)
        }
        .supportedFamilies([.systemSmall])
    }
}

struct SmallRemoteView: View {
    var device: DeviceAppEntity?
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Button(intent: ButtonPressIntent().withButton(.left).withDevice(device)) {
                    Image(systemName: "arrow.left")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
                
                Button(intent: ButtonPressIntent().withButton(.power).withDevice(device)) {
                    Image(systemName: "power")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.red)
                }.buttonStyle(.plain)
                
                Button(intent: ButtonPressIntent().withButton(.home).withDevice(device)) {
                    Image(systemName: "house")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
            }

            HStack(spacing: 4) {
                Button(intent: ButtonPressIntent().withButton(.left).withDevice(device)) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
                
                Button(intent: ButtonPressIntent().withButton(.select).withDevice(device)) {
                    Text("Ok")
                        .font(.headline)
                        .fixedSize()
                        .fontDesign(.rounded)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
                
                Button(intent: ButtonPressIntent().withButton(.playPause).withDevice(device)) {
                    Image(systemName: "playpause")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
            }
            
            HStack(spacing: 4) {
                Button(intent: ButtonPressIntent().withButton(.mute).withDevice(device)) {
                    Image(systemName: "speaker.slash")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
                
                Button(intent: ButtonPressIntent().withButton(.volumeDown).withDevice(device)) {
                    Image(systemName: "minus")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
                
                Button(intent: ButtonPressIntent().withButton(.volumeUp).withDevice(device)) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 18, height: 20)
                }
                .buttonBorderShape(.roundedRectangle)
            }
        }
        .tint(Color("AccentColor"))
        .containerBackground(Color("WidgetBackground"), for: .widget)
    }
}


#Preview(as: WidgetFamily.systemSmall) {
    SmallRemoteWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: getTestingDevices()[0].toAppEntity()
    )
}

#Preview(as: WidgetFamily.systemSmall) {
    SmallRemoteWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: nil
    )
}
