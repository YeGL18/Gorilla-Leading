import Foundation
import UIKit
import Vision

// MARK: - Recognition Result Model

struct ParkingRecognizedInfo: Codable, Equatable {
    /// All OCR raw lines joined together (primary display)
    /// e.g., "P1 B2 B1258" or "95 A-1 區"
    var displayText: String?

    /// Floor text extracted from OCR (for confirmation popup)
    /// e.g., "B2", "-2 樓", "地下二層"
    var floorText: String?

    /// Parsed floor index (negative = underground)
    /// e.g., B2 → -2, 3F → 3, LG → -1
    var floorIndex: Int?

    /// Filtered parking-relevant items only (for display)
    /// e.g., ["B2", "B1258", "P1"] — excludes noise
    var relevantItems: [String]

    /// All individual OCR raw results (for debug panel)
    var rawTexts: [String]

    /// When recognition completed
    var recognizedAt: Date?
}

// MARK: - Parking Spot Recognition Service

class ParkingSpotRecognizer {

    // MARK: - Public API

    static func recognize(from image: UIImage) async -> ParkingRecognizedInfo {
        guard let cgImage = image.cgImage else {
            return ParkingRecognizedInfo(
                displayText: nil, floorText: nil, floorIndex: nil,
                relevantItems: [], rawTexts: [], recognizedAt: Date()
            )
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ParkingRecognizedInfo(
                        displayText: nil, floorText: nil, floorIndex: nil,
                        relevantItems: [], rawTexts: [], recognizedAt: Date()
                    ))
                    return
                }

                // Collect all candidates (not just top 1) for better accuracy
                var allLines: [String] = []
                for obs in observations {
                    let candidates = obs.topCandidates(3)
                    if let best = candidates.first?.string {
                        allLines.append(best)
                    }
                }

