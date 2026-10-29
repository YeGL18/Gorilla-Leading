import Foundation

@main struct ParkingCommunityChecks {
    @MainActor static func main() {
        precondition(HKCommunityPlate.standardCandidate("AB 1234") == "AB1234")
        precondition(HKCommunityPlate.standardCandidate("ＡＢ１２３４") == "AB1234")
        precondition(HKCommunityPlate.standardCandidate("18") == "18")
        func segment(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CommunityOCRSegment {
            .init(text: text, bounds: CGRect(x: x, y: y, width: w, height: h))
        }
        let sideBySide = CommunityPlateOCR.candidates([
            segment("AB", 10, 10, 40, 20), segment("1234", 58, 10, 70, 20)])
        precondition(sideBySide.map(\.plate) == ["AB1234"])
        let groupedDigits = CommunityPlateOCR.candidates([
            segment("AB", 10, 10, 40, 20), segment("12", 58, 10, 30, 20), segment("34", 94, 10, 30, 20)])
        precondition(groupedDigits.map(\.plate) == ["AB1234"])
        let closeDigitGroups = CommunityPlateOCR.candidates([
            segment("AB", 10, 10, 40, 20), segment("12", 55, 10, 25, 20), segment("34", 85, 10, 25, 20)])
        precondition(closeDigitGroups.map(\.plate) == ["AB1234"])
        let twoLine = CommunityPlateOCR.candidates([
            segment("AB", 35, 10, 40, 20), segment("1234", 20, 35, 70, 20)])
        precondition(twoLine.map(\.plate) == ["AB1234"])
        let unrelated = CommunityPlateOCR.candidates([
            segment("AB", 10, 10, 40, 20), segment("1234", 300, 90, 70, 20)])
        precondition(!unrelated.contains { $0.plate == "AB1234" })
        let invalidPrefix = CommunityPlateOCR.candidates([
            segment("ABC", 10, 10, 40, 20), segment("1234", 58, 10, 70, 20)])
        precondition(!invalidPrefix.contains { $0.plate == "ABC1234" })
        var hold = CommunityOCRHold()
        let now = Date(timeIntervalSince1970: 100)
        precondition(hold.update(["AB1234"], now: now) == ["AB1234"])
        precondition(hold.update([], now: now.addingTimeInterval(2)) == ["AB1234"])
        precondition(hold.update([], now: now.addingTimeInterval(4)).isEmpty)
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
