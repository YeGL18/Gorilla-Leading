import SwiftUI
import UIKit

struct SpeedUnitPicker: View {
    @AppStorage(SpeedUnit.preferenceKey) private var selection = SpeedUnit.kilometresPerHour.rawValue

    var body: some View {
        Picker(selection: $selection) {
            ForEach(SpeedUnit.allCases) { unit in
                Text(unit.symbol).tag(unit.rawValue)
            }
        } label: {
            Label("時速單位", systemImage: "speedometer")
        }
        .accessibilityIdentifier("speedUnitPicker")
    }
}

struct SpeedInstrumentCards<SpeedContent: View>: View {
    let motion: GForceParallaxMotion
    let telemetry: ACTelemetry
    let partiallyOpen: Bool
    let foreground: Color
    let accent: Color
    var textColorOverride: Color? = nil
    let source: String
    var drivingState = false
    var onBlankTap: () -> Void = {}
    @ViewBuilder var speed: (Bool) -> SpeedContent

    var body: some View {
        GeometryReader { geo in
            let layout = SpeedCardLayout(width: geo.size.width, height: geo.size.height, partiallyOpen: partiallyOpen)
            VStack(spacing: 0) {
                if layout.horizontal {
                    HStack(spacing: 12) {
                        currentAction
                            .frame(maxWidth: .infinity)
                        speedCard(compact: layout.cardHeight < 210)
                            .frame(width: max(210, (layout.width - 64) * 0.38))
                        forceCircle
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: layout.cardHeight)
                } else {
                    VStack(spacing: 12) {
                        currentAction.frame(height: layout.cardHeight)
                        speedCard(compact: layout.cardHeight < 210).frame(height: layout.cardHeight)
                        forceCircle.frame(height: layout.cardHeight)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(width: layout.width, height: layout.height)
            .background {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onBlankTap)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("speedInstrumentDeck")
        }
        .foregroundStyle(foreground)
    }

    private var currentAction: some View {
        SpeedCurrentActionPanel(motion: motion, telemetry: telemetry, accent: accent, textColorOverride: textColorOverride,
                                canRecognize: drivingState || telemetry.isReceiving)
            .instrumentGlass()
            .accessibilityIdentifier("currentActionCard")
    }

    private var forceCircle: some View {
        SpeedGForceCirclePanel(motion: motion, telemetry: telemetry, accent: accent, textColorOverride: textColorOverride)
            .instrumentGlass()
            .accessibilityIdentifier("gForceCircleCard")
    }

    private func speedCard(compact: Bool) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("Speed").font(.headline)
                Spacer(minLength: 4)
                Text(source).font(.caption.weight(.semibold)).foregroundStyle(textColorOverride ?? accent)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            speed(compact).frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .instrumentGlass()
        .accessibilityIdentifier("speedCenterCard")
    }
}

private struct InstrumentBackdropBlur: UIViewRepresentable {
    let dark: Bool
    final class Coordinator {
        var dark: Bool?
        var animator: UIViewPropertyAnimator?

        func apply(to view: UIVisualEffectView, dark: Bool) {
            guard self.dark != dark else { return }
            self.dark = dark
            animator?.stopAnimation(true)
            view.effect = nil
            let effect = UIBlurEffect(style: dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak view] in
                view?.effect = effect
            }
            animator.startAnimation()
            animator.pauseAnimation()
            animator.fractionComplete = dark ? 0.35 : 0.08
            self.animator = animator
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        view.isUserInteractionEnabled = false
        context.coordinator.apply(to: view, dark: dark)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        context.coordinator.apply(to: view, dark: dark)
    }

    static func dismantleUIView(_ view: UIVisualEffectView, coordinator: Coordinator) {
        coordinator.animator?.stopAnimation(true)
        coordinator.animator = nil
        view.effect = nil
    }
}

private struct InstrumentGlass: ViewModifier {
    @AppStorage("capsuleDarkGlassEnabled") private var darkGlassEnabled = true

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                InstrumentBackdropBlur(dark: darkGlassEnabled)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .glassEffect(.clear.tint(darkGlassEnabled ? .black.opacity(0.03) : .clear),
                                 in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .contain)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture { }
    }
}

private extension View {
    func instrumentGlass() -> some View {
        modifier(InstrumentGlass())
    }
}

private struct SpeedCurrentActionPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var motion: GForceParallaxMotion
    @ObservedObject var telemetry: ACTelemetry
    let accent: Color
    let textColorOverride: Color?
    let canRecognize: Bool
    @State private var tracker = SpeedActionTracker()

