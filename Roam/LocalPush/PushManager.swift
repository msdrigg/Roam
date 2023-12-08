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
        
        Task {
            guard let pm = await self.save(pushManager: self.pushManager ?? NEAppPushManager()) else {
                return
            }
            
            prepare(pushManager: pm)
        }
    }
    
    func initialize() {
        Self.logger.log("Loading existing push manager.")
        
        // It is important to call loadAllFromPreferences as early as possible during app initialization in order to set the delegate on your
        // NEAppPushManagers. This allows your NEAppPushManagers to receive an incoming call.
        NEAppPushManager.loadAllFromPreferences { managers, error in
            if let error = error {
                Self.logger.log("Failed to load all managers from preferences: \(error)")
                return
            }
            
            guard let manager = managers?.first else {
                return
            }
            
            // The manager's delegate must be set synchronously in this closure in order to avoid race conditions when the app launches in response
            // to an incoming call.
            manager.delegate = self
            
            self.dispatchQueue.async {
                self.prepare(pushManager: manager)
            }
        }
    }
    
    private func prepare(pushManager: NEAppPushManager) {
        self.pushManager = pushManager
        
        if pushManager.delegate == nil {
            pushManager.delegate = self
        }
        
        // Observe changes to the manager's `isActive` property and send the value out on the `pushManagerIsActiveSubject`.
        pushManagerIsActiveCancellable = NSObject.KeyValueObservingPublisher(object: pushManager, keyPath: \.isActive, options: [.initial, .new])
        .subscribe(pushManagerIsActiveSubject)
    }
    
    private func save(pushManager: NEAppPushManager) async -> NEAppPushManager? {
        pushManager.localizedDescription = pushManagerDescription
        pushManager.providerBundleIdentifier = pushProviderBundleIdentifier
        pushManager.delegate = self
        pushManager.isEnabled = true
        
        // The provider configuration passes global variables; don't put user-specific info in here (which could expose sensitive user info when
        // running on a shared iPad).
        pushManager.providerConfiguration = [:]
        
        pushManager.matchSSIDs = ["Myfi-GL"]
        
        pushManager.matchPrivateLTENetworks = []
        
        return try? await withCheckedThrowingContinuation {continuation in
            pushManager.saveToPreferences { error in
                if let error = error {
                    Self.logger.error("Error saving push manager preferences \(error)")
                    continuation.resume(with: .failure(error))
                    return
                }
                Self.logger.info("Saved push manager preferences")
                continuation.resume(returning: pushManager)
            }
        }
    }
    
    private func cleanup() {
        pushManager = nil
        pushManagerIsActiveCancellable = nil
        pushManagerIsActiveSubject.send(false)
    }
}

extension PushConfigurationManager: NEAppPushDelegate {
    func appPushManager(_ manager: NEAppPushManager, didReceiveIncomingCallWithUserInfo userInfo: [AnyHashable: Any] = [:]) {
        Self.logger.log("NEAppPushDelegate received an incoming call with user info \(String(describing: userInfo))")
    }
}

