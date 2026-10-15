import SwiftUI

struct ACTelemetryOverlay: View {
    @ObservedObject var telemetry: ACTelemetry
    var foreground: Color = .white

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 8) {
                header
                if telemetry.isReceiving {
                    if landscape {
                        lapMetrics
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom) {
                            drivetrain.frame(width: max(140, geo.size.width * 0.23))
                                .rotation3DEffect(.degrees(32), axis: (x: 0, y: 1, z: 0), perspective: 0.85)
                            Spacer(minLength: 180)
                            pedals.frame(width: max(140, geo.size.width * 0.23))
                                .rotation3DEffect(.degrees(-32), axis: (x: 0, y: 1, z: 0), perspective: 0.85)
                        }
                    } else {
                        Spacer(minLength: 154)
                        VStack(spacing: 12) {
                            HStack(spacing: 24) {
                                drivetrain
                                pedals
                            }
                            lapMetrics
                        }
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, landscape ? 20 : 24)
            .padding(.top, 12)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(foreground)
    }

    private var header: some View {
        VStack(spacing: 3) {
            Label(LocalizedStringKey(telemetry.isReceiving ? "ASSETTO CORSA · 電腦遙測" : "GPS · 等待電腦遙測"),
                  systemImage: "desktopcomputer")
                .font(.caption.weight(.bold))
                .foregroundStyle(telemetry.isReceiving ? .purple : .yellow)
            if telemetry.isReceiving {
                Text([telemetry.carName, telemetry.trackName, telemetry.configuration]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
        }
    }

    private var drivetrain: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("波段").font(.caption)
                Text(telemetry.sample?.gearLabel ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit().accessibilityIdentifier("acGear")
                Spacer(minLength: 0)
            }
            HStack {
                Text("RPM").font(.caption)
                Spacer(minLength: 4)
                Text(telemetry.sample.map { String(Int($0.rpm.rounded())) } ?? "—")
                    .font(.system(.headline, design: .monospaced))
                    .accessibilityIdentifier("acRPM")
            }
            ProgressView(value: min(telemetry.sample?.rpm ?? 0, 30000), total: 30000).tint(.purple)
            Text("0 – 30,000 RPM").font(.caption2).opacity(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var pedals: some View {
        HStack(alignment: .bottom, spacing: 16) {
            pedal("煞車", value: telemetry.sample?.brake ?? 0, color: .red, identifier: "acBrake")
            pedal("油門", value: telemetry.sample?.throttle ?? 0, color: .green, identifier: "acThrottle")
        }
        .frame(maxWidth: .infinity)
    }

    private func pedal(_ label: String, value: Double, color: Color, identifier: String) -> some View {
        let fraction = min(1, max(0, value))
        return VStack(spacing: 4) {
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(.caption, design: .monospaced)).monospacedDigit()
                .frame(width: 60).accessibilityIdentifier(identifier)
            RoundedRectangle(cornerRadius: 3)
                .fill(foreground.opacity(0.12))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(color).frame(height: 72 * fraction)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(foreground.opacity(0.35), lineWidth: 0.75) }
                .frame(width: 18, height: 72)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(label)).font(.caption)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 60)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier + "Column")
    }

    private var lapMetrics: some View {
        HStack(alignment: .top, spacing: 8) {
            metric("完成圈數", telemetry.sample.map { String($0.lap) } ?? "—")
            metric("本圈", ACPacket.lapTime(telemetry.sample?.currentLap))
            metric("上圈", ACPacket.lapTime(telemetry.sample?.lastLap))
            metric("最佳", ACPacket.lapTime(telemetry.sample?.bestLap))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(LocalizedStringKey(title)).font(.caption2).opacity(0.65)
            Text(value).font(.system(.caption, design: .monospaced))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ACConnectionSheet: View {
    @Binding var host: String
    let gameMode: Bool
    let connect: () -> Void
    let useGPS: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftHost = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("時速來源") {
                    Picker("電腦遊戲", selection: .constant("ac")) {
                        Text("Assetto Corsa").tag("ac")
                    }
                }
                Section("Windows 電腦") {
                    TextField("IP 地址", text: $draftHost)
                        .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().accessibilityIdentifier("acHost")
                    LabeledContent("UDP", value: "9996")
                    Button { host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines); connect(); dismiss() } label: {
                        Label("儲存並等待連線", systemImage: "desktopcomputer")
                    }
                    .disabled(draftHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if gameMode {
                        Button { useGPS(); dismiss() } label: {
                            Label("關閉電腦連線", systemImage: "power")
                        }
                    }
                }
            }
            .navigationTitle("時速來源")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("關閉", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .onAppear { draftHost = host }
    }
}
