/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A central object for coordinating changes to the NEAppPushManager configuration.
*/

import Foundation
import Combine
import NetworkExtension
import OSLog


class PushConfigurationManager: NSObject {
    static let MATCH_SSIDS: [String] = ["Indah Coffee"]
    static let shared = PushConfigurationManager()
    
    // A publisher that returns the active state of the current push manager.
    private(set) lazy var pushManagerIsActivePublisher = {
        pushManagerIsActiveSubject
        .debounce(for: .milliseconds(500), scheduler: dispatchQueue)
        .eraseToAnyPublisher()
    }()
    
    private let dispatchQueue = DispatchQueue(label: "PushConfigurationManager.dispatchQueue")
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PushConfigurationManager.self)
    )
    private var pushManager: NEAppPushManager?
    private let pushManagerDescription = "SimplePushDefaultConfiguration"
    private let pushProviderBundleIdentifier = "com.msdrigg.roam.SimplePushProvider"
    private let pushManagerIsActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var pushManagerIsActiveCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
    }
    
    func create() {
        Task {
            Self.logger.info("Creating new PM. Current should be null. current=\(String(describing: self.pushManager))")
            guard let pm = await self.save(pushManager: NEAppPushManager()) else {
                Self.logger.error("Failed to create new PM for some reason")
                return
            }
            Self.logger.info("Created new pm: ssids=\(pm.matchSSIDs) enabled=\(pm.isEnabled)")
            
            prepare(pushManager: pm)
        }

    }
    
    func initialize() {
        Self.logger.log("Loading existing push manager.")
        
        
        NEAppPushManager.loadAllFromPreferences { managers, error in
            if let error = error {
                Self.logger.log("Failed to load all push managers from preferences: \(error)")
                self.create()
                return
            }
            
            guard let manager = managers?.first else {
                self.create()
                return
            }
            
            manager.delegate = self
            
            Self.logger.info("Loaded push manager ssids=\(manager.matchSSIDs) enabled=\(manager.isEnabled)")
            
            self.dispatchQueue.async {
                self.prepare(pushManager: manager)
            }
        }
    }
    
    private func prepare(pushManager: NEAppPushManager) {
        Self.logger.info("Preparing push manager: enabled=\(String(describing: pushManager.isEnabled)) ssids=\(String(describing: pushManager.matchSSIDs))")
        self.pushManager = pushManager
        
        if pushManager.delegate == nil {
            pushManager.delegate = self
        }
        
        // Observe changes to the manager's `isActive` property and send the value out on the `pushManagerIsActiveSubject`.
        pushManagerIsActiveCancellable = NSObject.KeyValueObservingPublisher(object: pushManager, keyPath: \.isActive, options: [.initial, .new])
        .subscribe(pushManagerIsActiveSubject)
        
        Task {
            if let pm = await self.save(pushManager: pushManager) {
                Self.logger.info("PM updated, so updating in self")
                self.pushManager = pm
            } else {
                Self.logger.info("PM not updated, so no save occurred")
            }
        }
    }
    
    private func save(pushManager: NEAppPushManager) async -> NEAppPushManager? {
        if pushManager.isEnabled && pushManager.matchSSIDs == Self.MATCH_SSIDS {
            return nil
        }
        pushManager.localizedDescription = pushManagerDescription
        pushManager.providerBundleIdentifier = pushProviderBundleIdentifier
        pushManager.delegate = self
        pushManager.isEnabled = true
        
        pushManager.providerConfiguration = [:]
        
        pushManager.matchSSIDs = Self.MATCH_SSIDS
        
        pushManager.matchPrivateLTENetworks = []
        
        let result: Optional<NEAppPushManager> = try? await withCheckedThrowingContinuation {continuation in
            pushManager.saveToPreferences { error in
                if let error = error {
                    Self.logger.error("Error saving push manager preferences \(error)")
                    continuation.resume(with: .failure(error))
                    return
                }
                Self.logger.info("Saved push manager preferences enabled=\(pushManager.isEnabled), ssids=\(pushManager.matchSSIDs)")
                continuation.resume(returning: pushManager)
            }
        }
        
        Self.logger.info("Push manager preferences saved ssids=\(String(describing: result?.matchSSIDs))")
        return result
    }
    
    private func cleanup() {
        pushManager = nil
        pushManagerIsActiveCancellable = nil
        pushManagerIsActiveSubject.send(false)
    }
}

extension PushConfigurationManager: NEAppPushDelegate {
    func appPushManager(_ manager: NEAppPushManager, didReceiveIncomingCallWithUserInfo userInfo: [AnyHashable: Any] = [:]) {
        Self.logger.info("NEAppPushDelegate received an incoming call with user info \(String(describing: userInfo))")
    }
}

