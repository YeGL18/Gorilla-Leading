import Foundation
import CoreLocation

// Explicit simulator-only developer utility. Pass the simulator history.json path.
@main struct SeedDuoReplay {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard url.path.contains("CoreSimulator/Devices/8E46229D-0702-4B21-8DEE-9673DBE24928/") else {
            fatalError("This utility only writes to the designated iPhone Duo simulator")
        }
        var archive = (try? JSONDecoder().decode(TripReplayArchive.self, from: Data(contentsOf: url))) ?? TripReplayArchive()
        let ids = [UUID(uuidString:"D0020001-0000-4000-8000-000000000001")!, UUID(uuidString:"D0020002-0000-4000-8000-000000000002")!]
        let routes: [[(Double,Double)]] = [
            [(22.2820,114.1580),(22.2798,114.1640),(22.2778,114.1700),(22.2780,114.1790),(22.2800,114.1860),(22.2840,114.1920),(22.2870,114.1960)],
            [(22.2970,114.1720),(22.3050,114.1730),(22.3170,114.1760),(22.3300,114.1820),(22.3450,114.1840),(22.3610,114.1830),(22.3810,114.1880)]]
        let names = [("示範 · 中環", "示範 · 北角"),("示範 · 尖沙咀", "示範 · 沙田")]
        for index in 0..<2 where !archive.trips.contains(where:{$0.id == ids[index]}) {
            let start = Date().addingTimeInterval(Double(-4 + index * 2) * 3600)
            let route = routes[index]
            var points: [TripReplayPoint] = []
            var elapsed = 0.0
            for segment in 0..<(route.count - 1) {
                let a=route[segment], b=route[segment+1]
                let distance=CLLocation(latitude:a.0,longitude:a.1).distance(from:CLLocation(latitude:b.0,longitude:b.1))
                let steps=max(30,Int(distance / 14))
                for step in 0..<steps {
                    let t=Double(step)/Double(steps)
                    let speed=28 + 17*sin(t * .pi) + 7*sin(Double(step)*0.13)
                    let dt=(distance/Double(steps))/(speed/3.6)
                    let lateral=0.12*sin(Double(segment)*1.8+t * .pi)
                    let longitudinal=0.08*cos(Double(step)*0.13)
                    points.append(TripReplayPoint(time:start.addingTimeInterval(elapsed),latitude:a.0+(b.0-a.0)*t,
                        longitude:a.1+(b.1-a.1)*t,accuracy:4,speedKmh:speed,
                        altitude:18 + Double(index)*14 + 22*sin(elapsed/180) + Double(segment)*5,
                        verticalAccuracy:5,lateralG:lateral,longitudinalG:longitudinal,driving:true))
                    elapsed += dt
                }
            }
            let end=route.last!
            points.append(TripReplayPoint(time:start.addingTimeInterval(elapsed),latitude:end.0,longitude:end.1,
                accuracy:4,speedKmh:0,altitude:25+Double(index)*28,verticalAccuracy:5,lateralG:0,longitudinalG:0,driving:true))
            let actions: [SpeedDrivingAction] = [.accelerating,.left,.braking,.right]
            let events=(0..<12).map { n in
                let time=start.addingTimeInterval(8 + Double(n)*max(10,(elapsed-25)/12))
                return TripReplayEvent(id:UUID(),start:time,end:time.addingTimeInterval(3.4+Double(n%3)),
                    action:actions[n%4],peakG:0.12+Double(n%5)*0.025,score:82+n%13)
            }
            archive.trips.append(TripReplay(id:ids[index],points:points,events:events,
                originName:names[index].0,destinationName:names[index].1,finished:true))
        }
        _ = try archive.validated()
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:url.path) {
            let backup=url.appendingPathExtension("before-demo-\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.copyItem(at:url,to:backup)
        }
        try JSONEncoder().encode(archive).write(to:url,options:.atomic)
        print("Saved two labelled demo trips with coordinates, speed, altitude, G-force and 12 events each; existing trips preserved.")
    }
}
