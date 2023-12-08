import Foundation
import Combine
import UserNotifications
import OSLog

class MessagingManager: NSObject {
    static let shared = MessagingManager()
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: MessagingManager.self)
    )
    
    let channel: AsyncBufferedChannel<String> = .init()
    
    func initialize() {
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [self] granted, error in
            if granted == true && error == nil {
                logger.log("Notification permission granted")
            } else {
                logger.log("Notification permission denied")
            }
        }
    }
    
    private func textMessage(from notification: UNNotification) -> String? {
        guard let messageBody = notification.request.content.userInfo["message"] as? String else {
            logger.log("Notification was missing required message and cannot be loaded")
            return nil
        }
        
        
        return messageBody
    }
}

extension MessagingManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let message = textMessage(from: notification) else {
            return completionHandler([.badge, .sound, .banner])
        }
        
        completionHandler([])
        channel.send(message)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let message = textMessage(from: response.notification) else {
            completionHandler()
            return
        }
        
        channel.send(message)
        completionHandler()
    }
}
