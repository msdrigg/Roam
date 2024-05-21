import Foundation
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "AppDelegate"
)

// Optional: Send the device token to your server
func sendDeviceTokenToServer(_ token: String) async {
    do {
        try await sendMessage(message: nil, apnsToken: token)
    } catch {
        logger.error("Error sending apns token to server \(error)")
    }
}

#if os(macOS)
    import AppKit

    class RoamAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
        private var aboutBoxWindowController: NSWindowController?
        private var messagingWindowController: NSWindowController?
        private var modelContainer: ModelContainer = getSharedModelContainer()
        @Published var navigationPath: [NavigationDestination] = []
        @Published var messagingWindowOpenTrigger: UUID?

        override init() {
            super.init()
            UNUserNotificationCenter.current().delegate = self
        }

        @MainActor func showAboutPanel() {
            if aboutBoxWindowController == nil {
                let styleMask: NSWindow.StyleMask = [.closable, .miniaturizable, .titled]
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                    styleMask: styleMask,
                    backing: .buffered,
                    defer: false
                )
                window.center()
                window.title = "About Roam"
                window.contentView = NSHostingView(rootView: ExternalAboutView())
                aboutBoxWindowController = NSWindowController(window: window)
                aboutBoxWindowController?.showWindow(nil)
            }
            aboutBoxWindowController?.showWindow(aboutBoxWindowController?.window)
        }

        func application(_: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            let tokenParts = deviceToken.map { data -> String in
                String(format: "%02.2hhx", data)
            }
            let token = tokenParts.joined()
            logger.info("Device Token: \(token)")

            Task {
                await sendDeviceTokenToServer(token)
                UserDefaults.standard.set(true, forKey: "hasSentFirstMessage")
            }
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            logger.info("didReceive notification. Showing Messages...")
            #if os(macOS)
                messagingWindowOpenTrigger = UUID()
            #else
                if navigationPath.last != NavigationDestination.messageDestination {
                    navigationPath.append(NavigationDestination.messageDestination)
                }
            #endif
            completionHandler()
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            logger.info("WillPresent notification. Refreshing messages...")
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<Message>(
                predicate: #Predicate {
                    $0.fetchedBackend == true
                },
                sortBy: [SortDescriptor(\.id, order: .reverse)]
            )
            descriptor.fetchLimit = 1

            let lastMessage = try? context.fetch(descriptor).last

            let latestMessageId = lastMessage?.id
            Task.detached {
                let dataHandler = DataHandler(modelContainer: self.modelContainer)
                await dataHandler.refreshMessages(latestMessageId: latestMessageId, viewed: false)
            }
            completionHandler(.badge)
        }

        func application(_: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            logger.error("Failed to register with Error \(error)")
        }
    }
#else
    import UIKit

    class RoamAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
        private var modelContainer: ModelContainer = getSharedModelContainer()

        @Published var navigationPath: [NavigationDestination] = []

        override init() {
            super.init()
            UNUserNotificationCenter.current().delegate = self
        }

        func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            let tokenParts = deviceToken.map { data -> String in
                String(format: "%02.2hhx", data)
            }
            let token = tokenParts.joined()
            logger.info("Device Token: \(token)")

            Task {
                await sendDeviceTokenToServer(token)
                UserDefaults.standard.set(true, forKey: "hasSentFirstMessage")
            }
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            if navigationPath.last != NavigationDestination.messageDestination {
                navigationPath.append(NavigationDestination.messageDestination)
            }
            completionHandler()
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<Message>(
                predicate: #Predicate {
                    $0.fetchedBackend == true
                },
                sortBy: [SortDescriptor(\.id, order: .reverse)]
            )
            descriptor.fetchLimit = 1

            let lastMessage = try? context.fetch(descriptor).last

            let latestMessageId = lastMessage?.id
            Task.detached {
                await DataHandler(modelContainer: getSharedModelContainer()).refreshMessages(latestMessageId: latestMessageId, viewed: false)
            }
            completionHandler(.badge)
        }

        func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            logger.error("Failed to register with Error \(error)")
        }
    }
#endif
