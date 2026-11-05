import Foundation
import CoreGraphics
import Combine

/// Display spacing is preserved; matching ignores spacing. Never fuzzy-match recipients.
enum HKCommunityPlate {
    static let letters = "ABCDEFGHJKLMNPRSTUVWXYZ"
    static func cleaned(_ value: String) -> String {
        String(value.uppercased().filter { (letters + "0123456789 ").contains($0) }.prefix(8))
    }
    static func key(_ value: String) -> String { value.replacingOccurrences(of: " ", with: "") }
    static func isValid(_ value: String) -> Bool {
        !key(value).isEmpty && value.count <= 8 && cleaned(value) == value
    }
    static func ocrText(_ value: String) -> String {
        value.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .uppercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }
    static func standardCandidate(_ value: String) -> String? {
        let compact = ocrText(value)
        guard compact.range(of: "^(?:[A-HJ-NPR-Z]{1,2})?[1-9][0-9]{0,3}$", options: .regularExpression) != nil else { return nil }
        return compact
    }
}

/// OCR geometry uses one consistent top-left coordinate system per frame.
struct CommunityOCRSegment: Sendable {
    let text: String
    let bounds: CGRect
}
struct CommunityOCRCandidate: Identifiable, Sendable {
    var id: String { plate }
    let plate: String
    let bounds: CGRect
}
enum CommunityPlateOCR {
    static func candidates(_ segments: [CommunityOCRSegment]) -> [CommunityOCRCandidate] {
        var items = Array(segments.filter { !$0.bounds.isEmpty && !$0.text.isEmpty }.prefix(180))
        // Rejoin digit groups such as "12" + "34" before attaching the prefix.
        let digits = items.filter { HKCommunityPlate.ocrText($0.text).range(of: "^[0-9]{1,3}$", options: .regularExpression) != nil }
        for left in digits {
            if items.count >= 256 { break }
            for right in digits {
                if items.count >= 256 { break }
                let a = left.bounds, b = right.bounds
                let height = max(a.height, b.height)
                let text = HKCommunityPlate.ocrText(left.text + right.text)
                if text.count <= 4 && b.minX >= a.maxX - height * 0.1
                    && b.minX - a.maxX <= height * 0.8 && abs(a.midY - b.midY) <= height * 0.4 {
                    items.append(.init(text: text, bounds: a.union(b)))
                }
            }
        }
        var joined: [CommunityOCRCandidate] = []
        // Prefix and number are often separate observations, especially on two-line plates.
        for prefix in items {
            let letters = HKCommunityPlate.ocrText(prefix.text)
            guard letters.range(of: "^[A-HJ-NPR-Z]{1,2}$", options: .regularExpression) != nil else { continue }
            for number in items {
                let digits = HKCommunityPlate.ocrText(number.text)
                guard digits.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil else { continue }
                let a = prefix.bounds, b = number.bounds
                let height = max(a.height, b.height)
                let sameRow = abs(a.midY - b.midY) <= height * 0.5
                    && b.minX >= a.maxX - height * 0.15 && b.minX - a.maxX <= height * 2
                let twoRows = b.minY >= a.maxY - height * 0.15
                    && b.minY - a.maxY <= height * 1.5
                    && abs(a.midX - b.midX) <= max(a.width, b.width) * 0.45
                guard sameRow || twoRows,
                      let plate = HKCommunityPlate.standardCandidate(letters + digits) else { continue }
                joined.append(.init(plate: plate, bounds: a.union(b)))
            }
        }
        var result = joined
        for item in items {
            guard let plate = HKCommunityPlate.standardCandidate(item.text) else { continue }
            // Do not offer just the digit half when a complete plate has been assembled.
            if joined.contains(where: { $0.bounds.contains(item.bounds) }) { continue }
            result.append(.init(plate: plate, bounds: item.bounds))
        }
        result = result.filter { short in
            !result.contains { long in
                long.plate.count > short.plate.count && long.bounds.contains(short.bounds)
                    && long.plate.prefix(while: { $0.isLetter }) == short.plate.prefix(while: { $0.isLetter })
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.plate).inserted }.prefix(6).map { $0 }
    }
}

