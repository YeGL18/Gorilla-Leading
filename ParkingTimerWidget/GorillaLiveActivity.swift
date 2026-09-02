import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Design tokens (ported from design/live-activities-preview.html)

enum GorillaLADesign {
    static let timerColor = Color(red: 234/255, green: 234/255, blue: 234/255)  // #EAEAEA
    static let pauseGlyph = Color(red: 29/255,  green: 27/255,  blue: 32/255)   // #1D1B20
    /// Rainbow gradient for the parking detail text (look-screen 1.svg paint0_linear)
    static let infoGradient = LinearGradient(
        colors: [
            Color(red: 190/255, green: 190/255, blue: 190/255),  // #BEBEBE
            Color(red: 237/255, green: 117/255, blue: 250/255),  // #ED75FA
            Color(red: 246/255, green: 43/255,  blue: 106/255),  // #F62B6A
            Color(red: 247/255, green: 155/255, blue: 28/255),   // #F79B1C
            Color(red: 3/255,   green: 170/255, blue: 246/255),  // #03AAF6
            Color(red: 219/255, green: 127/255, blue: 251/255),  // #DB7FFB
        ],
        startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - Live Activity

struct GorillaLiveActivity: Widget {
    let kind: String = "GorillaLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GorillaActivityAttributes.self) { context in
            // Lock Screen banner — identical layout to the expanded island.
            // Background: pure transparent (system Liquid Glass shows through).
            GorillaLockScreenView(state: context.state)
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — leading: tile icon + state name.
                // Padding kept near zero to use the island's extreme margins;
                // text scales down instead of truncating.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        tileIcon(context.state.state, size: 30, symbolSize: 13)
                        Text(context.state.state.label)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.leading, 2)
                }
                // Expanded — trailing: big live timer
                DynamicIslandExpandedRegion(.trailing) {
                    HStack {
                        Spacer(minLength: 0)
                        timerText(context.state, size: 28, color: GorillaLADesign.timerColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.trailing, 2)
                    }
                }
                // Expanded — bottom: full-height gorilla watermark pinned to
                // the top-right + contextual info row pinned to the bottom.
                // ALL children are fixed-size — no Spacer / infinity frames:
                // flexible elements have collapsed this region on-device
                // before, wiping the text and the watermark. The watermark
                // stays layout-affecting so the island keeps its full height
                // (camera cutout lands on the gorilla's eye — intentional).
                DynamicIslandExpandedRegion(.bottom) {
                    ZStack(alignment: .topTrailing) {
                        Image("GorillaWatermark")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 148, height: 160)
                            .opacity(0.14)
                        GorillaInfoRow(state: context.state)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 4)
                            .frame(height: 160, alignment: .bottom)
                    }
                }
            } compactLeading: {
                // P icon + "泊車中" text
                HStack(spacing: 4) {
                    Image(systemName: context.state.state.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(context.state.state.color)
                    Text(context.state.state.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            } compactTrailing: {
                // Timer: live-updating via TimelineView (compact auto-refresh)
                compactTimerText(context.state)
            } minimal: {
                Image(systemName: context.state.state.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(context.state.state.color)
            }
        }
    }

    /// Test-page style tile icon: colored tile + white SF Symbol.
    /// Exception: 停留中 pause bars are black on the yellow tile.
    private func tileIcon(_ state: GorillaActivityState, size: CGFloat, symbolSize: CGFloat) -> some View {
        Image(systemName: state.symbol)
            .font(.system(size: symbolSize, weight: .bold))
            .foregroundStyle(state == .stationary ? GorillaLADesign.pauseGlyph : .white)
            .frame(width: size, height: size)
            .background(state.color, in: RoundedRectangle(cornerRadius: size * 9 / 34, style: .continuous))
    }

    /// Live-updating monospaced timer (HH:MM:SS style).
    private func timerText(_ state: GorillaActivityAttributes.ContentState, size: CGFloat, color: Color) -> some View {
        Text(state.startDate, style: .timer)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
    }

    /// Compact timer: lives in the compact trailing region.
    /// Uses native .timer for reliable auto-update.
    private func compactTimerText(_ state: GorillaActivityAttributes.ContentState) -> some View {
        Text(state.startDate, style: .timer)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(state.state.color)
            .lineLimit(1)
    }
}

// MARK: - Lock Screen view (pure transparent, same layout as Expanded)

struct GorillaLockScreenView: View {
    let state: GorillaActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            // Top row: tile icon + state name | big timer
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: state.state.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(state.state == .stationary ? GorillaLADesign.pauseGlyph : .white)
                        .frame(width: 34, height: 34)
                        .background(state.state.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(state.state.label)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Text(state.startDate, style: .timer)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(GorillaLADesign.timerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            GorillaInfoRow(state: state)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(alignment: .topTrailing) {
            // Soft dark halo keeps the white silhouette legible on light
            // wallpapers behind the transparent glass.
            Image("GorillaWatermark")
                .resizable()
                .scaledToFill()
                .frame(width: 148, height: 160)
                .opacity(0.25)
                .shadow(color: .black.opacity(0.35), radius: 2)
        }
    }
}

// MARK: - Shared bottom info row (one variant per state)
// All rows are LEFT-ALIGNED with fixed 30pt gaps (per approved design).
// Missing live data falls back to the design-reference sample values.

struct GorillaInfoRow: View {
    let state: GorillaActivityAttributes.ContentState

    var body: some View {
        switch state.state {
        case .parking:
            // location white · rainbow-gradient area/floor/spot, left aligned.
            // Missing recognition data renders as "-".
            HStack(spacing: 20) {
                Text(state.location ?? "-")
                    .foregroundStyle(.white)
                Text(parkingDetailText)
                    .foregroundStyle(GorillaLADesign.infoGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 16))
            .frame(maxWidth: .infinity, alignment: .leading)

        case .nonAutomotiveParking:
            // Same layout as parking but without floor/spot (non-automotive stops have no floor detection)
            HStack(spacing: 20) {
                Text(state.location ?? "-")
                    .foregroundStyle(.white)
                Text(state.area ?? "-")
                    .foregroundStyle(GorillaLADesign.infoGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 16))
            .frame(maxWidth: .infinity, alignment: .leading)

        case .driving:
            // speed · road name (larger) · eta — all left aligned
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                valueUnit(state.speedKmh.map(String.init), "km/h")
                Text(state.road ?? "-")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                valueUnit(state.etaMinutes.map(String.init), "mins")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .stationary:
            // destination label above distance · road · eta — left aligned
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("目的地: \(state.destinationName ?? "-")")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Text(state.distanceText ?? "-")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(state.road ?? "-")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                valueUnit(state.etaMinutes.map(String.init), "mins")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .walking:
            // road name + eta — same layout as driving but no speed
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(state.road ?? "-")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                valueUnit(state.etaMinutes.map(String.init), "mins")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .cycling:
            // speed + road name + eta — same as driving
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                valueUnit(state.speedKmh.map(String.init), "km/h")
                Text(state.road ?? "-")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                valueUnit(state.etaMinutes.map(String.init), "mins")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "P1區域 ␣ B2 · B1258" — real recognition data, one wide em-gap after
    /// the area, normal " · " between floor and spot. "-" when not detected.
    private var parkingDetailText: String {
        let area = state.area ?? "-"
        let floor = state.floor ?? "-"
        let spot = state.spot ?? "-"
        return area + "\u{2003}\u{2003}" + floor + " · " + spot
    }

    /// Bold number + smaller unit, e.g. "39 mins"; "-" when data is missing.
    private func valueUnit(_ value: String?, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value ?? "-")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            if value != nil {
                Text(unit)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

// MARK: - Previews

private let parkingPreview = GorillaActivityAttributes.ContentState(
    state: .parking, startDate: .now, location: "台北101", area: "P1區域", floor: "B2", spot: "B1258"
)
private let drivingPreview = GorillaActivityAttributes.ContentState(
    state: .driving, startDate: .now, speedKmh: 2, road: "Sai Sha Rd 599", etaMinutes: 39
)
private let stationaryPreview = GorillaActivityAttributes.ContentState(
    state: .stationary, startDate: .now, location: "台北101", road: "Sai Sha Rd 599",
    etaMinutes: 39, destinationName: "家", distanceText: "46.1 km"
)
private let nonAutomotivePreview = GorillaActivityAttributes.ContentState(
    state: .nonAutomotiveParking, startDate: .now, location: "中央公園", area: "入口廣場"
)
private let walkingPreview = GorillaActivityAttributes.ContentState(
    state: .walking, startDate: .now, road: "Sai Sha Rd 599", etaMinutes: 15
)
private let cyclingPreview = GorillaActivityAttributes.ContentState(
    state: .cycling, startDate: .now, speedKmh: 15, road: "Tolo Highway", etaMinutes: 8
)

#Preview(as: .dynamicIsland(.compact), using: GorillaActivityAttributes()) {
    GorillaLiveActivity()
} contentStates: {
    parkingPreview
    drivingPreview
    stationaryPreview
    nonAutomotivePreview
    walkingPreview
    cyclingPreview
}

#Preview(as: .dynamicIsland(.expanded), using: GorillaActivityAttributes()) {
    GorillaLiveActivity()
} contentStates: {
    parkingPreview
    drivingPreview
    stationaryPreview
    nonAutomotivePreview
    walkingPreview
    cyclingPreview
}

#Preview(as: .content, using: GorillaActivityAttributes()) {
    GorillaLiveActivity()
} contentStates: {
    parkingPreview
    drivingPreview
    stationaryPreview
    nonAutomotivePreview
    walkingPreview
    cyclingPreview
}
