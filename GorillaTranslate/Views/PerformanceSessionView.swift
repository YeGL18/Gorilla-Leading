import SwiftUI
import UniformTypeIdentifiers
import QuartzCore
import Darwin

struct DiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Opt-in diagnostics reuse animation callbacks; no extra display link is created.
@MainActor final class PerformanceRecorder: ObservableObject {
    static let shared = PerformanceRecorder()
    @Published private(set) var running = false
    @Published private(set) var samples = 0
    private var timer: Timer?
    private var startedAt = Date()
    private var previousCPU = 0.0
    private var previousTime = 0.0
    private var batteryWasEnabled = false
    private var lines: [String] = []
    private var streams: [String: (last: Double, count: Int, stalled: Int, maximum: Double)] = [:]
    private var foregroundObserver: NSObjectProtocol?

    private init() {
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.streams = [:] }
            }
    }

    func frame(_ source: String, timestamp: Double, expected: Double) {
        guard running, UIApplication.shared.applicationState == .active else { return }
        var stream = streams[source] ?? (0, 0, 0, 0)
        if stream.last > 0 {
            let interval = timestamp - stream.last
            if interval > 0 {
                stream.count += 1
                stream.maximum = max(stream.maximum, interval)
                if interval > max(expected * 2, 0.025) { stream.stalled += 1 }
            }
        }
        stream.last = timestamp
        streams[source] = stream
    }

    func start() {
        guard !running else { return }
        samples = 0
        streams = [:]
        startedAt = Date()
        previousTime = CACurrentMediaTime()
        previousCPU = cpuTime()
        batteryWasEnabled = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        lines = ["elapsed_s,foreground,battery_percent,charging,thermal,low_power,brightness,cpu_percent,memory_mb,high_frequency_tracking,orbs_enabled,orb_mixing,dark_knight,source,callbacks,delayed_callbacks,max_interval_ms"]
        running = true
        AnimationDiagnostics.callback = { [weak self] source, timestamp, expected in
            MainActor.assumeIsolated { self?.frame(source, timestamp: timestamp, expected: expected) }
        }
        sample()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard running else { return }
        sample()
        running = false
        AnimationDiagnostics.callback = nil
        timer?.invalidate()
        timer = nil
        UIDevice.current.isBatteryMonitoringEnabled = batteryWasEnabled
    }

    var csv: String { lines.joined(separator: "\n") }

    private func sample() {
        let now = CACurrentMediaTime()
        let cpu = cpuTime()
        let utilization = (cpu - previousCPU) / max(now - previousTime, 0.001) * 100
        previousCPU = cpu
        previousTime = now
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let defaults = UserDefaults.standard
        let battery: Double = UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel * 100) : -1
        let base = [
            fixed(Date().timeIntervalSince(startedAt), places: 0),
            UIApplication.shared.applicationState == .active ? "true" : "false",
            fixed(battery, places: 0),
            UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full ? "1" : "0",
            thermal, ProcessInfo.processInfo.isLowPowerModeEnabled ? "1" : "0",
            fixed(Double(UIScreen.main.brightness), places: 2), fixed(utilization, places: 1), fixed(memoryMB(), places: 1),
            (defaults.object(forKey: "highFrequencyTracking") as? Bool ?? true) ? "1" : "0",
            (defaults.object(forKey: "orbMasterEnabled") as? Bool ?? true) ? "1" : "0",
            (defaults.object(forKey: "orbOverlapGlowEnabled") as? Bool ?? true) ? "1" : "0",
            GorillaColorGroup.load(defaults).usesSpecialMap ? "1" : "0"
        ].joined(separator: ",")
        if streams.isEmpty { lines.append(base + ",none,0,0,0") }
        for (name, stream) in streams.sorted(by: { $0.key < $1.key }) {
            lines.append(base + ",\(name),\(stream.count),\(stream.stalled)," + fixed(stream.maximum * 1000, places: 2))
        }
        streams = streams.mapValues { _ in (0, 0, 0, 0) }
        samples += 1
        // A bounded three-hour foreground test; never an indefinite logger.
        if Date().timeIntervalSince(startedAt) >= 3 * 3600 {
            running = false
            AnimationDiagnostics.callback = nil
            timer?.invalidate()
            timer = nil
            UIDevice.current.isBatteryMonitoringEnabled = batteryWasEnabled
        }
    }

    private func fixed(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func cpuTime() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return previousCPU }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}

struct PerformanceSessionView: View {
    @ObservedObject private var recorder = PerformanceRecorder.shared
    @State private var exporting = false
    @State private var document: DiagnosticDocument?
    @State private var exportError: String?
    var body: some View {
        Form {
            Section {
                LabeledContent("Samples", value: String(recorder.samples))
                Button { recorder.running ? recorder.stop() : recorder.start() } label: {
                    Label(recorder.running ? String(localized: "Stop Recording") : String(localized: "Start Recording"),
                        systemImage: recorder.running ? "stop.circle" : "record.circle")
                }
                Button {
                    document = DiagnosticDocument(text: recorder.csv)
                    exporting = true
                } label: { Label("Export Diagnostics", systemImage: "square.and.arrow.up") }
                .disabled(recorder.samples == 0 || recorder.running)
            } footer: {
                Text("Records battery, system thermal state, CPU, memory and animation callback delays every 10 seconds. Callback timing is not rendered map FPS. No route coordinates or photos are recorded. Stops after three hours.")
            }
        }
        .navigationTitle("Performance Check")
        .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText,
            defaultFilename: "Gorilla-performance") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
                document = nil
            }
        .alert("Performance Check", isPresented: Binding(get: { exportError != nil },
            set: { if !$0 { exportError = nil } })) {
                Button("確定", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
    }
}