/// Keep an explicitly selectable result through short OCR tracking drop-outs.
struct CommunityOCRHold {
    private var recent: [String: Date] = [:]
    mutating func update(_ plates: [String], now: Date) -> [String] {
        for plate in plates { recent[plate] = now }
        recent = recent.filter { now.timeIntervalSince($0.value) < 4 }
        return recent.keys.sorted {
            let left = recent[$0]!, right = recent[$1]!
            return left == right ? $0 < $1 : left > right
        }.prefix(6).map { $0 }
    }
}

struct CommunityPlateDraft: Codable, Identifiable {
    var id: String { HKCommunityPlate.key(plate) }
    let plate: String
    let consentedAt: Date
}

/// Local drafts are deliberately not presented as server bindings.
@MainActor final class ParkingCommunityStore: ObservableObject {
    @Published private(set) var drafts: [CommunityPlateDraft]
    @Published private(set) var boundPlates: [CommunityPlateDraft] = []
    @Published private(set) var threads: [CommunityThread] = []
    @Published private(set) var signedIn: Bool
    @Published var errorMessage: String?
    let api: CommunityHTTPClient
    var configured: Bool { api.baseURL != nil }
    private let defaults: UserDefaults
    private let storageKey = "parkingCommunity.plateDrafts.v1"
    private var refreshGeneration = UUID()
    init(defaults: UserDefaults = .standard, api: CommunityHTTPClient = CommunityHTTPClient()) {
        self.defaults = defaults
        self.api = api
        self.signedIn = api.signedIn
        drafts = (defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([CommunityPlateDraft].self, from: $0) }) ?? []
    }
    func saveDraft(_ plate: String) {
        guard HKCommunityPlate.isValid(plate), !drafts.contains(where: { $0.id == HKCommunityPlate.key(plate) }) else { return }
        drafts.append(.init(plate: plate, consentedAt: Date()))
        persist()
    }
    func remove(_ id: String) { drafts.removeAll { $0.id == id }; persist() }
    func refresh() async {
        #if canImport(UIKit)
        Task { await CommunityPushCoordinator.shared.sync() }
        #endif
        let generation = UUID()
        refreshGeneration = generation
        errorMessage = nil
        signedIn = api.signedIn
        guard signedIn else { boundPlates = []; threads = []; return }
        do {
            await api.restoreIdentity()
            let fetchedPlates = try await api.bindings()
            let fetchedThreads = try await api.threads()
            guard refreshGeneration == generation, api.signedIn else { return }
            boundPlates = fetchedPlates
            threads = fetchedThreads
        } catch { if refreshGeneration == generation { handle(error) } }
    }
    func refreshThreads() async {
        guard api.signedIn else { return }
        let generation = refreshGeneration
        do {
            let fetched = try await api.threads()
            guard !Task.isCancelled, refreshGeneration == generation, api.signedIn else { return }
            threads = fetched; errorMessage = nil
        } catch { if !Task.isCancelled, refreshGeneration == generation { handle(error) } }
    }
    func handle(_ error: Error) {
        // Preserve credentials and cached views until explicit logout. Reauthentication
        // replaces an expired token without treating a server outage as logout.
        errorMessage = error.localizedDescription
    }
    func bindDraft(_ draft: CommunityPlateDraft) async {
        do { try await api.bind(draft.plate); remove(draft.id); await refresh() }
        catch { handle(error) }
    }
    func unbind(_ plate: String) async {
        do { try await api.unbind(plate); await refresh() }
        catch { handle(error) }
    }
    func logout() async {
        do {
            try await api.logout()
            #if canImport(UIKit)
            CommunityPushCoordinator.shared.reset()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            #endif
            await refresh()
        } catch { handle(error) }
    }
    func deleteAccount() async {
        do {
            try await api.deleteAccount()
            drafts = []; persist(); await refresh()
        } catch { handle(error) }
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(drafts), forKey: storageKey) }
}

