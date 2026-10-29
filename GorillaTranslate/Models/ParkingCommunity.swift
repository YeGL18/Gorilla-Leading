import Foundation
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
    static func standardCandidate(_ value: String) -> String? {
        let compact = value.uppercased().components(separatedBy: .whitespacesAndNewlines).joined()
        guard compact.range(of: "^[A-HJ-NPR-Z]{1,2}[1-9][0-9]{0,3}$", options: .regularExpression) != nil else { return nil }
        return compact
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
    private let defaults: UserDefaults
    private let storageKey = "parkingCommunity.plateDrafts.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        drafts = (defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([CommunityPlateDraft].self, from: $0) }) ?? []
    }
    func saveDraft(_ plate: String) {
        guard HKCommunityPlate.isValid(plate), !drafts.contains(where: { $0.id == HKCommunityPlate.key(plate) }) else { return }
        drafts.append(.init(plate: plate, consentedAt: Date()))
        persist()
    }
    func remove(_ id: String) { drafts.removeAll { $0.id == id }; persist() }
    private func persist() { defaults.set(try? JSONEncoder().encode(drafts), forKey: storageKey) }
}

/// Platform-neutral API boundary. Implementations must authenticate on the server.
protocol ParkingCommunityAPI {
    func bindings() async throws -> [CommunityPlateDraft]
    func bind(plate: String, consentedAt: Date) async throws
    func unbind(plateKey: String) async throws
    func send(plate: String, text: String, idempotencyKey: UUID) async throws -> UUID
    func reply(threadID: UUID, text: String, idempotencyKey: UUID) async throws
}
