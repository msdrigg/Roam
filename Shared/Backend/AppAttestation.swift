import CryptoKit
import DeviceCheck
import Foundation
import OSLog

/// Bundle ids the backend will accept an attestation from. The widget
/// extensions have their own bundle ids and are not on the list, so if one ever
/// does reach the backend it fails here with a clear error rather than burning
/// an App Attest registration the server would refuse anyway.
private let attestableBundleIDs: Set<String> = [
    "com.msdrigg.roam",
    "com.msdrigg.roam.watchkitapp",
]

/// Routes that create something durable on the backend, and the only ones that
/// carry an assertion.
///
/// Signing by HTTP method instead would sign `/typing`, which goes out every
/// five seconds while someone is composing, and that is the assertion volume
/// Apple warns has real CPU cost. This list has to match `requires_proof` in
/// the backend's `auth.rs`, or a signed request meets a server that ignores the
/// signature and an unsigned one meets a server that demands it.
private let proofRequiredPaths: Set<String> = [
    "/v2/new-message",
    "/new-message",
    "/v2/upload-diagnostics",
    "/new-apns",
]

private func requiresProof(_ path: String) -> Bool {
    proofRequiredPaths.contains(path) || path.hasPrefix("/upload-diagnostics/")
}

/// Platform and OS version, reported when a device cannot attest so the backend
/// can separate an old Mac from a client that should have been able to.
private func platformDescription() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    #if os(macOS)
        let platform = "macOS"
    #elseif os(iOS)
        let platform = "iOS"
    #elseif os(watchOS)
        let platform = "watchOS"
    #elseif os(visionOS)
        let platform = "visionOS"
    #else
        let platform = "unknown"
    #endif
    return "\(platform) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}

public enum BackendAuthError: Error, LocalizedError {
    case attestationRejected(Int, String)
    case missingKey
    case missingReceipt
    case attestationUnavailable(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case let .attestationRejected(code, body):
            return "The backend rejected attestation (\(code)): \(body)"
        case .missingKey:
            return "No attestation key is available"
        case .missingReceipt:
            return "No App Store receipt is available to authenticate with"
        case let .attestationUnavailable(reason):
            return "App Attest is unavailable and this platform has no fallback: \(reason)"
        case .badResponse:
            return "The backend returned an unexpected response"
        }
    }
}

/// The bytes an assertion signs.
///
/// The client sends these exact bytes alongside the assertion, so the server
/// hashes what was signed rather than a re-serialisation of the same fields.
/// On the session-refresh route `s` carries the challenge, because there is no
/// session to name yet.
private struct AssertionClientData: Encodable {
    let s: String
    let m: String
    let p: String
    let t: Int64
}

private struct ChallengeResponse: Decodable {
    let challenge: String
    let expiresAtMs: Int64
}

private struct SessionResponse: Decodable {
    let token: String
    let sessionId: String
    let userId: String
    let expiresAtMs: Int64
    let attested: Bool
}

/// Holds the app's backend credential.
///
/// The session token lives here and nowhere else: it is never written to
/// disk, the Keychain, or a log. What does persist is the key identifier,
/// which names a P-256 key generated inside the Secure Enclave and is useless
/// without the hardware that holds it. Recovering the token from memory buys
/// an attacker reads at most, because every write has to carry a fresh
/// assertion that only that hardware can produce.
#if os(macOS)
    /// The Mac App Store receipt, base64 encoded.
    ///
    /// Present in every App Store copy. A local build has none, which is why
    /// development against production needs the backend's development flag
    /// rather than a client-side bypass.
    private func appStoreReceipt() -> String? {
        guard let url = Bundle.main.appStoreReceiptURL,
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return data.base64EncodedString()
    }
#endif

