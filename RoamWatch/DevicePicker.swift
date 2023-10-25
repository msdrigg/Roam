//
//  DevicePicker.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

import Foundation
import SwiftUI
import os


struct DevicePicker: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DevicePicker.self)
    )
    
    @Environment(\.modelContext) private var modelContext
    
    let devices: [Device]
    @Binding var device: Device?
    @State var showingPicker: Bool = false
    @State var navPath = NavigationPath()
    
    
    var deviceStatusColor: Color {
        device?.isOnline() ?? false ? Color.green : Color.secondary
    }
    
    var body: some View {
        Button(action: {showingPicker.toggle()}) {
            Label("Devices", systemImage: "list.bullet")
                .labelStyle(.iconOnly)
        }
        .sheet(isPresented: $showingPicker) {
            SettingsNavigationWrapper(path: $navPath) {
                List {
                    Section("Devices") {
                        ForEach(devices) { listItemDevice in
                            Button(action: {
                                if let chosenDevice = devices.first(where: { d in
                                    d.id == listItemDevice.id
                                }) {
                                    Self.logger.debug("Setting last selected at")
                                    chosenDevice.lastSelectedAt = Date.now
                                }
                                do {
                                    try modelContext.save()
                                } catch {
                                    Self.logger.error("Error saving device selection: \(error)")
                                }
                                showingPicker = false
                            }) {
                                if listItemDevice.id == device?.id {
                                    Label(listItemDevice.name, systemImage: "checkmark.circle.fill").tag(listItemDevice as Device?)
                                } else {
                                    Label(listItemDevice.name, systemImage: "").tag(listItemDevice as Device?)
                                }
                            }
                        }
                        
                        if devices.isEmpty {
                            Text("No devices")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    NavigationLink(value: SettingsDestination.Global) {
                        Label("Settings", systemImage: "gear")
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}
