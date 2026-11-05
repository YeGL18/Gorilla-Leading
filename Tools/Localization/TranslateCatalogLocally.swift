import Foundation
import Translation

/// Developer-only catalog generation. TranslationSession processes text on-device.
/// Uses installed models only; never requests downloads or calls an HTTP service.
@main struct TranslateCatalogLocally {
    struct Input: Decodable { let strings: [String: String]; let info: [String: String] }
    struct Work: Decodable { let language: String; let existing: [String: String] }
    static let tokenPattern = #"https?://[^\s]+|[\w.+-]+@[\w.-]+\.[A-Za-z]+|%(?:\d+\$)?[-+0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hljztL])?[@diuoxXfFeEgGaAcCsSp%]|Gorilla Leading|M3 Concept|Assetto Corsa|\n"#

    static func protectedText(_ source: String) -> AttributedString {
        let regex = try! NSRegularExpression(pattern: tokenPattern)
        let ns = source as NSString
        var result = AttributedString()
        var start = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            if start < match.range.location { result.append(AttributedString(ns.substring(with: NSRange(location: start, length: match.range.location - start)))) }
            var protected = AttributedString(ns.substring(with: match.range))
            protected.translation.skipsTranslation = true
            result.append(protected)
            start = match.range.location + match.range.length
        }
        if start < ns.length { result.append(AttributedString(ns.substring(from: start))) }
        return result
    }
    static func tokens(_ text: String) -> [String] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: tokenPattern)
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }.sorted()
    }
    static func save(_ values: [String: String], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else { fatalError("Usage: localize <input.json> <work.json> <output-directory> [maximum-new-strings]") }
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let work = try JSONDecoder().decode([Work].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let output = URL(fileURLWithPath: args[3], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let all = input.strings.merging(input.info) { first, _ in first }
        let maximum = args.count > 4 ? Int(args[4]) ?? .max : .max
        let protectedNames: Set<String> = ["Gorilla", "Gorilla Leading", "M3 Concept", "Assetto Corsa", "Foundation Models", "Apple Maps", "Apple Intelligence", "Siri", "VoiceOver", "Windows", "English", "繁體中文", "简体中文", "日本語", "G", "G-force", "GPS", "GPS · m", "km/h", "m", "RPM", "UDP", "B2", "A", "Sunrise-Sunset.org", "https://api.lucidtelos.com/v1/parking-community"]
        for task in work {
            let url = output.appendingPathComponent(task.language + ".json")
            var values = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
            values.merge(task.existing) { _, curated in curated }
            for (key, text) in all where values[key] == nil {
                if protectedNames.contains(text) || text.rangeOfCharacter(from: .letters) == nil { values[key] = text }
            }
            let pending = all.keys.sorted().filter { values[$0] == nil }.prefix(maximum)
            let target = Locale.Language(identifier: task.language == "yue" ? "zh-HK" : task.language)
            if args.contains("--wait-fast") && task.language != "ms" {
                while await LanguageAvailability(preferredStrategy: .lowLatency).status(from: .init(identifier: "en"), to: target) != .installed {
                    print("Waiting for installed local model: \(task.language)"); fflush(stdout)
                    try await Task.sleep(for: .seconds(10))
                }
            }
            let localFast = LanguageAvailability(preferredStrategy: .lowLatency)
            let strategy: TranslationSession.Strategy = await localFast.status(from: .init(identifier: "en"), to: target) == .installed ? .lowLatency : .highFidelity
            let availability = LanguageAvailability(preferredStrategy: strategy)
            guard await availability.status(from: .init(identifier: "en"), to: target) == .installed else {
                throw NSError(domain: "LocalCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "No installed on-device model for \(task.language)"])
            }
            let session = TranslationSession(installedSource: .init(identifier: "en"), target: target, preferredStrategy: strategy)
            var review: [String: String] = [:]
            let keys = Array(pending)
            for start in stride(from: 0, to: keys.count, by: 24) {
                let batch = Array(keys[start..<min(start + 24, keys.count)])
                var translatedValues: [String: String] = [:]
                if args.contains("--documents") {
                    var document = AttributedString()
                    for (index, key) in batch.enumerated() {
                        var marker = AttributedString("⟦\(index)⟧\n")
                        marker.translation.skipsTranslation = true
                        document.append(marker)
                        document.append(protectedText(all[key]!))
                        document.append(AttributedString("\n"))
                    }
                    let response = try await session.translate(document)
                    let text = response.targetText as NSString
                    let markers = try! NSRegularExpression(pattern: #"⟦\s*(\d+)\s*⟧"#).matches(in: response.targetText, range: NSRange(location: 0, length: text.length))
                    if markers.count == batch.count {
                        for (index, marker) in markers.enumerated() {
                            guard Int(text.substring(with: marker.range(at: 1))) == index else { continue }
                            let end = index + 1 < markers.count ? markers[index + 1].range.location : text.length
                            translatedValues[batch[index]] = text.substring(with: NSRange(location: marker.range.upperBound, length: end - marker.range.upperBound))
                        }
                    }
                }
                let missing = batch.filter { translatedValues[$0] == nil }
                if !missing.isEmpty {
                    let requests = missing.map { TranslationSession.Request(sourceText: protectedText(all[$0]!), clientIdentifier: $0) }
                    for response in try await session.translations(from: requests) {
                        if let key = response.clientIdentifier { translatedValues[key] = response.targetText }
                    }
                }
                for (key, raw) in translatedValues {
                    guard let original = all[key] else { continue }
                    let translated = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !translated.isEmpty && tokens(translated) == tokens(original) { values[key] = translated }
                    else { review[key] = translated; print("REVIEW \(task.language): \(key)") }
                }
                try save(values, to: url)
                if !review.isEmpty { try save(review, to: output.appendingPathComponent(task.language + ".review.json")) }
                print("\(Date()) \(task.language): \(min(start + 24, keys.count))/\(keys.count) new strings; \(values.count)/\(all.count) total")
                fflush(stdout)
            }
            try save(values, to: url)
            print("DONE \(task.language): \(values.count)/\(all.count)")
            fflush(stdout)
        }
    }
}
