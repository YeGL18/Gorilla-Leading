import Foundation

@main
struct ACTelemetryChecks {
    static func main() {
        func put(_ value: UInt32, at offset: Int, into data: inout Data) {
            for index in 0..<4 { data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
        }
        var data = Data(repeating: 0, count: 328)
        data[0] = 97
        put(328, at: 4, into: &data)
        put(Float(123.5).bitPattern, at: 8, into: &data)
        put(Float(6500).bitPattern, at: 68, into: &data)
        put(4, at: 76, into: &data)
        put(83456, at: 40, into: &data)
        put(2, at: 52, into: &data)
        put(Float(0.65).bitPattern, at: 56, into: &data)
        put(Float(0.2).bitPattern, at: 60, into: &data)
        put(Float(-0.29).bitPattern, at: 32, into: &data)
        put(Float(0.4).bitPattern, at: 36, into: &data)
        let sample = ACPacket.car(data)!
        precondition(sample.speed == 123.5 && sample.rpm == 6500)
        precondition(sample.gearLabel == "3" && sample.lap == 2)
        precondition(abs(sample.gForce!.lateral + 0.29) < 0.0001 && abs(sample.gForce!.longitudinal - 0.4) < 0.0001)
        precondition(abs(sample.throttle - 0.65) < 0.0001 && abs(sample.brake - 0.2) < 0.0001)
        precondition(ACPacket.lapTime(sample.currentLap) == "1:23.456")
        precondition(ACPacket.lapTime(0) == "—")
        for (gear, expected) in [(0, "R"), (1, "N"), (2, "1")] {
            put(UInt32(gear), at: 76, into: &data)
            precondition(ACPacket.car(data)?.gearLabel == expected)
        }
        precondition(ACPacket.car(Data(data.prefix(80))) == nil)
        var invalid = data
        put(Float.nan.bitPattern, at: 32, into: &invalid)
        precondition(ACPacket.car(invalid)?.gForce == nil)
        precondition(ACPacket.car(invalid)?.speed == 123.5)
        invalid = data
        put(Float.nan.bitPattern, at: 8, into: &invalid)
        precondition(ACPacket.car(invalid) == nil)
        invalid = data
        put(Float.infinity.bitPattern, at: 60, into: &invalid)
        precondition(ACPacket.car(invalid) == nil)
        invalid = data
        put(Float(1.1).bitPattern, at: 56, into: &invalid)
        precondition(ACPacket.car(invalid) == nil)
        invalid = data
        put(UInt32.max, at: 76, into: &invalid)
        precondition(ACPacket.car(invalid) == nil)
        invalid = data
        put(327, at: 4, into: &invalid)
        precondition(ACPacket.car(invalid) == nil)

        var names = Data(repeating: 0, count: 408)
        put(4242, at: 200, into: &names)
        put(1, at: 204, into: &names)
        for (text, offset) in [("BMW M3", 0), ("Monza", 208), ("GP", 308)] {
            let encoded = text.data(using: .utf16LittleEndian)!
            names.replaceSubrange(offset..<(offset + encoded.count), with: encoded)
        }
        let decoded = ACPacket.names(names)!
        precondition(decoded.car == "BMW M3" && decoded.track == "Monza" && decoded.configuration == "GP")
        precondition(ACPacket.names(Data(names.prefix(400))) == nil)
        put(0, at: 200, into: &names)
        precondition(ACPacket.names(names) == nil)
        precondition(Array(ACPacket.command(1)) == [0,0,0,0,1,0,0,0,1,0,0,0])
        print("AC telemetry packet checks passed")
    }
}
