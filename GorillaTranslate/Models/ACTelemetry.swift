import Foundation
import Combine
import Network

struct ACCarSample {
    let speed: Double
    let rpm: Double
    let gear: Int
    let lap: Int
    let currentLap: Int
    let lastLap: Int
    let bestLap: Int
    let throttle: Double
    let brake: Double
    let gForce: SpeedGForce?

    var gearLabel: String { gear == 0 ? "R" : gear == 1 ? "N" : String(gear - 1) }
}

enum ACPacket {
    // Original AC Windows wire format: aligned little-endian fields, UTF-16 names.
    static func integer(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }

    static func car(_ data: Data) -> ACCarSample? {
        guard data.count == 328, data[0] == 97, integer(data, 4) == 328 else { return nil }
        let speed = Double(Float(bitPattern: integer(data, 8)))
        let rpm = Double(Float(bitPattern: integer(data, 68)))
        let gear = Int(Int32(bitPattern: integer(data, 76)))
        let times = [40, 44, 48, 52].map { Int(Int32(bitPattern: integer(data, $0))) }
        let throttle = Double(Float(bitPattern: integer(data, 56)))
        let brake = Double(Float(bitPattern: integer(data, 60)))
        guard speed.isFinite, rpm.isFinite, (0...1500).contains(speed),
              (0...100000).contains(rpm), (0...20).contains(gear),
              times.allSatisfy({ $0 >= 0 }), throttle.isFinite, brake.isFinite,
              (0...1).contains(throttle), (0...1).contains(brake) else { return nil }
        return ACCarSample(speed: speed, rpm: rpm, gear: gear, lap: times[3],
                           currentLap: times[0], lastLap: times[1], bestLap: times[2],
                           throttle: throttle, brake: brake,
                           gForce: SpeedGForce.validated(lateral: Double(Float(bitPattern: integer(data, 32))),
                                                       longitudinal: Double(Float(bitPattern: integer(data, 36)))))
    }

    static func names(_ data: Data) -> (car: String, track: String, configuration: String)? {
        guard data.count == 408, integer(data, 200) == 4242, integer(data, 204) == 1 else { return nil }
        func name(_ offset: Int) -> String {
            var units: [UInt16] = []
            for index in stride(from: offset, to: offset + 100, by: 2) {
                let value = UInt16(data[index]) | UInt16(data[index + 1]) << 8
                if value == 0 { break }
                units.append(value)
            }
            return String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (name(0), name(208), name(308))
    }

    static func command(_ operation: UInt32) -> Data {
        var data = Data()
        for value: UInt32 in [0, 1, operation] {
            data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        return data
    }

    static func lapTime(_ milliseconds: Int?) -> String {
        guard let milliseconds, milliseconds > 0 else { return "—" }
        return String(format: "%d:%02d.%03d", milliseconds / 60000,
                      milliseconds / 1000 % 60, milliseconds % 1000)
    }
}

@MainActor
final class ACTelemetry: ObservableObject {
    @Published private(set) var sample: ACCarSample?
    @Published private(set) var carName = ""
    @Published private(set) var trackName = ""
    @Published private(set) var configuration = ""
    @Published private(set) var status = String(localized: "未連線")
    @Published private(set) var isReceiving = false
    private var connection: NWConnection?
    private var timer: Timer?
    private var pending: ACCarSample?
    private var lastPacket = Date.distantPast
    private var lastHandshake = Date.distantPast
    private var generation = UUID()
    private var transportReady = false
    private var desiredHost: String?
    private var lastAttempt = Date.distantPast

    func ensureConnected(host: String) {
        if desiredHost == host.trimmingCharacters(in: .whitespacesAndNewlines), timer != nil { return }
        connect(host: host)
    }

    func connect(host: String) {
        disconnect()
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { status = String(localized: "請輸入電腦 IP 地址"); return }
        desiredHost = host
        startTransport(host: host)
        // Coalesce physics-step packets before publishing UI state at 30 Hz.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func startTransport(host: String) {
        connection?.cancel()
        generation = UUID()
        transportReady = false
        lastPacket = .distantPast
        lastAttempt = Date()
        clearSample()
        status = String(localized: "正在連接電腦")
        let token = generation
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 9996, using: .udp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch state {
                case .ready:
                    guard !self.transportReady else { return }
                    self.transportReady = true
                    self.status = String(localized: "等待 AC 遙測")
                    self.send(0)
                    self.receive(connection, token: token)
                case .waiting, .failed:
                    self.transportReady = false
                    self.status = String(localized: "連線失敗，請檢查區域網絡及防火牆")
                    self.clearSample()
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    func disconnect() {
        if let connection {
            connection.send(content: ACPacket.command(3), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
        generation = UUID()
        connection = nil
        desiredHost = nil
        transportReady = false
        timer?.invalidate()
        timer = nil
        lastPacket = .distantPast
        lastHandshake = .distantPast
        carName = ""
        trackName = ""
        configuration = ""
        clearSample()
        status = String(localized: "未連線")
    }

    private func send(_ operation: UInt32) {
        connection?.send(content: ACPacket.command(operation), completion: .contentProcessed { _ in })
        if operation == 0 { lastHandshake = Date() }
    }

    private func receive(_ connection: NWConnection, token: UUID) {
        connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let data {
                    if let names = ACPacket.names(data) {
                        self.carName = names.car
                        self.trackName = names.track
                        self.configuration = names.configuration
                        self.send(1)
                    } else if let sample = ACPacket.car(data) {
                        self.pending = sample
                        self.lastPacket = Date()
                    }
                }
                if error == nil { self.receive(connection, token: token) }
                else {
                    self.transportReady = false
                    self.status = String(localized: "連線中斷")
                    self.clearSample()
                }
            }
        }
    }

    private func clearSample() {
        if isReceiving { isReceiving = false }
        if sample != nil { sample = nil }
        pending = nil
    }

    private func tick() {
        guard transportReady else {
            if let desiredHost, Date().timeIntervalSince(lastAttempt) > 3 {
                startTransport(host: desiredHost)
            }
            return
        }
        if Date().timeIntervalSince(lastPacket) > 3 {
            clearSample()
            if Date().timeIntervalSince(lastHandshake) > 2 {
                status = String(localized: "等待 AC 遙測")
                send(0)
            }
        } else if let pending {
            sample = pending
            self.pending = nil
            if !isReceiving { isReceiving = true; status = String(localized: "電腦遙測已連線") }
            if Date().timeIntervalSince(lastHandshake) > 15 { send(0) }
        }
    }
}
