import Foundation

@main struct ParkingCommunityChecks {
    @MainActor static func main() {
        precondition(HKCommunityPlate.standardCandidate("AB 1234") == "AB1234")
        precondition(HKCommunityPlate.standardCandidate("AB\n1234") == "AB1234")
        for invalid in ["AB0123", "AB12345", "ABC123", "AI123", "AQ123", "AB-123", "AB123!", "BILL"] {
            precondition(HKCommunityPlate.standardCandidate(invalid) == nil, invalid)
        }
        precondition(HKCommunityPlate.isValid("MY CAR 8"))
        precondition(!HKCommunityPlate.isValid("I LOVE U"))
        precondition(!HKCommunityPlate.isValid("AB-123"))
        precondition(!HKCommunityPlate.isValid("         "))
        precondition(!HKCommunityPlate.isValid("ABCDEFGH8"))
        precondition(HKCommunityPlate.key("AB 1234") == HKCommunityPlate.key("AB1234"))
        let suite = "ParkingCommunityChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ParkingCommunityStore(defaults: defaults)
        store.saveDraft("AB 1234")
        store.saveDraft("AB1234")
        store.saveDraft("BAD!")
        precondition(store.drafts.count == 1)
        let restored = ParkingCommunityStore(defaults: defaults)
        precondition(restored.drafts.first?.plate == "AB 1234")
        restored.remove("AB1234")
        precondition(ParkingCommunityStore(defaults: defaults).drafts.isEmpty)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let binding = try! decoder.decode(CommunityPlateDraft.self, from: Data(#"{"plate":"AB 1234","consentedAt":"2027-01-15T08:00:00Z"}"#.utf8))
        precondition(binding.id == "AB1234")
        let thread = try! JSONDecoder().decode(CommunityThread.self, from: Data(#"{"id":"thread","plate":"AB1234","expiresAt":1800604800.0,"lastMessage":{"id":"msg","authorId":"driver","text":"唔該","createdAt":1800000000.0}}"#.utf8))
        precondition(thread.lastMessage?.text == "唔該")
        print("Parking community plate and draft persistence checks passed")
    }
}
