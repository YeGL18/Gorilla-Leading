import SwiftUI

struct LiquidGlassCapsuleDemo: View {
    @Environment(\.colorScheme) private var colorScheme
    var palette: BorderBeamPalette
    var address: String
    var showSpeed: Bool
    var speedKmh: Double
    var etaText: String?
    var enableRotate: Bool
    var enablePulse: Bool

    var body: some View {
        let capsuleWidth: CGFloat = showSpeed ? 370 : 270
        let capsuleHeight: CGFloat = 44
        let capsuleRadius: CGFloat = 34

        ZStack {
            liquidGlassOrbBackground(radius: capsuleRadius)

            ZStack {
                if showSpeed {
                    HStack(spacing: 16) {
                        Text("\(Int(speedKmh)) km/h")
                            .font(.body.bold())
                            .foregroundStyle(primaryText)
                        if let etaText {
                            Text(etaText)
                                .font(.body.bold())
                                .foregroundStyle(primaryText)
                        }
                    }
                } else {
                    Text(address)
                        .font(.body.bold())
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .glassEffect(.regular, in: .rect(cornerRadius: capsuleRadius))
        .clipShape(.rect(cornerRadius: capsuleRadius))
        .overlay(alignment: .center) {
            beamOverlay(radius: capsuleRadius)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .center) {
            glowOverlay(radius: capsuleRadius)
                .allowsHitTesting(false)
        }
    }

    private var primaryText: Color {
        switch palette {
        case .mono:
            return colorScheme == .dark ? .white : .black
        case .ocean:
            return .white
        case .senshackDark:
            return .white
        }
    }

    @ViewBuilder
    private func liquidGlassOrbBackground(radius: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let _ = w
            let _ = h

            ZStack {
                baseFill

                // TODO: orb 流動光球高度偏移有 render 問題，臨時停用，之後補返
            }
            .clipShape(.rect(cornerRadius: radius))
        }
    }

    private var baseFill: Color {
        switch palette {
        case .mono:
            return Color.black.opacity(0.40)
        case .ocean:
            return Color(red: 0.06, green: 0.14, blue: 0.26).opacity(0.58)
        case .senshackDark:
            return Color.black.opacity(0.72)
        }
    }

    private var orbColorA: Color {
        switch palette {
        case .mono:
            return Color(white: 0.75)
        case .ocean:
            return Color(red: 0.74, green: 0.74, blue: 0.25)
        case .senshackDark:
            return Color(red: 0.86, green: 0.74, blue: 0.40)
        }
    }

    private var orbColorB: Color {
        switch palette {
        case .mono:
            return Color(white: 0.55)
        case .ocean:
            return Color(red: 0.36, green: 0.68, blue: 0.72)
        case .senshackDark:
            return Color(red: 0.54, green: 0.38, blue: 0.82)
        }
    }

    private var orbColorC: Color {
        switch palette {
        case .mono:
            return Color(white: 0.35)
        case .ocean:
            return Color(red: 0.0, green: 0.60, blue: 1.00)
        case .senshackDark:
            return Color(red: 0.92, green: 0.40, blue: 0.32)
        }
    }

    @ViewBuilder
    private func beamOverlay(radius: CGFloat) -> some View {
        let size = BorderBeamSize.large
        let span: Double = enableRotate ? size.beamSpanDegrees : 360.0
        let spread = size.strokeFromCenter
        let head = palette.beamColors.first ?? .white
        let mid = palette.beamColors.count > 1 ? palette.beamColors[1] : head
        let tail = palette.beamColors.count > 2 ? palette.beamColors[2] : head.opacity(0.5)
        let full = 360.0
        TimelineView(.animation) { tl in
            let elapsed = tl.date.timeIntervalSinceReferenceDate
            let period = size.duration
            let phase = (elapsed.remainder(dividingBy: period) / period + 1)
                .truncatingRemainder(dividingBy: 1)
            let pulsePeriod = size.duration * 0.42
            let pulseRaw = (elapsed.remainder(dividingBy: pulsePeriod * 2) / (pulsePeriod * 2) + 1)
                .truncatingRemainder(dividingBy: 1)
            let pulseVal = enablePulse
                ? (0.5 - 0.5 * cos(pulseRaw * 2 * Double.pi))
                : 0.0
            let pulseBase = enablePulse ? (0.52 + 0.48 * pulseVal) : 1.0
            GeometryReader { geo in
                let dim = max(geo.size.width, geo.size.height) + spread * 3.0
                let phaseDeg = enableRotate ? phase * 360.0 : 0.0
                ZStack {
                    if enableRotate {
                        let span0 = 0.0
                        let span1 = 0.18
                        let span2 = 0.52
                        let span3 = 0.82
                        let span4 = 1.0
                        let a0 = (span * span0) / full
                        let a1 = (span * span1) / full
                        let a2 = (span * span2) / full
                        let a3 = (span * span3) / full
                        let a4 = (span * span4) / full
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: a0),
                                .init(color: head.opacity(0.18 * pulseBase), location: a1),
                                .init(color: mid.opacity(0.55 + 0.45 * pulseBase), location: a2),
                                .init(color: tail.opacity((0.32 + 0.50 * pulseBase) * 0.88), location: a3),
                                .init(color: tail.opacity(0.14 * pulseBase), location: a4),
                                .init(color: .clear, location: min(a4 + 0.002, 1)),
                                .init(color: .clear, location: 1)
                            ],
                            center: .center,
                            angle: .degrees(phaseDeg)
                        )
                        .frame(width: dim, height: dim)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    } else {
                        AngularGradient(
                            colors: [
                                head.opacity(0.30 * pulseBase),
                                mid.opacity(0.85 * pulseBase),
                                tail.opacity(0.60 * pulseBase),
                                mid.opacity(0.85 * pulseBase),
                                head.opacity(0.30 * pulseBase)
                            ],
                            center: .center,
                            angle: .degrees(0)
                        )
                        .frame(width: dim, height: dim)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
                .mask(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.black, lineWidth: size.borderWidth)
                )
                .blur(radius: 0.6)
                .opacity(0.92 * size.strength)
                .compositingGroup()
            }
        }
    }

