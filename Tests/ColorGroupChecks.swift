import Foundation

@main
enum ColorGroupChecks {
    static func main() {
        precondition(GorillaColorGroup.allCases.count == 3)
        precondition(M3ConceptPalette.all == ["EF363B", "DDD11B", "E6EFEA", "5C575D", "0D0B0E"])
        precondition(M3ConceptPalette.homeOrbs.map(\.hex) == [M3ConceptPalette.orange, M3ConceptPalette.yellow, "00172D"])
        precondition(M3ConceptPalette.homeOrbMixing)
        precondition(GorillaColorGroup.resolve(raw: -1, legacyDarkKnight: true) == .darkKnight)
        precondition(GorillaColorGroup.resolve(raw: -1, legacyDarkKnight: false) == .normal)
        precondition(GorillaColorGroup.resolve(raw: 2, legacyDarkKnight: true) == .m3Concept)
        precondition(GorillaColorGroup.resolve(raw: 0, legacyDarkKnight: true) == .normal)
        precondition(GorillaColorGroup.normal.showsOrbControls)
        precondition(GorillaColorGroup.m3Concept.showsOrbControls)
        precondition(!GorillaColorGroup.darkKnight.showsOrbControls)
        for group in GorillaColorGroup.allCases {
            precondition(!group.orbsEnabled(master: false, surface: true))
            precondition(!group.orbsEnabled(master: true, surface: false))
            precondition(group.orbsEnabled(master: true, surface: true) == (group != .darkKnight))
        }
        precondition(GorillaColorGroup.darkKnight.usesSpecialMap)
        precondition(!GorillaColorGroup.m3Concept.usesSpecialMap)
        precondition(!GorillaColorGroup.normal.usesSpecialMap)
        for preset in 0...4 {
            for speed in [0.0, 30, 100, 150, 200, 240, .nan, .infinity] {
                precondition(GorillaColorGroup.m3Concept.dotColorHex(speed: speed, preset: preset) == "#" + M3ConceptPalette.orange)
            }
            precondition(GorillaColorGroup.darkKnight.dotColorHex(speed: 100, preset: preset) == "#FFC46D")
            precondition(GorillaColorGroup.darkKnight.dotColorHex(speed: 200, preset: preset) == "#FF4500")
        }
        precondition(GorillaColorGroup.darkKnight.dotColorHex(speed: 150, preset: 0) == "#FF8436")
        precondition(GorillaColorGroup.normal.dotColorHex(speed: 200, preset: 0) == "#ffd700")
        precondition(GorillaColorGroup.normal.dotColorHex(speed: 30, preset: 1) == "#FF8C00")
        precondition(GorillaColorGroup.normal.dotColorHex(speed: 75, preset: 1) == "#FF6B00")
        precondition(GorillaColorGroup.normal.dotColorHex(speed: 120, preset: 1) == "#FF4500")
        let suite = "gorilla-color-groups-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "darkKnightMode")
        defaults.set(4, forKey: "orbColorPreset")
        precondition(GorillaColorGroup.load(defaults) == .darkKnight)
        for group in GorillaColorGroup.allCases {
            defaults.set(group.rawValue, forKey: "colorGroupMode")
            precondition(GorillaColorGroup.load(defaults) == group)
            precondition(defaults.integer(forKey: "orbColorPreset") == 4)
        }
        print("PASS: three exclusive groups; legacy preferences; normal dot presets; independent speed-based Dark Knight dots; fixed M3 dots; normal M3 map; preserved orb preferences")
    }
}
