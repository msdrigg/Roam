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
            logger.info("Setting Notifications delegate to self")

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
                window.title = String(localized: "About Roam", comment: "Window title on the about page of the Roam app")
                window.contentView = NSHostingView(rootView: ExternalAboutView())
                aboutBoxWindowController = NSWindowController(window: window)
                aboutBoxWindowController?.showWindow(nil)
            }
            aboutBoxWindowController?.showWindow(aboutBoxWindowController?.window)
        }
        
        func applicationDidFinishLaunching(_ notification: Notification) {
            let hasSentFirstMessage = UserDefaults.standard.bool(forKey: "hasSentFirstMessage")
            if hasSentFirstMessage {
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "lastApnsRequestTime")
                requestNotificationPermission()
            }

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
        
        func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
            logger.info("Received remote notification")
            refreshMessages()
        }
        
        func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            logger.info("didReceive notification. Showing Messages...")
            refreshMessages()
            messagingWindowOpenTrigger = UUID()
            completionHandler()
        }
        
        func refreshMessages() {
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

        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            logger.info("WillPresent notification. Refreshing messages...")
            refreshMessages()
            completionHandler(.badge)
        }

        func application(_: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            logger.error("Failed to register with Error \(error)")
        }
    }
#else
    import UIKit
    import Combine

    final class UserDefaultsPublisher: Sendable {
        static let shared = UserDefaultsPublisher()

        func publisher<T: Decodable>(for key: String) -> AnyPublisher<T, Never> {
            return NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
                .map { _ in
                    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
                    return try? PropertyListDecoder().decode(T.self, from: data)
                }
                .compactMap { $0 }
                .eraseToAnyPublisher()
        }
    }

    extension EventModifiers {
        var uiKeyModifierFlagsRepresentation: UIKeyModifierFlags {
            var flags = UIKeyModifierFlags()
            if self.contains(.shift) {
                flags.insert(.shift)
            }
            if self.contains(.control) {
                flags.insert(.control)
            }
            if self.contains(.option) {
                flags.insert(.alternate)
            }
            if self.contains(.command) {
                flags.insert(.command)
            }
            if self.contains(.capsLock) {
                flags.insert(.alphaShift)
            }
            return flags
        }
    }


extension UIViewController {
    func findFirstResponder() -> UIResponder? {
        if self.isFirstResponder {
            return self
        }
        for view in self.view.subviews {
            if let responder = view.findFirstResponder() {
                return responder
            }
        }
        return nil
    }
}

extension UIView {
    func findFirstResponder() -> UIResponder? {
        if self.isFirstResponder {
            return self
        }
        if let next = self.next, next.isFirstResponder {
            return next
        }

        for subview in self.subviews {
            if let responder = subview.findFirstResponder() {
                return responder
            }
        }
        return nil
    }
    
    func findFocused() -> UIView? {
        if self.isFocused{
            return self
        }

        for subview in self.subviews {
            if let responder = subview.findFocused() {
                return responder
            }
        }
        return nil
    }
}


    class RoamAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
        private var modelContainer: ModelContainer = getSharedModelContainer()

        @Published var navigationPath: [NavigationDestination] = []
        
        private var cancellables: Set<AnyCancellable> = []

        override init() {
            super.init()
            UNUserNotificationCenter.current().delegate = self
        }
        
        func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
            logger.info("Received remote notifications")
            requestMessages(fetchCompletionHandler: completionHandler)
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

        #if !os(tvOS)
        func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive _: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            logger.info("didReceive notification. Showing Messages...")
            if navigationPath.last != NavigationDestination.messageDestination {
                navigationPath.append(NavigationDestination.messageDestination)
            }
            completionHandler()
        }
        #endif
        
        func requestMessages(fetchCompletionHandler completionHandler: ((UIBackgroundFetchResult) -> Void)? = nil) {
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
                let refreshResult = await DataHandler(modelContainer: getSharedModelContainer()).refreshMessages(latestMessageId: latestMessageId, viewed: false)
                if refreshResult > 0 {
                    completionHandler?(.newData)
                } else {
                    completionHandler?(.noData)
                }
            }
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            logger.info("willPresent notification. Refreshing...")
            requestMessages()
            completionHandler(.badge)
        }
        
        func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
            let hasSentFirstMessage = UserDefaults.standard.bool(forKey: "hasSentFirstMessage")
            if hasSentFirstMessage {
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "lastApnsRequestTime")
                requestNotificationPermission()
            }

            Task {
                while true {
                    try? await Task.sleep(nanoseconds: 5 * 1000 * 1000 * 1000)
                    guard let scenes = UIApplication.shared.connectedScenes as? Set<UIWindowScene> else { return }

                    for scene in scenes {
                        for window in scene.windows where window.isKeyWindow {
                            print("Responder chain for window:")
                            var responder: UIResponder? = window.findFirstResponder()
                            if responder == nil {
                                print("No first repsonder")
                            }
                            while let currentResponder = responder {
                                print("\t\(currentResponder)")
                                responder = currentResponder.next
                            }
                        }
                    }
                }
            }
            return true
            
        }
        
        func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            logger.error("Failed to register for remote notifications with Error \(error)")
        }
    }
#endif
