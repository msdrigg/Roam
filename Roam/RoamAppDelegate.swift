import Foundation
import OSLog
import UserNotifications
import SwiftData
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "AppDelegate"
)

// Optional: Send the device token to your server
func sendDeviceTokenToServer(_ token: String) async {
    do {
        try await sendMessage(message: "", apnsToken: token)
    } catch {
        logger.error("Error sending apns token to server \(error)")
    }
}

#if os(macOS)
import AppKit

class RoamAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    var windowDelegate = RoamWindowDelegate()
    private var aboutBoxWindowController: NSWindowController?
    private var messagingWindowController: NSWindowController?
    private var modelContainer: ModelContainer = getSharedModelContainer()
    @Published var navigationPath: NavigationPath = NavigationPath()
    @Published var messagingWindowOpenTrigger: UUID? = nil
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func showAboutPanel() {
        if aboutBoxWindowController == nil {
            let styleMask: NSWindow.StyleMask = [.closable, .miniaturizable, .titled]
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: styleMask, backing: .buffered, defer: false)
            window.center()
            window.title = "About Roam"
            window.contentView = NSHostingView(rootView: ExternalAboutView())
            aboutBoxWindowController = NSWindowController(window: window)
            aboutBoxWindowController?.showWindow(nil)
        }
        aboutBoxWindowController?.showWindow(aboutBoxWindowController?.window)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let application = notification.object as? NSApplication {
            if let mainWindow = application.mainWindow ?? application.windows.first {
                mainWindow.delegate = windowDelegate
            }
        }
    }
    
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data -> String in
            return String(format: "%02.2hhx", data)
        }
        let token = tokenParts.joined()
        logger.info("Device Token: \(token)")

        Task {
            await sendDeviceTokenToServer(token)
            UserDefaults.standard.set(true, forKey: "hasSentFirstMessage")
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        logger.info("didReceive notification. Showing Messages...")
        #if os(macOS)
        messagingWindowOpenTrigger = UUID()
        #else
        navigationPath.removeLast(100)
        navigationPath.append(MessagingDestination.Global)
        #endif
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
        Task {
            await refreshMessages(modelContainer: modelContainer, latestMessageId: latestMessageId, viewed: false)
        }
        completionHandler(.badge)
    }
    
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register with Error \(error)")
    }
}
#else
import UIKit

class RoamAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    private var modelContainer: ModelContainer = getSharedModelContainer()

    @Published var navigationPath: NavigationPath = NavigationPath()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data -> String in
            return String(format: "%02.2hhx", data)
        }
        let token = tokenParts.joined()
        logger.info("Device Token: \(token)")

        // Here you might want to send the token to your server
        Task {
            await sendDeviceTokenToServer(token)
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        navigationPath.removeLast(100)
        navigationPath.append(MessagingDestination.Global)
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
        Task {
            await refreshMessages(modelContainer: modelContainer, latestMessageId: latestMessageId, viewed: false)
        }
        completionHandler(.badge)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register with Error \(error)")
    }
}
#endif