    @ViewBuilder
    private func glowOverlay(radius: CGFloat) -> some View {
        let size = BorderBeamSize.large
        let colors = palette.glowColors
        TimelineView(.animation) { tl in
            let elapsed = tl.date.timeIntervalSinceReferenceDate
            let breathePeriod = size.duration * 0.9
            let breatheRaw = (elapsed.remainder(dividingBy: breathePeriod * 2) / (breathePeriod * 2) + 1)
                .truncatingRemainder(dividingBy: 1)
            let breatheVal = 0.5 - 0.5 * cos(breatheRaw * 2 * Double.pi)
            let breatheBase = 0.35 + 0.65 * breatheVal
            let pulsePeriod = size.duration * 0.42
            let pulseRaw = (elapsed.remainder(dividingBy: pulsePeriod * 2) / (pulsePeriod * 2) + 1)
                .truncatingRemainder(dividingBy: 1)
            let pulseVal = 0.5 - 0.5 * cos(pulseRaw * 2 * Double.pi)
            let pulseMul = enablePulse ? (0.50 + 0.50 * pulseVal) : 1.0

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            .opacity(breatheBase * size.strength * pulseMul)
                    )
                    .padding(size.glowRadius * 0.8)
                    .blur(radius: size.glowRadius + 4)
                    .opacity(0.55 * size.strength)

                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                palette.beamColors.first ?? .clear,
                                palette.beamColors.count > 1 ? palette.beamColors[1] : .clear,
                                palette.beamColors.last ?? .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size.borderWidth * 0.8
                    )
                    .opacity(0.32 * size.strength * breatheBase * pulseMul)
                    .blur(radius: 0.6)
            }
        }
    }
}
