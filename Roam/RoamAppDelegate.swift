import Foundation

#if os(macOS)
import AppKit
import SwiftUI

class RoamAppDelegate: NSObject, NSApplicationDelegate {
    var windowDelegate = RoamWindowDelegate()
    private var aboutBoxWindowController: NSWindowController?

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

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool
    {
        // Get URL components from the incoming user activity.
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let incomingURL = userActivity.webpageURL,
            let components = NSURLComponents(url: incomingURL, resolvingAgainstBaseURL: true) else {
            return false
        }


        // Check for specific URL components that you need.
        guard let path = components.path,
        let params = components.queryItems else {
            return false
        }
        print("path = \(path)")


        if let albumName = params.first(where: { $0.name == "albumname" } )?.value,
            let photoIndex = params.first(where: { $0.name == "index" })?.value {
            print("album = \(albumName)")
            print("photoIndex = \(photoIndex)")
            return true


        } else {
            print("Either album name or photo index missing")
            return false
        }
    }


    func applicationDidFinishLaunching(_ notification: Notification) {
        if let application = notification.object as? NSApplication {
            if let mainWindow = application.mainWindow ?? application.windows.first {
                mainWindow.delegate = windowDelegate
            }
        }
    }
}
#else
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    
}
#endif