    private var reading: SpeedGForce? {
        telemetry.isReceiving ? telemetry.sample?.gForce : motion.reading
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                actionContent(now: ProcessInfo.processInfo.systemUptime, height: geo.size.height)
            }
        }
        .transaction { $0.animation = nil }
        .onReceive(motion.$reading) { force in
            guard canRecognize, !telemetry.isReceiving else { return }
            tracker.update(force, at: ProcessInfo.processInfo.systemUptime)
        }
        .onReceive(telemetry.$sample) { sample in
            guard canRecognize, telemetry.isReceiving else { return }
            tracker.update(sample?.gForce, at: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: telemetry.isReceiving) { _, _ in tracker = SpeedActionTracker() }
        .onChange(of: canRecognize) { _, _ in tracker = SpeedActionTracker() }
    }

    private func actionContent(now: TimeInterval, height: CGFloat) -> some View {
        let compact = height < 210
        let freshReading = canRecognize && tracker.isFresh(at: now) ? reading : nil
        let result = freshReading == nil ? nil : tracker.completed(at: now)
        let ongoing = freshReading != nil && tracker.action != .steady
        let action = result?.action ?? tracker.action
        let title = !canRecognize ? "暫無動作" : freshReading == nil ? "等待數據" : ongoing ? action.title : result?.action.resultTitle ?? "暫無動作"
        let duration = result?.duration ?? tracker.duration(at: now)
        let peak = result?.peak ?? tracker.peak
        let statusColor: Color = result != nil ? .green : accent
        let phase = ongoing ? "ongoing-\(action.rawValue)" : result != nil ? "completed-\(action.rawValue)" : "idle"
        return VStack(alignment: .leading, spacing: height < 150 ? 2 : compact ? 3 : 10) {
            HStack(spacing: 6) {
                Text("目前動作").font(compact ? .caption.weight(.semibold) : .headline)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 2)
                if ongoing || result != nil {
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 4, height: 4).accessibilityHidden(true)
                        Text(LocalizedStringKey(ongoing ? "進行中" : "已完成"))
                            .contentTransition(.opacity)
                            .accessibilityIdentifier("currentActionStatus")
                    }
                    .font(.caption2.weight(.semibold)).foregroundStyle(textColorOverride ?? statusColor)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .transition(.opacity)
                }
            }
            HStack(spacing: compact ? 8 : 12) {
                Image(systemName: ongoing || result != nil ? action.symbol : "waveform.path")
                    .font(.system(size: compact ? 20 : 32, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: compact ? 32 : 58, height: compact ? 32 : 58)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .contentTransition(.opacity)
                        .font(compact ? .caption.weight(.semibold) : .headline)
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .accessibilityIdentifier("currentActionName")
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(ongoing ? "已持續" : "持續時間"))
                            .contentTransition(.opacity)
                            .accessibilityIdentifier("currentActionDurationLabel")
                        Text(ongoing || result != nil ? String(format: "%.1f s", duration) : "—")
                            .contentTransition(.numericText())
                            .monospacedDigit().accessibilityIdentifier("currentActionDuration")
                    }
                    .font(.caption2).foregroundStyle(textColorOverride ?? .secondary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            Divider().overlay(.primary.opacity(0.08))
            HStack(spacing: 8) {
                forceValue("目前力度", value: freshReading.map { action.force($0) }, identifier: "currentActionForce", compact: compact)
                Spacer(minLength: 2)
                forceValue("峰值", value: freshReading == nil ? nil : peak, identifier: "currentActionPeak", compact: compact)
            }
            if let result {
                HStack(spacing: 6) {
                    Text("評分").font(.caption2).foregroundStyle(textColorOverride ?? .secondary)
                        .accessibilityIdentifier("currentActionScoreTitle")
                    Text("\(result.score)")
                        .font(.system(size: compact ? 16 : 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(textColorOverride ?? accent).monospacedDigit()
                        .accessibilityIdentifier("currentActionScore")
                    Spacer(minLength: 0)
                    Text(LocalizedStringKey(result.feedback)).font(.caption2).foregroundStyle(textColorOverride ?? .secondary)
                        .lineLimit(compact ? 1 : 2).minimumScaleFactor(0.65)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("currentActionSummary")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(height < 150 ? 8 : compact ? 10 : 16)
        // Animate structural state changes, not every incoming force sample or timer tick.
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : .spring(duration: 0.38, bounce: 0.12), value: phase)
    }

    private func forceValue(_ title: String, value: Double?, identifier: String, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.caption2).foregroundStyle(textColorOverride ?? .secondary)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: compact ? 14 : 22, weight: .semibold, design: .rounded))
                .monospacedDigit().accessibilityIdentifier(identifier)
            Text("G").font(.caption2).foregroundStyle(textColorOverride ?? .secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.6)
    }
}

private struct SpeedGForceCirclePanel: View {
    @ObservedObject var motion: GForceParallaxMotion
    @ObservedObject var telemetry: ACTelemetry
    let accent: Color
    let textColorOverride: Color?
    @Environment(\.scenePhase) private var scenePhase
    @State private var recentPeak = SpeedGForceRecentPeak()

