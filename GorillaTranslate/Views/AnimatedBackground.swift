import SwiftUI

struct AnimatedBackground: View {
    @ObservedObject var clock: AnimationClock
    var colorSchemeIndex: Int = 0
    var isVoiceRecording: Bool = false
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
        switch colorSchemeIndex {
        case 0:
            return [
                ("BEBC3F", 0.3),
                ("5CAEB7", 0.3),
                ("0098FF", 0.3)
            ]
        case 1:
            return [
                ("D4C3B8", 0.6),
                ("F8FBDC", 0.6),
                ("9ACDDE", 0.6)
            ]
        default:
            return [
                ("BEBC3F", 0.3),
                ("5CAEB7", 0.3),
                ("0098FF", 0.3)
            ]
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
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let elapsed = clock.elapsed
            let colors = orbColors

            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Circle()
                    .fill(Color(hex: colors[0].hex).opacity(colors[0].opacity))
                    .blur(radius: 100)
                    .frame(width: 450, height: 450)
                    .offset(
                        x: w * 0.05 + CGFloat(sin(elapsed * 0.449)) * w * 0.45,
                        y: h * 0.1 + CGFloat(cos(elapsed * 0.35)) * h * 0.3
                    )

                Circle()
                    .fill(Color(hex: colors[1].hex).opacity(colors[1].opacity))
                    .blur(radius: 100)
                    .frame(width: 500, height: 500)
                    .offset(
                        x: w * 0.05 + CGFloat(sin(elapsed * 0.393 + 2.1)) * w * 0.35,
                        y: h * 0.05 + CGFloat(cos(elapsed * 0.31 + 2.1)) * h * 0.3
                    )

                Circle()
                    .fill(Color(hex: colors[2].hex).opacity(colors[2].opacity))
                    .blur(radius: 100)
                    .frame(width: 420, height: 420)
                    .offset(
                        x: -w * 0.05 + CGFloat(sin(elapsed * 0.524 + 4.2)) * w * 0.4,
                        y: h * 0.02 + CGFloat(cos(elapsed * 0.42 + 4.2)) * h * 0.32
                    )
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    AnimatedBackground(clock: {
        let c = AnimationClock()
        c.start()
        return c
    }())
}
