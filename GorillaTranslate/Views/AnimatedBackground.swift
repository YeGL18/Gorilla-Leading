import SwiftUI

struct AnimatedBackground: View {
    @ObservedObject var clock: AnimationClock
    var colorSchemeIndex: Int = 0
    var isVoiceRecording: Bool = false
    var orbEnabled: Bool = true
    var useTimeBasedOrb: Bool = false
    var phaseManager: TimePhaseManager? = nil
    var orbSizeMultiplier: CGFloat = 1.0
    var orbColorPreset: Int = 0
    var overlapGlowEnabled: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var orbColors: [(hex: String, opacity: Double)] {
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
        if isDark {
            [Color.black, Color(hex: "0a0a1a")]
        } else {
            [Color(hex: "f5f5f7"), Color(hex: "e0e3e8")]
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
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let elapsed = clock.elapsed
            let colors = orbColors
            let glowStrength = overlapGlowEnabled ? 0.8 : 1.0
            let orbBlend: BlendMode = overlapGlowEnabled ? .plusLighter : .normal

            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Circle()
                    .fill(Color(hex: colors[0].hex).opacity(min(1, colors[0].opacity * glowStrength) * (orbEnabled ? 1 : 0)))
                    .blur(radius: 100)
                    .frame(width: 450 * orbSizeMultiplier, height: 450 * orbSizeMultiplier)
                    .offset(
                        x: w * 0.05 + CGFloat(sin(elapsed * 0.449)) * w * 0.45,
                        y: h * 0.1 + CGFloat(cos(elapsed * 0.35)) * h * 0.3
                    )
                    .blendMode(orbBlend)

                Circle()
                    .fill(Color(hex: colors[1].hex).opacity(min(1, colors[1].opacity * glowStrength) * (orbEnabled ? 1 : 0)))
                    .blur(radius: 100)
                    .frame(width: 500 * orbSizeMultiplier, height: 500 * orbSizeMultiplier)
                    .offset(
                        x: w * 0.05 + CGFloat(sin(elapsed * 0.393 + 2.1)) * w * 0.35,
                        y: h * 0.05 + CGFloat(cos(elapsed * 0.31 + 2.1)) * h * 0.3
                    )
                    .blendMode(orbBlend)

                Circle()
                    .fill(Color(hex: colors[2].hex).opacity(min(1, colors[2].opacity * glowStrength) * (orbEnabled ? 1 : 0)))
                    .blur(radius: 100)
                    .frame(width: 420 * orbSizeMultiplier, height: 420 * orbSizeMultiplier)
                    .offset(
                        x: -w * 0.05 + CGFloat(sin(elapsed * 0.524 + 4.2)) * w * 0.4,
                        y: h * 0.02 + CGFloat(cos(elapsed * 0.42 + 4.2)) * h * 0.32
                    )
                    .blendMode(orbBlend)
            }
        }
        .ignoresSafeArea()
    }
}