                let info = Self.parseRecognizedText(allLines)
                continuation.resume(returning: info)
            }

            // Use .accurate for better recognition
            request.recognitionLevel = .accurate
            // Support mixed Chinese/English text
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en"]
            // Disable language correction — it can mangle parking codes like "B2-B1258"
            request.usesLanguageCorrection = false
            // Custom words to help recognition
            request.customWords = [
                "車位", "樓", "區", "地下", "停車場", "層",
                "B1", "B2", "B3", "B4", "B5",
                "LG", "UG", "P1", "P2", "P3", "P4",
            ]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: ParkingRecognizedInfo(
                    displayText: nil, floorText: nil, floorIndex: nil,
                    relevantItems: [], rawTexts: [], recognizedAt: Date()
                ))
            }
        }
    }

    // MARK: - Text Parsing

    /// Parse all OCR lines into a ParkingRecognizedInfo.
    /// Strategy: filter to parking-relevant items only, extract floor separately.
    static func parseRecognizedText(_ lines: [String]) -> ParkingRecognizedInfo {
        // Filter out empty lines
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Extract parking-relevant items only
        var relevantItems: [String] = []
        var floorText: String?
        var floorIndex: Int?

        for line in cleaned {
            // Check if it's a floor indicator
            if let parsed = Self.parseFloor(line) {
                floorText = parsed.text
                floorIndex = parsed.index
                relevantItems.append(parsed.text)
                continue
            }

            // Check if it's a compound code like "B2-B1258"
            if let parsed = Self.parseFloorFromCompound(line) {
                if floorIndex == nil {
                    floorText = parsed.text
                    floorIndex = parsed.index
                }
                relevantItems.append(line)
                continue
            }

            // Check if it's a parking spot number (pure digits, 1-5 chars)
            if Self.isSpotNumber(line) {
                relevantItems.append(line)
                continue
            }

            // Check if it's an area code (e.g., "P1", "A區", "A-1")
            if Self.isAreaCode(line) {
                relevantItems.append(line)
                continue
            }

            // Check if it contains parking-related keywords
            if Self.containsParkingKeyword(line) {
                relevantItems.append(line)
                continue
            }

            // Otherwise: unrelated noise, skip it
        }

        // If no relevant items found, fall back to showing all cleaned text
        let displayItems = relevantItems.isEmpty ? cleaned : relevantItems
        let displayText = displayItems.isEmpty ? nil : displayItems.joined(separator: " ")

        return ParkingRecognizedInfo(
            displayText: displayText,
            floorText: floorText,
            floorIndex: floorIndex,
            relevantItems: relevantItems,
            rawTexts: cleaned,
            recognizedAt: Date()
        )
    }

    // MARK: - Parking Relevance Checks

    /// Pure digits, 1-5 characters → likely a parking spot number
    private static func isSpotNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Pure digits, 1-5 chars
        if let regex = try? NSRegularExpression(pattern: "^\\d{1,5}$"),
           regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            return true
        }
        return false
    }

    /// Area code patterns: P1-P9, A-Z followed by digits, or "X區"
    private static func isAreaCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "P1"~"P9", "A1", "B1" etc.
        if let regex = try? NSRegularExpression(pattern: "^[A-Z]\\d{1,2}$"),
           regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            return true
        }
        // "A-1", "B-2" etc.
        if let regex = try? NSRegularExpression(pattern: "^[A-Z]-\\d{1,2}$"),
           regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            return true
        }
        // Contains "區"
        if trimmed.contains("區") {
            return true
        }
        return false
    }

    /// Contains parking-related Chinese/English keywords
    private static func containsParkingKeyword(_ text: String) -> Bool {
        let keywords = ["車位", "停車", "泊車", "樓", "層", "地下", "區域", "zone", "parking", "floor"]
        let lower = text.lowercased()
        for kw in keywords {
            if lower.contains(kw.lowercased()) {
                return true
            }
        }
        return false
    }

    // MARK: - Floor Parsing (from standalone text like "B2", "-2 樓")

    /// Returns (displayText, floorIndex) or nil
    private static func parseFloor(_ text: String) -> (text: String, index: Int)? {
        let patterns: [(pattern: String, transform: (NSTextCheckingResult, String) -> (String, Int)?)] = [
            // "B2" / "B2F" / "B02" (standalone or with context)
            ("\\b[Bb]\\s*(\\d{1,2})[Ff]?\\b", { match, full in
                guard let range = Range(match.range(at: 1), in: full) else { return nil }
                let numStr = String(full[range])
                guard let num = Int(numStr), num > 0, num <= 20 else { return nil }
                return ("B\(num)", -num)
            }),
            // "-2 樓" / "-2樓"
            ("(-?)\\s*(\\d+)\\s*樓", { match, full in
                guard let numRange = Range(match.range(at: 2), in: full) else { return nil }
                let numStr = String(full[numRange])
                guard let num = Int(numStr), num > 0, num <= 20 else { return nil }
                let hasMinus = match.range(at: 1).length > 0
                let isUnderground = hasMinus || full.contains("地下")
                let index = isUnderground ? -num : num
                return ("\(index) 樓", index)
            }),
            // "地下2層" / "地下二層"
            ("地下\\s*(\\d+)\\s*層", { match, full in
                guard let range = Range(match.range(at: 1), in: full) else { return nil }
                let numStr = String(full[range])
                guard let num = Int(numStr), num > 0 else { return nil }
                return ("地下\(num)層", -num)
            }),
            // "LG" / "LG1" / "LG2"
            ("\\b[Ll][Gg]\\s*(\\d*)\\b", { match, full in
                guard let range = Range(match.range(at: 1), in: full) else { return nil }
                let numStr = String(full[range])
                let num = numStr.isEmpty ? 1 : (Int(numStr) ?? 1)
                return ("LG\(num > 1 ? "\(num)" : "")", -num)
            }),
            // "UG" / "UG1"
            ("\\b[Uu][Gg]\\s*(\\d*)\\b", { match, full in
                guard let range = Range(match.range(at: 1), in: full) else { return nil }
                let numStr = String(full[range])
                let num = numStr.isEmpty ? 1 : (Int(numStr) ?? 1)
                return ("UG\(num > 1 ? "\(num)" : "")", -num)
            }),
            // "2F" / "3F" (standalone, ends with F)
            ("^(\\d{1,2})\\s*[Ff]$", { match, full in
                guard let range = Range(match.range(at: 1), in: full) else { return nil }
                let numStr = String(full[range])
                guard let num = Int(numStr), num > 0, num <= 20 else { return nil }
                return ("\(num)F", num)
            }),
            // "G" / "G1" / "G2" (ground floor, standalone)
            ("^[Gg](\\d*)$", { match, full in
                guard let range = Range(match.range(at: 1), in: full) else { return nil }
                let numStr = String(full[range])
                let num = numStr.isEmpty ? 0 : (Int(numStr) ?? 0)
                return ("G\(num > 0 ? "\(num)" : "")", num)
            }),
        ]

        for (pattern, transform) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                if let result = transform(match, text) {
                    return result
                }
            }
        }

        return nil
    }

    // MARK: - Floor Parsing from compound strings like "B2-B1258"

    /// Extracts floor from compound parking spot codes.
    /// e.g., "B2-B1258" → floor B2 (index -2)
    private static func parseFloorFromCompound(_ text: String) -> (text: String, index: Int)? {
        // Pattern: starts with B + number, then dash or space, then more text
        // e.g., "B2-B1258", "B1-A001", "B3 125"
        let pattern = "^[Bb](\\d{1,2})[-\\s]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let numStr = String(text[range])
        guard let num = Int(numStr), num > 0, num <= 20 else { return nil }
        return ("B\(num)", -num)
    }
}
