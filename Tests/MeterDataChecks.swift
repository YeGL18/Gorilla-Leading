import Foundation
import CoreLocation

@main
struct MeterDataChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let header = "PoleId,ParkingSpaceId,Region,District,District_tc,Street,Street_tc,Latitude,Longitude,VehicleType,LPP,OperatingPeriod,TimeUnit,PaymentUnit"
        let csv = "\u{FEFF}2026-09-20\r\n,,,,,,,,,,,,,\r\n\(header)\r\n1,1A,HK,CENTRAL,中西區,\"ROAD, ONE\",測試街,22.3,114.17,A,120,D,15,4\r\n2,2A,HK,CENTRAL,中西區,ROAD TWO,貨車街,22.3001,114.17,G,60,D,30,2\r\n3,3A,HK,CENTRAL,中西區,ROAD THREE,旅遊巴街,22.3002,114.17,C,240,D,15,2\r\n"
        let meters = try MeterCSV.spaces(csv)
        check(meters.count == 3, "BOM/date/blank/header handling must preserve the first space")
        check(meters[0].streetKey.contains("ROAD, ONE"), "Quoted comma must not shift columns")
        check(meters[0].paymentUnit == 4 && meters[0].timeUnit == 15, "Fee and time must come from named fields")
        let quotedRows = try MeterCSV.rows("name,value\n\"a\"\"b\",\"line\nline\"\n")
        check(quotedRows[1] == ["a\"b", "line\nline"], "Escaped quotes and multiline fields")
        let statuses = try MeterCSV.statuses("ParkingSpaceId,ParkingMeterStatus,OccupancyStatus,OccupancyDateChanged\r\n1A,N,V,09/20/2026 07:00:00 AM\r\n2A,NU,V,09/20/2026 07:00:00 AM\r\n3A,N,O,09/20/2026 07:00:00 AM\r\n")
        check(statuses["1A"]?.isOperating == true, "N means normal")
        check(statuses["2A"]?.isOperating == false, "NU overrides vacant")
        check(MeterBayType.general.accepts(.lightGoods), "General class includes light goods vehicles")
        check(!MeterBayType.general.accepts(.mediumHeavyGoods), "General class excludes medium/heavy goods")
        check(!MeterBayType.goods.accepts(.privateCar), "Goods bays exclude private cars")
        check(MeterBayType.coach.accepts(.coach), "Coach mapping")
        let now = Date()
        func state(_ meter: ParkingMeter, _ vehicle: MeterVehicle, _ date: Date?) -> MeterDisplayState {
            .resolve(meter: meter, status: statuses[meter.id], vehicle: vehicle, fetchedAt: date, now: now)
        }
        check(state(meters[0], .privateCar, now) == .vacant, "Compatible vacancy is green")
        check(state(meters[0], .coach, now) == .incompatible, "Incompatible vacancy is yellow")
        check(state(meters[0], .unset, now) == .vacant, "Unset vehicle must not imply incompatibility")
        check(state(meters[1], .lightGoods, now) == .unknown, "Unavailable meter is gray")
        check(state(meters[2], .privateCar, now) == .occupied, "Incompatible occupied bay stays red")
        check(state(meters[0], .privateCar, now.addingTimeInterval(-181)) == .unknown, "Stale status cannot remain green")
        check(state(meters[0], .privateCar, nil) == .unknown, "No status fetch is gray")
        check(MeterDisplayState.cluster([.occupied, .vacant, .unknown]) == .vacant, "Green cluster precedence")
        check(MeterDisplayState.cluster([.occupied, .incompatible, .unknown]) == .incompatible, "Yellow cluster precedence")
        check(MeterDisplayState.cluster([.occupied, .occupied]) == .occupied, "All occupied is red")
        check(MeterDisplayState.cluster([.occupied, .unknown]) == .unknown, "Uncertain cluster is gray")
        let origin = CLLocation(latitude: 22.3, longitude: 114.17)
        func bay(_ id: String, _ north: Double, _ street: String) -> ParkingMeter {
            ParkingMeter(id: id, poleId: id, district: "district", street: street, streetKey: street,
                         latitude: 22.3 + north / 110740, longitude: 114.17, bayType: .general,
                         lpp: nil, operatingPeriod: "", paymentUnit: nil, timeUnit: nil)
        }
        let candidates = [bay("1", 100, "A"), bay("2", 750, "A"), bay("3", 1100, "A"),
                          bay("4", 740, "B"), bay("5", 300, "C"), bay("90001", 50, "A")]
        let index = MeterSpatialIndex(candidates)
        let nearby = index.nearby(origin, radius: 1000)
        check(Set(nearby.map(\.id)) == Set(["1", "2", "4", "5"]), "Spatial index excludes distant and internal test bays")
        var visibility = MeterVisibility()
        func visible(_ seconds: Double, _ speed: Double = 0, _ location: CLLocation = origin) -> Set<String> {
            Set(visibility.update(candidates: candidates, location: location, speed: speed, radius: 500,
                                  now: now.addingTimeInterval(seconds)).map(\.id))
        }
        check(visible(0) == Set(["1", "2", "5"]), "Same street extends only to 2R without seeding street B")
        check(!visible(1, 51).isEmpty, "Brief speed above 50 must not hide")
        check(!visible(5, 51).isEmpty, "Wait full five seconds")
        check(visible(6, 51).isEmpty, "Sustained speed hides")
        check(visible(7, 50).isEmpty, "Wait before showing again")
        check(!visible(10, 50).isEmpty, "Exactly 50 qualifies after three seconds")
        let moved = CLLocation(latitude: 22.3 - 450 / 110740, longitude: 114.17)
        check(visible(11, 0, moved).contains("1"), "Street exit grace retains in-cap bay")
        check(!visible(16, 0, moved).contains("1"), "Street exit grace expires")
        check(visible(17).contains("1"), "Returning to a street restores it")
        do { _ = try MeterCSV.spaces("<html>error</html>"); preconditionFailure("Reject bad payload") }
        catch { checks += 1 }
        do { _ = try MeterCSV.rows("\"unterminated"); preconditionFailure("Reject malformed CSV") }
        catch { checks += 1 }
        if CommandLine.arguments.count == 3 {
            let spaces = try MeterCSV.spaces(String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8))
            let statuses = try MeterCSV.statuses(String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8))
            check(spaces.count > 10000, "Real location feed must contain the Hong Kong inventory")
            check(statuses.count > 10000, "Real occupancy feed must contain a full inventory")
            check(spaces.contains { $0.id == "1A" }, "First real location retained")
            check(spaces.allSatisfy { $0.bayType != .unknown }, "Verify real vehicle codes")
            print("Official feed: \(spaces.count) spaces; \(statuses.count) statuses; \(spaces.filter { $0.isTest }.count) test spaces")
        }
        print("PASS: \(checks) meter data, compatibility, freshness, clustering and visibility checks")
    }
}