    private var reading: SpeedGForce? {
        telemetry.isReceiving ? telemetry.sample?.gForce : motion.reading
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("G-force").font(.headline)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Text(reading.map { String(format: "%.2f G", $0.magnitude) } ?? "— G")
                        .foregroundStyle(textColorOverride ?? accent)
                        .accessibilityIdentifier("gForceMagnitude")
                    Text("峰值").foregroundStyle(textColorOverride ?? .secondary)
                    Text(reading == nil ? "— G" : String(format: "%.2f G", recentPeak.peak))
                        .foregroundStyle(textColorOverride ?? accent)
                        .accessibilityIdentifier("gForceRecentPeak")
                }
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            SpeedGForcePlot(reading: reading, accent: accent)
                .id(telemetry.isReceiving)
        }
        .padding(16)
        .transaction { $0.animation = nil }
        .onAppear { recentPeak.update(reading, at: ProcessInfo.processInfo.systemUptime) }
        .onReceive(motion.$reading) { value in
            if !telemetry.isReceiving { recentPeak.update(value, at: ProcessInfo.processInfo.systemUptime) }
        }
        .onReceive(telemetry.$sample) { sample in
            if telemetry.isReceiving { recentPeak.update(sample?.gForce, at: ProcessInfo.processInfo.systemUptime) }
        }
        .onChange(of: telemetry.isReceiving) { _, _ in recentPeak = SpeedGForceRecentPeak() }
        .onChange(of: scenePhase) { _, _ in recentPeak = SpeedGForceRecentPeak() }
    }
}

private struct SpeedGForcePlot: View {
    let reading: SpeedGForce?
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var trail = SpeedGForceTrail()

    var body: some View {
        GeometryReader { geo in
            let labelsFit = geo.size.height >= 76
            let size = max(12, min(260, min(geo.size.width - 76, geo.size.height - (labelsFit ? 44 : 8))))
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2
            let range = reading?.plotRange ?? 1
            let x = (reading?.lateral ?? 0) / range * radius
            let y = -(reading?.longitudinal ?? 0) / range * radius
            ZStack {
                ForEach(0..<4, id: \.self) { quadrant in
                    Circle().trim(from: 0.045, to: 0.205)
                        .stroke(.primary.opacity(0.18), lineWidth: 1)
                        .rotationEffect(.degrees(Double(quadrant) * 90))
                        .frame(width: size, height: size)
                }
                Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 1).frame(width: size / 2, height: size / 2)
                Rectangle().fill(.primary.opacity(0.12)).frame(width: size * 0.65, height: 1)
                Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: size)
                if !reduceMotion, reading != nil {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active)) { context in
                        Canvas { canvas, canvasSize in
                            let now = context.date.timeIntervalSinceReferenceDate
                            let samples = trail.visible(at: now)
                            for index in samples.indices.dropFirst() {
                                let previous = samples[index - 1]
                                let sample = samples[index]
                                let freshness = max(0, 1 - (now - sample.time) / SpeedGForceTrail.lifetime)
                                var path = Path()
                                path.move(to: CGPoint(x: canvasSize.width / 2 + previous.force.lateral / range * radius,
                                                      y: canvasSize.height / 2 - previous.force.longitudinal / range * radius))
                                path.addLine(to: CGPoint(x: canvasSize.width / 2 + sample.force.lateral / range * radius,
                                                         y: canvasSize.height / 2 - sample.force.longitudinal / range * radius))
                                canvas.stroke(path, with: .color(accent.opacity(freshness * 0.65)),
                                              style: StrokeStyle(lineWidth: 1 + freshness * 4, lineCap: .round))
                            }
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                if reading != nil {
                    Circle().fill(accent.opacity(0.13)).frame(width: 28, height: 28).offset(x: x, y: y)
                    Circle().fill(accent).frame(width: 9, height: 9).offset(x: x, y: y)
                }
            }
            .position(center)
            if labelsFit {
            direction(reading.map { max(0, $0.longitudinal) })
                .position(x: center.x, y: center.y - radius - 12)
            direction(reading.map { max(0, -$0.longitudinal) })
                .position(x: center.x, y: center.y + radius + 12)
            direction(reading.map { max(0, -$0.lateral) })
                .position(x: max(27, center.x - radius - 29), y: center.y)
            direction(reading.map { max(0, $0.lateral) })
                .position(x: min(geo.size.width - 27, center.x + radius + 29), y: center.y)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("G-force")
        .accessibilityValue(reading.map { String(format: "%.2f G", $0.magnitude) } ?? "—")
        .accessibilityIdentifier("gForcePlot")
        .onChange(of: reading, initial: true) { _, value in
            trail.append(value, at: Date.timeIntervalSinceReferenceDate)
        }
        .onChange(of: scenePhase) { _, _ in trail = SpeedGForceTrail() }
    }

    private func direction(_ value: Double?) -> some View {
        Text(value.map { String(format: "%.2f", abs($0)) } ?? "—")
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).frame(width: 54, height: 18)
    }
}
