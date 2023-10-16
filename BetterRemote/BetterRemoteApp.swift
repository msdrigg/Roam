//
//  BetterRemoteApp.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/6/23.
//

import SwiftUI
import SwiftData

@main
struct BetterRemoteApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AppLink.self,
            Device.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RemoteView()
        }
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        #endif
        .modelContainer(sharedModelContainer)
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
        #endif

    }
}
