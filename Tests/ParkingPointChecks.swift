import Foundation
import CoreLocation

// Compile with ParkingPointRecord extracted from LocationManager.swift.
// Only the unrelated floor presentation dependency is stubbed here.
enum ParkingFloorStore {
    static func cleanFloorText(_ text: String?, coordinate: CLLocationCoordinate2D?) -> String? { text }
    static func formatFloor(_ floor: Int, coordinate: CLLocationCoordinate2D?) -> String { String(floor) }
}

@main
struct ParkingPointChecks {
    static func main() throws {
        for kind in ["confirmed", "estimated"] {
            var point = ParkingPointRecord(
                id: UUID(), address: "HKMU", latitude: 22.316, longitude: 114.18,
                createdAt: Date(), manualFloorIndex: 2, llmSpotNumber: "A12",
                meterID: kind == "confirmed" ? "7802A" : nil,
                meterStreet: "Test Street", meterMatchKind: kind
            )
            let original = point
            precondition(point.meterTag != nil)
            point.removeMeterAnnotation()
            precondition(point.meterTag == nil)
            precondition(point.meterID == nil && point.meterStreet == nil && point.meterMatchKind == nil)
            precondition(point.id == original.id && point.createdAt == original.createdAt)
            precondition(point.latitude == original.latitude && point.longitude == original.longitude)
            precondition(point.address == original.address && point.manualFloorIndex == 2 && point.llmSpotNumber == "A12")
            let restored = try JSONDecoder().decode(ParkingPointRecord.self, from: JSONEncoder().encode(point))
            precondition(restored == point && restored.meterTag == nil)
            point.removeMeterAnnotation()
            precondition(point == restored)
        }
        print("PASS: confirmed/estimated meter removal preserves parking memory and survives storage")
    }
}