// MARK: - Shared HTTP API and secure session
import Security

struct CommunityMessage: Decodable, Identifiable, Equatable {
    let id: String
    let authorId: String
    let text: String
    let createdAt: TimeInterval
    let mine: Bool?
    var isOutgoing: Bool { mine == true }
}
struct CommunityThread: Decodable, Identifiable {
    let id: String
    let plate: String
    let expiresAt: TimeInterval
    let lastMessage: CommunityMessage?
}
struct CommunityLogin: Decodable { let token: String; let userId: String }
struct CommunityAppleChallenge: Decodable { let challengeId: String; let nonce: String }
struct CommunitySendResult: Decodable { let threadId: String; let pushStatus: String; let messageId: String? }
struct CommunityAPIError: LocalizedError {
    let code: String
    var errorDescription: String? {
        switch code {
        case "not_configured": return String(localized: "提醒服務尚未設定，暫時無法連線。")
        case "incompatible_server": return String(localized: "此網址不是相容的 Gorilla 服務，請檢查網址或更新 Windows 後端。")
        case "server_changed": return String(localized: "服務網址已更改，請在目前服務重新操作。")
        case "not_found": return String(localized: "服務不支援此操作，請先更新 Windows 後端。")
        case "apple_unavailable": return String(localized: "Apple 登入服務暫未就緒，請更新 Windows 後端並設定 Apple 登入金鑰。")
        case "apple_verification_failed": return String(localized: "Apple 身分驗證未通過，請重新登入。")
        case "apple_challenge_expired": return String(localized: "Apple 登入要求已過期，請再試一次。")
        case "apple_already_linked": return String(localized: "此 Apple 帳戶或目前帳戶已連結其他身分，不能自動合併。")
        case "recent_login_required": return String(localized: "為保護帳戶，請先重新驗證電郵登入，再連結 Apple。")
        case "sign_in_required": return String(localized: "請先登入，或重新登入。")
        case "recipient_unavailable": return String(localized: "此車牌目前沒有可接收提醒的用戶。")
        case "thread_unavailable": return String(localized: "此對話已過期，或你已無法存取。")
        case "invalid_or_expired_code": return String(localized: "驗證碼錯誤或已過期，請重新申請。")
        case "rate_limited": return String(localized: "操作太頻密，請稍後再試。")
        case "plate_limit_reached": return String(localized: "每個帳號最多綁定 20 個車牌，請先解除不再使用的車牌。")
        case "invalid_request": return String(localized: "輸入內容不符合格式，請檢查車牌或訊息長度。")
        case "email_unavailable": return String(localized: "驗證電郵暫時無法寄出，請稍後再試。")
        case "keychain_unavailable": return String(localized: "無法安全儲存登入資料，請重試。")
        default: return String(localized: "暫時未能完成操作，請稍後再試。")
        }
    }
}

private enum CommunityCredentials {
    static let service = "GorillaLeading.ParkingCommunity"
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String?, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        if let value {
            var item = query
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw CommunityAPIError(code: "keychain_unavailable")
            }
        }
    }
}

