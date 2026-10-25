import Foundation

@main
struct SpeedUnitChecks {
    static func main() {
        func near(_ value: Double, _ expected: Double) { precondition(abs(value - expected) < 0.000001) }
        let kmh = SpeedUnit.kilometresPerHour
        let mph = SpeedUnit.milesPerHour
        precondition(SpeedUnit.resolve(nil) == kmh)
        precondition(SpeedUnit.resolve("invalid") == kmh)
        precondition(SpeedUnit.resolve("mph") == mph)
        near(kmh.value(fromKmh: 100), 100)
        near(mph.value(fromKmh: 1.609344), 1)
        near(mph.value(fromKmh: 96.56064), 60)
        precondition(Int(mph.value(fromKmh: 42)) == 26)
        precondition(Int(mph.value(fromKmh: 123)) == 76)
        near(mph.value(fromKmh: -1), 0)
        near(mph.value(fromKmh: .nan), 0)
        near(kmh.value(fromKmh: .infinity), 0)
        precondition(kmh.symbol == "km/h" && mph.symbol == "mph")
        print("PASS: km/h and mph conversion, defaults, invalid input and display units")
    }
}
