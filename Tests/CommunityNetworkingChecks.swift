import Foundation
import Security

private final class CommunityFixtureProtocol: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var offline = false
    static var user = "fixture-self"
    static var compatible = true
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "gorilla-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.offline { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let path = request.url!.path
        var body: [String: Any] = [:]
        if path.hasSuffix("capabilities") {
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            body = ["service": Self.compatible ? "gorilla-parking-community" : "other", "apiVersion": 1,
                    "push": ["apns": false, "fcm": false], "auth": ["apple": true]]
        } else if path.hasSuffix("auth/apple/challenge") {
            body = ["challengeId": "fixture-challenge", "nonce": "fixture-nonce"]
        } else if path.hasSuffix("auth/apple") {
            body = ["token": "fixture-apple-token", "userId": "fixture-apple-user"]
        } else if path.hasSuffix("auth/verify") {
            body = ["token": "fixture-token-" + Self.user, "userId": Self.user]
        } else if path.hasSuffix("plates/lookup") { body = ["available": true] }
        else if path.hasSuffix("messages") {
            body = ["messages": [
                ["id": "fixture-first", "authorId": "fixture-self", "text": "sent", "createdAt": 1],
                ["id": "fixture-received", "authorId": "fixture-other", "text": "received", "createdAt": 2]]]
        } else if path.hasSuffix("threads") { body = ["threadId": "fixture-thread", "pushStatus": "not_configured"] }
        if Self.status != 200 { body = ["error": Self.status == 401 ? "sign_in_required" : "internal_error"] }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct CommunityNetworkingChecks {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CommunityFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let address = "https://gorilla-fixture.invalid/v1/parking-community"
        let api = CommunityHTTPClient(baseURL: URL(string: address)!, session: session)
        defer {
            api.clearSession()
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("parkingCommunity.ownership:" + address) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        precondition(CommunityHTTPClient.normalized(" https://gorilla-fixture.invalid/ ")?.absoluteString == address)
        for invalid in ["http://example.com", "https://user:password@example.com", "https://example.com/?secret=1", "https://example.com/login"] {
            precondition(CommunityHTTPClient.normalized(invalid) == nil)
        }
        let verified = try await CommunityHTTPClient.verifyServer(address, session: session)
        precondition(verified.absoluteString == address)
        CommunityFixtureProtocol.compatible = false
        do { _ = try await CommunityHTTPClient.verifyServer(address, session: session); preconditionFailure("Wrong service accepted") }
        catch let error as CommunityAPIError { precondition(error.code == "incompatible_server") }
        CommunityFixtureProtocol.compatible = true
        try await api.verify(email: "fixture@example.invalid", code: "123456")
        precondition(api.signedIn)
        let available = try await api.recipientAvailable("AB1234")
        precondition(available)
        let rows = try await api.messages("fixture-thread")
        precondition(rows[0].isOutgoing && !rows[1].isOutgoing)
        // Legacy login had a token but no user ID: a locally-created thread proves
        // its first author, without guessing from message text or timestamps.
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "GorillaLeading.ParkingCommunity",
                       kSecAttrAccount as String: address + ":user"] as CFDictionary)
        _ = try await api.send(plate: "AB1234", text: "sent", key: UUID())
        let legacy = try await api.messages("fixture-thread")
        precondition(legacy[0].isOutgoing && !legacy[1].isOutgoing)
        let store = ParkingCommunityStore(api: api)
        for status in [401, 503] {
            CommunityFixtureProtocol.status = status
            do { _ = try await api.messages("fixture-thread"); preconditionFailure("Failure expected") }
            catch { store.handle(error) }
            precondition(api.signedIn && store.signedIn)
        }
        CommunityFixtureProtocol.status = 200; CommunityFixtureProtocol.offline = true
        do { _ = try await api.messages("fixture-thread"); preconditionFailure("Offline failure expected") }
        catch { store.handle(error) }
        precondition(api.signedIn && store.signedIn)
        CommunityFixtureProtocol.offline = false
        try await api.logout()
        CommunityFixtureProtocol.user = "fixture-different-account"
        try await api.verify(email: "another@example.invalid", code: "123456")
        let differentAccount = try await api.messages("fixture-thread")
        precondition(!differentAccount[0].isOutgoing)
        let capabilities = try await api.capabilities()
        precondition(capabilities.auth?.apple == true)
        let challenge = try await api.appleChallenge(linking: false)
        precondition(challenge.challengeId == "fixture-challenge")
        try await api.signInWithApple(challenge: challenge, identityToken: "fixture-token", authorizationCode: "fixture-code", linking: false)
        precondition(api.signedIn)
        print("Community URL probing, legacy ownership, account separation and outage checks passed")
    }
}
