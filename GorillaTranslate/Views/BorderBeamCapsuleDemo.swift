import SwiftUI

struct BorderBeamCapsuleDemo: View {
    @Environment(\.colorScheme) private var colorScheme
    var palette: BorderBeamPalette
    var address: String
    var statusTitle: String
    var statusValue: String
    var etaText: String?
    var speedKmh: Double
    var enableRotate: Bool = true
    var enablePulse: Bool = true

    var body: some View {
        let radius: CGFloat = 30
        let horizPadding: CGFloat = 18
        let vertPadding: CGFloat = 14
        let titleFont: Font = .system(size: 16, weight: .bold)
        let metaFont: Font = .system(size: 12, weight: .semibold)

        let textPrimary = palette.primaryText(scheme: colorScheme)
        let textSecondary = palette.secondaryText(scheme: colorScheme)
        let iconTint: Color = {
            switch palette {
            case .mono: return colorScheme == .dark ? .white.opacity(0.85) : .primary.opacity(0.85)
            case .ocean: return Color(red: 0.10, green: 0.42, blue: 0.78).opacity(colorScheme == .dark ? 1 : 0.88)
            case .senshackDark: return Color(red: 0.92, green: 0.80, blue: 0.58)
            }
        }()

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.16))
                Image(systemName: palette == .senshackDark ? "parkingsign.circle.fill" : (palette == .ocean ? "car.circle.fill" : "location.circle.fill"))
                    .font(.system(size: 18))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(address)
                    .font(titleFont)
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(statusTitle)
                        .font(metaFont)
                        .foregroundStyle(textSecondary)
                    Text(statusValue)
                        .font(metaFont.monospacedDigit())
                        .foregroundStyle(textPrimary)
                    if let etaText {
                        Text(etaText)
                            .font(metaFont.monospacedDigit())
                            .foregroundStyle(textPrimary.opacity(0.88))
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(speedKmh)) km/h")
                        .font(metaFont.monospacedDigit())
                        .foregroundStyle(textPrimary)
                }
            }
        }
        .padding(.horizontal, horizPadding)
        .padding(.vertical, vertPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .borderBeam(size: .large,
                    palette: palette,
                    cornerRadius: radius,
                    enableRotate: enableRotate,
                    enablePulse: enablePulse)
    }
}
