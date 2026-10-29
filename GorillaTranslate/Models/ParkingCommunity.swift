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
            let fetchedPlates = try await api.bindings()
            let fetchedThreads = try await api.threads()
            guard refreshGeneration == generation, api.signedIn else { return }
            boundPlates = fetchedPlates
            threads = fetchedThreads
        } catch { if refreshGeneration == generation { handle(error) } }
    }
    func handle(_ error: Error) {
        if let error = error as? CommunityAPIError, error.code == "sign_in_required" {
            api.clearSession(); signedIn = false; boundPlates = []; threads = []
        }
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

struct CommunityMessage: Decodable, Identifiable {
    let id: String
    let authorId: String
    let text: String
    let createdAt: TimeInterval
}
struct CommunityThread: Decodable, Identifiable {
    let id: String
    let plate: String
    let expiresAt: TimeInterval
    let lastMessage: CommunityMessage?
}
struct CommunityLogin: Decodable { let token: String; let userId: String }
struct CommunitySendResult: Decodable { let threadId: String; let pushStatus: String }
struct CommunityAPIError: LocalizedError {
    let code: String
    var errorDescription: String? {
        switch code {
        case "not_configured": return "提醒服務尚未設定，暫時無法連線。"
        case "sign_in_required": return "請先登入，或重新登入。"
        case "recipient_unavailable": return "此車牌目前沒有可接收提醒的用戶。"
        case "thread_unavailable": return "此對話已過期，或你已無法存取。"
        case "invalid_or_expired_code": return "驗證碼錯誤或已過期，請重新申請。"
        case "rate_limited": return "操作太頻密，請稍後再試。"
        case "plate_limit_reached": return "每個帳號最多綁定 20 個車牌，請先解除不再使用的車牌。"
        case "invalid_request": return "輸入內容不符合格式，請檢查車牌或訊息長度。"
        case "email_unavailable": return "驗證電郵暫時無法寄出，請稍後再試。"
        case "keychain_unavailable": return "無法安全儲存登入資料，請重試。"
        default: return "暫時未能完成操作，請稍後再試。"
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

final class CommunityHTTPClient: Sendable {
    let baseURL: URL?
    // Separate credentials by API origin, including developer environments.
    private var credentialKey: String { baseURL?.absoluteString ?? "unconfigured" }
    var signedIn: Bool { token != nil }
    private var token: String? { CommunityCredentials.read(credentialKey) }
    init(baseURL: URL? = CommunityHTTPClient.configuredURL) { self.baseURL = baseURL }
    static var configuredURL: URL? {
        var address = Bundle.main.object(forInfoDictionaryKey: "ParkingCommunityAPIBaseURL") as? String ?? ""
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["GORILLA_COMMUNITY_API_URL"] { address = override }
        #endif
        guard let url = URL(string: address), url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        if url.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "") { return url }
        #endif
        return nil
    }
    func clearSession() { try? CommunityCredentials.write(nil, account: credentialKey) }
    private func request(_ method: String, _ path: String, body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Data {
        guard let baseURL else { throw CommunityAPIError(code: "not_configured") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let token else { throw CommunityAPIError(code: "sign_in_required") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let data = try await request("POST", "auth/verify", body: ["email": email, "code": code], authenticated: false)
        let login = try JSONDecoder().decode(CommunityLogin.self, from: data)
        try CommunityCredentials.write(login.token, account: credentialKey)
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
        return try JSONDecoder().decode(Response.self, from: await request("GET", "threads")).threads
    }
    func messages(_ thread: String) async throws -> [CommunityMessage] {
        struct Response: Decodable { let messages: [CommunityMessage] }
        return try JSONDecoder().decode(Response.self, from: await request("GET", "threads/\(thread)/messages")).messages
    }
    func send(plate: String, text: String, key: UUID) async throws -> CommunitySendResult {
        try JSONDecoder().decode(CommunitySendResult.self, from: await request("POST", "threads", body: ["plate": plate, "text": text, "idempotencyKey": key.uuidString]))
    }
    func reply(thread: String, text: String, key: UUID) async throws {
        _ = try await request("POST", "threads/\(thread)/messages", body: ["text": text, "idempotencyKey": key.uuidString])
    }
    func report(thread: String) async throws {
        _ = try await request("POST", "threads/\(thread)/reports", body: ["reason": "用戶舉報不當訊息"])
    }
    func block(user: String) async throws { _ = try await request("POST", "blocks", body: ["userId": user]) }
}

struct CommunityCapabilities: Decodable {
    struct Push: Decodable { let apns: Bool; let fcm: Bool }
    let push: Push
}
#if canImport(UIKit)
import UIKit
import UserNotifications

@MainActor final class CommunityPushCoordinator: ObservableObject {
    static let shared = CommunityPushCoordinator()
    @Published private(set) var status = "正在檢查遠端推送設定…"
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
        guard api.baseURL != nil else { status = "提醒服務未設定。"; return }
        do {
            let capabilities = try await api.capabilities()
            available = capabilities.push.apns
            guard available else { registered = false; status = "遠端推送等待 Apple 金鑰設定；可重新整理對話。"; return }
            guard api.signedIn else { registered = false; status = "登入後可啟用手機推送。"; return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
                registered = false; status = "請在此頁開啟通知權限，以接收手機提醒。"; return
            }
            if let deviceToken { await upload(deviceToken) }
            else if !requested { requested = true; status = "正在登記手機推送…"; UIApplication.shared.registerForRemoteNotifications() }
        } catch { status = "未能連接推送服務，請稍後重新整理。" }
    }
    func didRegister(_ token: Data) {
        deviceToken = token
        Task { await upload(token) }
    }
    func didFail() { requested = false; registered = false; status = "手機推送登記未完成，請檢查網絡及簽署設定。" }
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
            registered = true; status = "手機已登記推送；通知仍受網絡及系統設定影響。"
        } catch { registered = false; status = "推送登記未完成，請重新整理重試。" }
    }
    func reset() { registered = false; requested = false; status = "登入後可啟用手機推送。" }
    func route(threadID: String) {
        pendingThreadID = threadID
        NotificationCenter.default.post(name: Self.openThread, object: threadID)
    }
}
#endif
