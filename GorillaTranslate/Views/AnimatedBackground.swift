import SwiftUI

struct AnimatedBackground: View {
    let clock: AnimationClock
    var colorSchemeIndex: Int = 0
    var isVoiceRecording: Bool = false
    var orbEnabled: Bool = true
    var useTimeBasedOrb: Bool = false
    var phaseManager: TimePhaseManager? = nil
    var orbSizeMultiplier: CGFloat = 1.0
    var orbColorPreset: Int = 0
    var overlapGlowEnabled: Bool = true
    var customOrbColors: [(hex: String, opacity: Double)]? = nil
    var backgroundColorHex: String? = nil
    @AppStorage("orbCanvasDitherEnabled") private var canvasDitherEnabled = true
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var orbColors: [(hex: String, opacity: Double)] {
        if let customOrbColors, customOrbColors.count == 3 { return customOrbColors }
        if isVoiceRecording {
            return [
                ("FF825C", 0.3),
                ("FFC46D", 0.3),
                ("3497FF", 0.3)
            ]
        }
        switch orbColorPreset {
        case 1: return [("FF8C00", 0.35), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        case 2: return [("9BF783", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        case 3: return [("99E695", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        case 4: return [("97D5AB", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        default: return [("BEBC3F", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        }
    }

    private var gradientColors: [Color] {
        if let backgroundColorHex {
            return [Color(hex: backgroundColorHex), Color(hex: backgroundColorHex)]
        }
        if isDark {
            return [Color.black, Color(hex: "0a0a1a")]
        } else {
            return [Color(hex: "f5f5f7"), Color(hex: "e0e3e8")]
        }
    }

    var body: some View {
        if useTimeBasedOrb, let phaseManager = phaseManager {
            TimeBasedOrbView(phaseManager: phaseManager, clock: clock, orbEnabled: orbEnabled, orbSizeMultiplier: orbSizeMultiplier)
        } else {
            legacyOrbView
        }
    }

    private var legacyOrbView: some View {
        GeometryReader { _ in
            let colors = orbColors
            let glowStrength = overlapGlowEnabled ? (isDark ? 1.6 : 1.05) : 1.0
            let fills = colors.map { Color(hex: $0.hex).opacity(min(1, $0.opacity * glowStrength) * (orbEnabled ? 1 : 0)) }

            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ClockDrivenContent(clock: clock, running: orbEnabled) { elapsed in
                    if canvasDitherEnabled {
                        LegacyOrbCanvas(elapsed: elapsed, fills: fills,
                                        multiplier: orbSizeMultiplier, mixing: overlapGlowEnabled)
                    } else {
                        LegacyOrbField(elapsed: elapsed, fills: fills,
                                       multiplier: orbSizeMultiplier, mixing: overlapGlowEnabled)
                    }
                }
            }
            .modifier(OptionalOrbDitherModifier(enabled: canvasDitherEnabled))
        }
        .ignoresSafeArea()
    }
}

// Keep the native branch free of offscreen compositing and noise shaders.
struct OptionalOrbDitherModifier: ViewModifier {
    var enabled: Bool
    @Environment(\.displayScale) private var displayScale

    private var shader: Shader {
        var shader = ShaderLibrary.orbDither(.float(Float(displayScale)))
        shader.dithersColor = true
        return shader
    }

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup(opaque: true, colorMode: .extendedLinear)
                .colorEffect(shader)
        } else {
            content
        }
    }
}

struct LegacyOrbCanvas: View {
    var elapsed: TimeInterval
    var fills: [Color]
    var multiplier: CGFloat
    var mixing: Bool

    var body: some View {
        Canvas(colorMode: .extendedLinear) { context, size in
            let offsets = LegacyOrbField.offsets(at: elapsed, size: size)
            for index in 0..<3 {
                guard let disc = context.resolveSymbol(id: index) else { continue }
                context.draw(disc, at: CGPoint(x: size.width / 2 + offsets[index].x,
                                              y: size.height / 2 + offsets[index].y))
            }
        } symbols: {
            ForEach(0..<3, id: \.self) { index in
                OrbDiscSymbol(fill: fills[index], diameter: [450.0, 500.0, 420.0][index] * multiplier,
                              mixing: mixing)
                    .equatable()
                    .tag(index)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct OrbDiscSymbol: View, Equatable {
    let fill: Color
    let diameter: CGFloat
    let mixing: Bool

    var body: some View {
        Canvas(colorMode: .extendedLinear) { context, _ in
            context.addFilter(.blur(radius: 100, options: .dithersResult))
            context.fill(Path(ellipseIn: CGRect(x: 300, y: 300, width: diameter, height: diameter)),
                         with: .color(fill))
        }
        .frame(width: diameter + 600, height: diameter + 600)
        .blendMode(mixing ? .plusLighter : .normal)
    }
}

/// Native blurred views preserve the pre-Canvas rendering pipeline.
struct LegacyOrbField: View {
    private static let diameters: [CGFloat] = [450, 500, 420]
    var elapsed: TimeInterval
    var fills: [Color]
    var multiplier: CGFloat
    var mixing: Bool

    static func offsets(at elapsed: TimeInterval, size: CGSize) -> [CGPoint] {
        let w = size.width, h = size.height
        return [
            CGPoint(x: w * 0.05 + sin(elapsed * 0.449) * w * 0.45,
                    y: h * 0.1 + cos(elapsed * 0.35) * h * 0.3),
            CGPoint(x: w * 0.05 + sin(elapsed * 0.393 + 2.1) * w * 0.35,
                    y: h * 0.05 + cos(elapsed * 0.31 + 2.1) * h * 0.3),
            CGPoint(x: -w * 0.05 + sin(elapsed * 0.524 + 4.2) * w * 0.4,
                    y: h * 0.02 + cos(elapsed * 0.42 + 4.2) * h * 0.32)
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let offsets = Self.offsets(at: elapsed, size: geometry.size)
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(fills[index])
                        .blur(radius: 100)
                        .frame(width: Self.diameters[index] * multiplier,
                               height: Self.diameters[index] * multiplier)
                        .offset(x: offsets[index].x, y: offsets[index].y)
                        .blendMode(mixing ? .plusLighter : .normal)
                }
            }
            .compositingGroup()
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
