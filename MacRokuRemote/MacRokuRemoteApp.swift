//
//  MacRokuRemoteApp.swift
//  MacRokuRemote
//
//  Created by Scott Driggers on 10/6/23.
//

import SwiftUI
import SwiftData

@main
struct MacRokuRemoteApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
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
            RokuRemoteView()
        }
        .modelContainer(sharedModelContainer)
    }
}
