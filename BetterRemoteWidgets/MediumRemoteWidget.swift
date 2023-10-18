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

struct MediumRemoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.betterremote.medium-remote",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            MediumRemoteView(device: entry.device)
        }
        .supportedFamilies([.systemMedium])
    }
}

struct MediumRemoteView: View {
    var device: DeviceAppEntity?
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Button(intent: ButtonPressIntent().withButton(.back).withDevice(device)) {
                        Image(systemName: "arrow.left")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.up).withDevice(device)) {
                        Image(systemName: "chevron.up")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.home).withDevice(device)) {
                        Image(systemName: "house")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                }
                
                HStack(spacing: 4) {
                    Button(intent: ButtonPressIntent().withButton(.left).withDevice(device)) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.select).withDevice(device)) {
                        Text("Ok")
                            .font(.headline)
                            .fixedSize()
                            .fontDesign(.rounded)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.right).withDevice(device)) {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                }
                
                HStack(spacing: 4) {
                    Text("")
                        .font(.headline)
                        .fixedSize()
                        .fontDesign(.rounded)
                        .frame(width: 20, height: 24)
                    
                    Button(intent: ButtonPressIntent().withButton(.down).withDevice(device)) {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Text("")
                        .font(.headline)
                        .fixedSize()
                        .fontDesign(.rounded)
                        .frame(width: 20, height: 24)
                }
            }
            
            Spacer()

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Button(intent: ButtonPressIntent().withButton(.instantReplay).withDevice(device)) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.power).withDevice(device)) {
                        Image(systemName: "power")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(.red)
                    }.buttonStyle(.plain)
                    
                    Button(intent: ButtonPressIntent().withButton(.options).withDevice(device)) {
                        Image(systemName: "asterisk")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                }
                
                HStack(spacing: 4) {
                    Button(intent: ButtonPressIntent().withButton(.rewind).withDevice(device)) {
                        Image(systemName: "backward")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.playPause).withDevice(device)) {
                        Image(systemName: "playpause")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.fastForward).withDevice(device)) {
                        Image(systemName: "forward")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                }
                
                HStack(spacing: 4) {
                    Button(intent: ButtonPressIntent().withButton(.mute).withDevice(device)) {
                        Image(systemName: "speaker.slash")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.volumeDown).withDevice(device)) {
                        Image(systemName: "minus")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    
                    Button(intent: ButtonPressIntent().withButton(.volumeUp).withDevice(device)) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 20, height: 24)
                    }
                    .buttonBorderShape(.roundedRectangle)
                }
            }
        }
        .tint(Color("AccentColor"))
        .containerBackground(Color("WidgetBackground"), for: .widget)
    }
}


#Preview(as: WidgetFamily.systemMedium) {
    MediumRemoteWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: getTestingDevices()[0].toAppEntity()
    )
}