private final class CommunityRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class CommunityHTTPClient: Sendable {
    static let transport = URLSession(configuration: .ephemeral, delegate: CommunityRedirectPolicy(), delegateQueue: nil)
    private let session: URLSession
    /// Debug builds may store a temporary server address in-app so a new tunnel
    /// host applies without rebuilding; an empty value falls back to the plist.
    static let overrideKey = "parkingCommunity.apiBaseURLOverride"
    private let fixedBaseURL: URL?
    // Resolved per call so a saved override applies without recreating clients.
    var baseURL: URL? { fixedBaseURL ?? CommunityHTTPClient.configuredURL }
    // Separate credentials by API origin, including developer environments.
    private var credentialKey: String { baseURL?.absoluteString ?? "unconfigured" }
    var signedIn: Bool { token != nil }
    private var token: String? { CommunityCredentials.read(credentialKey) }
    private var userID: String? { CommunityCredentials.read(credentialKey + ":user") }
    private var ownershipKey: String { "parkingCommunity.ownership:" + credentialKey + ":" + (userID ?? "legacy") }
    private func remember(_ id: String?, kind: String) {
        guard let id, !id.isEmpty else { return }
        let key = ownershipKey + ":" + kind
        var values = UserDefaults.standard.stringArray(forKey: key) ?? []
        values.removeAll { $0 == id }; values.append(id)
        UserDefaults.standard.set(Array(values.suffix(300)), forKey: key)
    }
    private func remembers(_ id: String, kind: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: ownershipKey + ":" + kind) ?? []).contains(id)
    }
    init(baseURL: URL? = nil, session: URLSession = CommunityHTTPClient.transport) {
        self.fixedBaseURL = baseURL; self.session = session
    }
    static func validated(_ address: String) -> URL? {
        guard let url = URL(string: address), url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        if url.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "") { return url }
        #endif
        return nil
    }
    static func normalized(_ address: String) -> URL? {
        guard let url = validated(address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.isEmpty || path == "v1/parking-community" else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.path = "/v1/parking-community"
        return parts?.url
    }
    static func verifyServer(_ address: String, session: URLSession = CommunityHTTPClient.transport) async throws -> URL {
        guard let url = normalized(address) else { throw CommunityAPIError(code: "not_configured") }
        let capabilities = try await CommunityHTTPClient(baseURL: url, session: session).capabilities()
        guard capabilities.service == "gorilla-parking-community", capabilities.apiVersion == 1 else {
            throw CommunityAPIError(code: "incompatible_server")
        }
        return url
    }
    static var configuredURL: URL? {
        var address = Bundle.main.object(forInfoDictionaryKey: "ParkingCommunityAPIBaseURL") as? String ?? ""
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["GORILLA_COMMUNITY_API_URL"] { address = override }
        #endif
        let defaults = UserDefaults.standard
        let migrationKey = "parkingCommunity.namedTunnelMigrated.v1"
        if normalized(address)?.absoluteString == "https://api.lucidtelos.com/v1/parking-community",
           !defaults.bool(forKey: migrationKey) {
            // Retire the old temporary endpoint once. Keep other custom servers,
            // and allow a developer to explicitly choose a Quick Tunnel later.
            let old = defaults.string(forKey: overrideKey) ?? ""
            if let host = validated(old)?.host?.lowercased(), host.hasSuffix(".trycloudflare.com") {
                defaults.removeObject(forKey: overrideKey)
            }
            defaults.set(true, forKey: migrationKey)
        }
        let override = defaults.string(forKey: overrideKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty { return validated(override) }
        return validated(address)
    }
    func clearSession() {
        try? CommunityCredentials.write(nil, account: credentialKey)
        try? CommunityCredentials.write(nil, account: credentialKey + ":user")
    }
    private func request(_ method: String, _ path: String, body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Data {
        guard let baseURL else { throw CommunityAPIError(code: "not_configured") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let token = CommunityCredentials.read(baseURL.absoluteString) else { throw CommunityAPIError(code: "sign_in_required") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw CommunityAPIError(code: payload?["error"] as? String ?? "server_error")
        }
        return data
    }
    func capabilities() async throws -> CommunityCapabilities {
        try JSONDecoder().decode(CommunityCapabilities.self, from: await request("GET", "capabilities", authenticated: false))
    }
    func registerDevice(id: String, token: String, environment: String) async throws {
        _ = try await request("PUT", "me/devices/\(id)", body: ["provider": "apns", "token": token, "environment": environment])
    }
    func startLogin(email: String) async throws {
        _ = try await request("POST", "auth/start", body: ["email": email], authenticated: false)
    }
    func verify(email: String, code: String) async throws {
        let origin = credentialKey
        let previousToken = token
        let data = try await request("POST", "auth/verify", body: ["email": email, "code": code], authenticated: false)
        let login = try JSONDecoder().decode(CommunityLogin.self, from: data)
        guard origin == credentialKey, previousToken == token else { throw CommunityAPIError(code: "server_changed") }
        try CommunityCredentials.write(login.token, account: origin)
        try CommunityCredentials.write(login.userId, account: origin + ":user")
    }
    func restoreIdentity() async {
        guard signedIn, userID == nil else { return }
        let origin = credentialKey
        struct Identity: Decodable { let userId: String }
        if let data = try? await request("GET", "me/session"), let identity = try? JSONDecoder().decode(Identity.self, from: data), origin == credentialKey {
            try? CommunityCredentials.write(identity.userId, account: origin + ":user")
        }
    }
    func appleChallenge(linking: Bool) async throws -> CommunityAppleChallenge {
        try JSONDecoder().decode(CommunityAppleChallenge.self, from: await request("POST", "auth/apple/challenge",
            body: ["purpose": linking ? "link" : "login"], authenticated: linking))
    }
    func signInWithApple(challenge: CommunityAppleChallenge, identityToken: String, authorizationCode: String, linking: Bool) async throws {
        let origin = credentialKey
        let previousToken = token
        let data = try await request("POST", "auth/apple", body: ["challengeId": challenge.challengeId,
            "identityToken": identityToken, "authorizationCode": authorizationCode], authenticated: linking)
        let login = try JSONDecoder().decode(CommunityLogin.self, from: data)
        guard origin == credentialKey, previousToken == token else { throw CommunityAPIError(code: "server_changed") }
        try CommunityCredentials.write(login.token, account: origin)
        try CommunityCredentials.write(login.userId, account: origin + ":user")
    }
    func recipientAvailable(_ plate: String) async throws -> Bool {
        struct Availability: Decodable { let available: Bool }
        return try JSONDecoder().decode(Availability.self, from: await request("POST", "plates/lookup", body: ["plate": plate])).available
    }
    func logout() async throws { _ = try await request("POST", "auth/logout"); clearSession() }
    func deleteAccount() async throws { _ = try await request("DELETE", "me"); clearSession() }
    func bindings() async throws -> [CommunityPlateDraft] {
        struct Response: Decodable { let plates: [CommunityPlateDraft] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: await request("GET", "me/plates")).plates
    }
    func bind(_ plate: String) async throws { _ = try await request("POST", "me/plates", body: ["plate": plate, "authorisedDriver": true]) }
    func unbind(_ plate: String) async throws { _ = try await request("DELETE", "me/plates/" + HKCommunityPlate.key(plate)) }
    func threads() async throws -> [CommunityThread] {
        struct Response: Decodable { let threads: [CommunityThread] }
        return try JSONDecoder().decode(Response.self, from: await request("GET", "threads")).threads.map {
            CommunityThread(id: $0.id, plate: $0.plate, expiresAt: $0.expiresAt, lastMessage: $0.lastMessage.map(resolved))
        }
    }
    private func resolved(_ row: CommunityMessage) -> CommunityMessage {
        CommunityMessage(id: row.id, authorId: row.authorId, text: row.text, createdAt: row.createdAt,
            mine: row.mine ?? (row.authorId == userID || remembers(row.id, kind: "messages")))
    }
    func messages(_ thread: String) async throws -> [CommunityMessage] {
        let origin = credentialKey
        struct Response: Decodable { let messages: [CommunityMessage] }
        let rows = try JSONDecoder().decode(Response.self, from: await request("GET", "threads/\(thread)/messages")).messages
        guard origin == credentialKey else { throw CommunityAPIError(code: "server_changed") }
        if userID == nil, remembers(thread, kind: "threads"), let first = rows.first {
            try? CommunityCredentials.write(first.authorId, account: credentialKey + ":user")
        }
        return rows.map(resolved)
    }
    func send(plate: String, text: String, key: UUID) async throws -> CommunitySendResult {
        let origin = credentialKey
        let result = try JSONDecoder().decode(CommunitySendResult.self, from: await request("POST", "threads", body: ["plate": plate, "text": text, "idempotencyKey": key.uuidString]))
        guard origin == credentialKey else { throw CommunityAPIError(code: "server_changed") }
        remember(result.threadId, kind: "threads"); remember(result.messageId, kind: "messages")
        return result
    }
    func reply(thread: String, text: String, key: UUID) async throws {
        let origin = credentialKey
        struct Reply: Decodable { let id: String }
        let result = try JSONDecoder().decode(Reply.self, from: await request("POST", "threads/\(thread)/messages", body: ["text": text, "idempotencyKey": key.uuidString]))
        guard origin == credentialKey else { throw CommunityAPIError(code: "server_changed") }
        remember(result.id, kind: "messages")
    }
    func report(thread: String) async throws {
        _ = try await request("POST", "threads/\(thread)/reports", body: ["reason": "用戶舉報不當訊息"])
    }
    func block(user: String) async throws { _ = try await request("POST", "blocks", body: ["userId": user]) }
}

struct CommunityCapabilities: Decodable {
    struct Push: Decodable { let apns: Bool; let fcm: Bool }
    struct Auth: Decodable { let apple: Bool }
    let push: Push
    let service: String?
    let apiVersion: Int?
    let auth: Auth?
}
#if canImport(UIKit)
import UIKit
import UserNotifications

@MainActor final class CommunityPushCoordinator: ObservableObject {
    static let shared = CommunityPushCoordinator()
    @Published private(set) var status = String(localized: "正在檢查遠端推送設定…")
    @Published private(set) var registered = false
    @Published var pendingThreadID: String?
    private var deviceToken: Data?
    private var registering = false
    private var requested = false
    private var available = false
    private let api = CommunityHTTPClient()
    static let openThread = Notification.Name("parkingCommunity.openThread")
    private var installationID: String {
        if let value = UserDefaults.standard.string(forKey: "parkingCommunity.installationID") { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: "parkingCommunity.installationID")
        return value
    }
    func sync() async {
        guard api.baseURL != nil else { status = String(localized: "提醒服務未設定。"); return }
        do {
            let capabilities = try await api.capabilities()
            available = capabilities.push.apns
            guard available else { registered = false; status = String(localized: "遠端推送等待 Apple 金鑰設定；可重新整理對話。"); return }
            guard api.signedIn else { registered = false; status = String(localized: "登入後可啟用手機推送。"); return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
                registered = false; status = String(localized: "請在此頁開啟通知權限，以接收手機提醒。"); return
            }
            if let deviceToken { await upload(deviceToken) }
            else if !requested { requested = true; status = String(localized: "正在登記手機推送…"); UIApplication.shared.registerForRemoteNotifications() }
        } catch { status = String(localized: "未能連接推送服務，請稍後重新整理。") }
    }
    func didRegister(_ token: Data) {
        deviceToken = token
        Task { await upload(token) }
    }
    func didFail() { requested = false; registered = false; status = String(localized: "手機推送登記未完成，請檢查網絡及簽署設定。") }
    private func upload(_ token: Data) async {
        guard available, api.signedIn, !registering else { return }
        registering = true
        defer { registering = false }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await api.registerDevice(id: installationID, token: token.map { String(format: "%02x", $0) }.joined(), environment: environment)
            registered = true; status = String(localized: "手機已登記推送；通知仍受網絡及系統設定影響。")
        } catch { registered = false; status = String(localized: "推送登記未完成，請重新整理重試。") }
    }
    func reset() { registered = false; requested = false; status = String(localized: "登入後可啟用手機推送。") }
    func route(threadID: String) {
        pendingThreadID = threadID
        NotificationCenter.default.post(name: Self.openThread, object: threadID)
    }
}
#endif