public actor BackendAuth {
    public static let shared = BackendAuth()

    private struct Session {
        let token: String
        let sessionId: String
        let userId: String
        let expiresAt: Date
        let attested: Bool
    }

    private var session: Session?
    /// Collapses concurrent callers onto one handshake so a cold launch does
    /// not fire several registrations at Apple's rate-limited endpoint.
    private var handshake: Task<Session, Error>?

    private let keychainService = "io.msd3.roam.appattest"
    private let keychainAccount = "app-attest-key-id"

    /// Sends `request` with a credential attached, refreshing once if the
    /// backend says the session is no longer good.
    public func authorizedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        for attempt in 0...1 {
            let session = try await currentSession()
            let signed = try await sign(request, with: session)
            let (data, response) = try await URLSession.shared.data(for: signed)

            if let http = response as? HTTPURLResponse, http.statusCode == 401, attempt == 0 {
                Log.backend.notice("Backend rejected the session; re-authenticating once")
                self.session = nil
                continue
            }
            return (data, response)
        }
        throw BackendAuthError.badResponse
    }

    /// Drops the in-memory session, so the next request re-authenticates.
    public func invalidate() {
        session = nil
    }

    private func currentSession() async throws -> Session {
        // A minute of headroom so a request that authenticates just under the
        // wire does not arrive just over it.
        if let session, session.expiresAt.timeIntervalSinceNow > 60 {
            return session
        }
        if let handshake {
            return try await handshake.value
        }

        let task = Task { try await self.establishSession() }
        handshake = task
        defer { handshake = nil }

        let established = try await task.value
        session = established
        adoptUserID(established.userId)
        return established
    }

    private func establishSession() async throws -> Session {
        let service = DCAppAttestService.shared
        let bundleID = Bundle.main.bundleIdentifier ?? "--"

        guard attestableBundleIDs.contains(bundleID), service.isSupported else {
            return try await fallbackSession(
                reason: "isSupported=\(service.isSupported) bundle=\(bundleID)")
        }

        do {
            return try await attestedSession(service: service)
        } catch {
            Log.backend.error(
                "Attestation failed: \(error, privacy: .public)")
            return try await fallbackSession(reason: "attestation failed: \(error)")
        }
    }

    /// The macOS-only fallback, for Macs below macOS 27 where App Attest does
    /// not exist.
    ///
    /// This is compiled out of every other platform on purpose. iOS 18,
    /// watchOS 11 and visionOS 2 all support App Attest, so a client there
    /// claiming it cannot attest is tampering rather than an old OS, and a
    /// binary that does not contain this code cannot be talked into using it.
    /// The backend refuses the route without a valid Apple-signed receipt, so
    /// the two halves have to be removed together when macOS 27 is the floor.
    private func fallbackSession(reason: String) async throws -> Session {
        #if os(macOS)
            let platform = platformDescription()
            guard let receipt = appStoreReceipt() else {
                Log.backend.error(
                    "No App Store receipt available on \(platform, privacy: .public); cannot authenticate"
                )
                throw BackendAuthError.missingReceipt
            }
            Log.backend.warning(
                "Falling back to a receipt-backed session on \(platform, privacy: .public): \(reason, privacy: .public)"
            )
            return try await unattestedSession(
                receipt: receipt, reason: "\(reason); \(platform)")
        #else
            // No fallback exists here, and none should: every supported OS on
            // this platform can attest.
            throw BackendAuthError.attestationUnavailable(reason)
        #endif
    }

    private func attestedSession(service: DCAppAttestService) async throws -> Session {
        if let keyID = loadKeyID() {
            do {
                return try await refreshSession(keyID: keyID, service: service)
            } catch let BackendAuthError.attestationRejected(code, _) where code == 401 {
                // The backend does not know this key, so the credential behind
                // it is gone. Start over rather than retrying forever.
                Log.backend.notice("Stored attestation key is unknown to the backend; re-registering")
                deleteKeyID()
            } catch let error as DCError {
                // A key ID outlives the key it names. Reinstalling the app or
                // restoring the device invalidates the Secure Enclave key while
                // the Keychain entry survives, so the identifier on disk can
                // point at nothing. Without this the app would retry a dead key
                // on every launch and never recover.
                Log.backend.notice(
                    "App Attest rejected the stored key (\(error.code.rawValue, privacy: .public)); re-registering"
                )
                deleteKeyID()
            }
        }

        return try await registerKey(service: service)
    }

    private func registerKey(service: DCAppAttestService) async throws -> Session {
        let challenge = try await fetchChallenge()
        let keyID = try await service.generateKey()
        // Persist before attesting: a key that is generated but not recorded
        // can never be used again, and Apple attests any given key only once.
        storeKeyID(keyID)

        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)

        let body: [String: String] = [
            "keyId": keyID,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
            "userId": getSystemInstallID(),
        ]
        let response: SessionResponse = try await post("/v3/attest/register", body: body)
        Log.backend.notice("Registered an attested key with the backend")
        return session(from: response)
    }

    private func refreshSession(keyID: String, service: DCAppAttestService) async throws -> Session {
        let challenge = try await fetchChallenge()
        let clientData = try encodeClientData(
            s: challenge, m: "POST", p: "/v3/attest/session")
        let clientDataHash = Data(SHA256.hash(data: clientData))
        let assertion = try await service.generateAssertion(keyID, clientDataHash: clientDataHash)

        let body: [String: String] = [
            "keyId": keyID,
            "assertion": assertion.base64EncodedString(),
            "clientData": clientData.base64EncodedString(),
        ]
        let response: SessionResponse = try await post("/v3/attest/session", body: body)
        return session(from: response)
    }

    private func unattestedSession(receipt: String, reason: String) async throws -> Session {
        let challenge = try await fetchChallenge()
        let body: [String: String] = [
            "userId": getSystemInstallID(),
            "challenge": challenge,
            "receipt": receipt,
            "reason": reason,
        ]
        let response: SessionResponse = try await post("/v3/attest/unattested", body: body)
        return session(from: response)
    }

    private func session(from response: SessionResponse) -> Session {
        Session(
            token: response.token,
            sessionId: response.sessionId,
            userId: response.userId,
            expiresAt: Date(timeIntervalSince1970: Double(response.expiresAtMs) / 1000),
            attested: response.attested
        )
    }

    private func sign(_ request: URLRequest, with session: Session) async throws -> URLRequest {
        var request = request
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        guard let path = request.url?.path(percentEncoded: true) else {
            throw BackendAuthError.badResponse
        }
        let method = request.httpMethod ?? "GET"
        guard session.attested, requiresProof(path) else {
            return request
        }
        guard let keyID = loadKeyID() else {
            throw BackendAuthError.missingKey
        }

        // Assertions are generated inside the actor, so their counters leave
        // the device in the order the Secure Enclave issued them.
        let clientData = try encodeClientData(s: session.sessionId, m: method, p: path)
        let clientDataHash = Data(SHA256.hash(data: clientData))
        let assertion = try await DCAppAttestService.shared.generateAssertion(
            keyID, clientDataHash: clientDataHash)

        request.setValue(clientData.base64EncodedString(), forHTTPHeaderField: "X-Roam-Client-Data")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Roam-Assertion")
        return request
    }

    private func encodeClientData(s: String, m: String, p: String) throws -> Data {
        let payload = AssertionClientData(
            s: s, m: m, p: p, t: Int64(Date().timeIntervalSince1970 * 1000))
        return try JSONEncoder().encode(payload)
    }

    private func fetchChallenge() async throws -> String {
        let response: ChallengeResponse = try await post("/v3/attest/challenge", body: [:])
        return response.challenge
    }

    private func post<Response: Decodable>(_ path: String, body: [String: String]) async throws
        -> Response
    {
        guard let url = URL(string: "\(globalBackendURL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendAuthError.badResponse
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "--"
            Log.backend.error(
                "Attestation call \(path, privacy: .public) failed \(http.statusCode, privacy: .public): \(detail, privacy: .public)"
            )
            throw BackendAuthError.attestationRejected(http.statusCode, detail)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: - Key identifier storage

    /// The key identifier is a handle, not a secret: it names a key the Secure
    /// Enclave will only ever use on this device. It lives in the Keychain so
    /// the app attests once per install rather than once per launch, which
    /// matters because Apple rate limits attestation.
    private func loadKeyID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let keyID = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return keyID
    }

    private func storeKeyID(_ keyID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(keyID.utf8)
        // Readable after the first unlock so a background refresh works, and
        // never synchronised: the private key it names cannot leave this
        // device, so a copy of the identifier elsewhere is dead weight.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Log.backend.error("Could not store attestation key id: \(status, privacy: .public)")
        }
    }

    private func deleteKeyID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
