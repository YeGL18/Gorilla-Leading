import SwiftUI

enum BorderBeamSize: Hashable, CaseIterable {
    case large
}

enum BorderBeamPalette: Hashable, CaseIterable, Identifiable {
    case mono
    case ocean
    case senshackDark

    var id: String {
        switch self {
        case .mono: return "mono"
        case .ocean: return "ocean"
        case .senshackDark: return "senshack"
        }
    }

    var title: String {
        switch self {
        case .mono: return "Mono（停留中）"
        case .ocean: return "Ocean（開車中）"
        case .senshackDark: return "Senshack（泊車中）"
        }
    }
}

extension BorderBeamSize {
    var beamSpanDegrees: Double {
        return 62
    }

    var borderWidth: CGFloat {
        return 2.2
    }

    var strokeFromCenter: CGFloat {
        return 28
    }

    var glowRadius: CGFloat {
        return 18
    }

    var duration: Double {
        return 4.2
    }

    var strength: Double {
        return 1.0
    }
}

extension BorderBeamPalette {
    var themeIsDark: Bool {
        switch self {
        case .mono: return false
        case .ocean: return false
        case .senshackDark: return true
        }
    }

    var surfaceTint: Color {
        switch self {
        case .mono:
            return Color.primary.opacity(0.05)
        case .ocean:
            return Color(red: 0.18, green: 0.53, blue: 0.78).opacity(0.14)
        case .senshackDark:
            return Color.black.opacity(0.72)
        }
    }

    var hairlineColor: Color {
        switch self {
        case .mono:
            return Color.primary.opacity(0.14)
        case .ocean:
            return Color(red: 0.20, green: 0.52, blue: 0.80).opacity(0.55)
        case .senshackDark:
            return Color.white.opacity(0.16)
        }
    }

    var beamColors: [Color] {
        switch self {
        case .mono:
            return [
                Color.primary.opacity(0.95),
                Color.primary.opacity(0.55),
                Color.primary.opacity(0.20),
                Color.primary.opacity(0.70)
            ]
        case .ocean:
            return [
                Color(red: 0.05, green: 0.30, blue: 0.62).opacity(0.95),
                Color(red: 0.10, green: 0.55, blue: 0.78).opacity(0.95),
                Color(red: 0.50, green: 0.70, blue: 0.92).opacity(0.55),
                Color(red: 0.30, green: 0.48, blue: 0.84).opacity(0.95)
            ]
        case .senshackDark:
            return [
                Color(red: 0.86, green: 0.78, blue: 0.58).opacity(0.95),
                Color(red: 0.62, green: 0.46, blue: 0.86).opacity(0.85),
                Color(red: 0.90, green: 0.44, blue: 0.36).opacity(0.55),
                Color(red: 0.88, green: 0.72, blue: 0.48).opacity(0.95)
            ]
        }
    }

    var glowColors: [Color] {
        switch self {
        case .mono:
            return [Color.primary.opacity(0.55),
                    Color.primary.opacity(0.12)]
        case .ocean:
            return [Color(red: 0.20, green: 0.55, blue: 0.86).opacity(0.70),
                    Color(red: 0.40, green: 0.65, blue: 0.96).opacity(0.18)]
        case .senshackDark:
            return [Color(red: 0.82, green: 0.55, blue: 0.95).opacity(0.70),
                    Color(red: 0.82, green: 0.58, blue: 0.30).opacity(0.18)]
        }
    }

    func primaryText(scheme: ColorScheme) -> Color {
        switch self {
        case .mono:
            return .primary
        case .ocean:
            return scheme == .dark ? .white : Color(red: 0.08, green: 0.22, blue: 0.36)
        case .senshackDark:
            return .white
        }
    }

    func secondaryText(scheme: ColorScheme) -> Color {
        switch self {
        case .mono:
            return .secondary
        case .ocean:
            return scheme == .dark ? Color.white.opacity(0.72) : Color(red: 0.10, green: 0.30, blue: 0.48).opacity(0.78)
        case .senshackDark:
            return Color.white.opacity(0.70)
        }
    }
}

struct BorderBeamModifier: ViewModifier {
    var size: BorderBeamSize = .large
    var palette: BorderBeamPalette = .ocean
    var strength: Double? = nil
    var duration: Double? = nil
    var cornerRadius: CGFloat
    var enableRotate: Bool = true
    var enablePulse: Bool = true
    @State private var phase: CGFloat = 0
    @State private var breathe: CGFloat = 0
    @State private var pulse: CGFloat = 0

    func body(content: Content) -> some View {
        let effectiveStrength = strength ?? size.strength
        let effectiveDuration = duration ?? size.duration

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.surfaceTint)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(palette.hairlineColor, lineWidth: 0.6)

            content
                .overlay(alignment: .center) {
                    beamLayer(strength: effectiveStrength, pulse: pulse)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .center) {
                    glowLayer(strength: effectiveStrength, breathe: breathe, pulse: pulse)
                        .allowsHitTesting(false)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            if enableRotate {
                withAnimation(.linear(duration: effectiveDuration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            withAnimation(.easeInOut(duration: effectiveDuration * 0.9).repeatForever(autoreverses: true)) {
                breathe = 1
            }
            if enablePulse {
                withAnimation(.easeInOut(duration: effectiveDuration * 0.42).repeatForever(autoreverses: true)) {
                    pulse = 1
                }
            }
        }
        .onChange(of: enableRotate) { _, newValue in
            if newValue {
                withAnimation(.linear(duration: effectiveDuration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .onChange(of: enablePulse) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: effectiveDuration * 0.42).repeatForever(autoreverses: true)) {
                    pulse = 1
                }
            }
        }
    }

    @ViewBuilder
    private func beamLayer(strength: Double, pulse: CGFloat) -> some View {
        let spread = size.strokeFromCenter
        let span: Double = enableRotate ? size.beamSpanDegrees : 360.0
        let head = palette.beamColors.first ?? .white
        let mid = palette.beamColors.count > 1 ? palette.beamColors[1] : head
        let tail = palette.beamColors.count > 2 ? palette.beamColors[2] : head.opacity(0.5)
        let pulseBase = enablePulse ? (0.52 + 0.48 * Double(pulse)) : 1.0
        let full = 360.0
        GeometryReader { geo in
            let dim = max(geo.size.width, geo.size.height) + spread * 3.0
            let phaseDeg = enableRotate ? Double(phase * 360) : 0.0
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
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black, lineWidth: size.borderWidth)
                )
                .blur(radius: 0.6)
                .opacity(0.92 * strength)
                .compositingGroup()
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
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black, lineWidth: size.borderWidth)
                )
                .blur(radius: 0.6)
                .opacity(0.92 * strength)
                .compositingGroup()
            }
        }
    }

    @ViewBuilder
    private func glowLayer(strength: Double, breathe: CGFloat, pulse: CGFloat) -> some View {
        let colors = palette.glowColors
        let breatheBase = 0.35 + 0.65 * Double(breathe)
        let pulseMul = enablePulse ? (0.50 + 0.50 * Double(pulse)) : 1.0

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(breatheBase * strength * pulseMul)
                )
                .padding(size.glowRadius * 0.8)
                .blur(radius: size.glowRadius + 4)
                .opacity(0.55 * strength)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                .opacity(0.32 * strength * breatheBase * pulseMul)
                .blur(radius: 0.6)
        }
    }
}

extension View {
    func borderBeam(
        size: BorderBeamSize = .large,
        palette: BorderBeamPalette = .ocean,
        strength: Double? = nil,
        duration: Double? = nil,
        cornerRadius: CGFloat,
        enableRotate: Bool = true,
        enablePulse: Bool = true
    ) -> some View {
        modifier(BorderBeamModifier(size: size,
                                    palette: palette,
                                    strength: strength,
                                    duration: duration,
                                    cornerRadius: cornerRadius,
                                    enableRotate: enableRotate,
                                    enablePulse: enablePulse))
    }

    @ViewBuilder
    func safeGlassEffect<S: Shape>(tint tintColor: Color? = nil, in shape: S) -> some View {
        if let tint = tintColor {
            ZStack {
                self
                    .glassEffect(.regular, in: shape)
                tint
                    .opacity(0.45)
                    .mask(shape.fill())
                    .allowsHitTesting(false)
            }
            .compositingGroup()
        } else {
            self.glassEffect(.regular, in: shape)
        }
    }
}
