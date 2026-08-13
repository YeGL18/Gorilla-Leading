import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity

struct GorillaLiveActivity: Widget {
    let kind: String = "GorillaLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GorillaActivityAttributes.self) { context in
            // Lock Screen / banner — transparent liquid-glass backplate,
            // layout mirrors the expanded Dynamic Island.
            GorillaLockScreenView(state: context.state)
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — leading: icon + title
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        Image(systemName: context.state.state.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(context.state.state.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(context.state.state.label)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 20)
                }
                // Expanded — trailing: big live timer
                DynamicIslandExpandedRegion(.trailing) {
                    HStack {
                        Spacer()
                        timerText(context.state, size: 30, color: .white)
                            .padding(.trailing, 20)
                    }
                }
                // Expanded — bottom: contextual info row
                DynamicIslandExpandedRegion(.bottom) {
                    GorillaInfoRow(state: context.state, dimmed: false)
                        .padding(.horizontal, 20)
                }
            } compactLeading: {
                HStack(spacing: 6) {
                    Image(systemName: context.state.state.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(context.state.state.color)
                    Text(context.state.state.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.leading, 12)
            } compactTrailing: {
                timerText(context.state, size: 14, color: context.state.state.color)
                    .padding(.trailing, 12)
            } minimal: {
                Image(systemName: context.state.state.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(context.state.state.color)
            }
        }
    }

    /// Live-updating monospaced timer (HH:MM:SS style).
    private func timerText(_ state: GorillaActivityAttributes.ContentState, size: CGFloat, color: Color) -> some View {
        Text(state.startDate, style: .timer)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Lock Screen view (transparent liquid glass)

struct GorillaLockScreenView: View {
    let state: GorillaActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: state.state.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(state.state.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Spacer()

                Text(state.startDate, style: .timer)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 12)

            // Destination / context row — slightly lighter in stationary state.
            GorillaInfoRow(state: state, dimmed: state.state == .stationary)
        }
        .padding(16)
    }
}

// MARK: - Shared bottom info row

struct GorillaInfoRow: View {
    let state: GorillaActivityAttributes.ContentState
    /// Stationary state renders the destination a touch lighter.
    let dimmed: Bool

    private var infoColor: Color {
        dimmed ? .white.opacity(0.55) : .white.opacity(0.85)
    }

    var body: some View {
        switch state.state {
        case .driving:
            HStack {
                speedBlock
                Spacer()
                Text(state.road ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                etaBlock
            }
        default:
            // parking / stationary: 台北101  P1區域  B2 · B1258
            HStack(spacing: 12) {
                if let location = state.location {
                    Text(location).foregroundStyle(infoColor)
                }
                if let area = state.area {
                    Text(area).foregroundStyle(infoColor)
                }
                if let floor = state.floor {
                    Text(floor).foregroundStyle(infoColor)
                }
                if let spot = state.spot {
                    Text("· \(spot)").foregroundStyle(infoColor)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
        }
    }

    private var speedBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(state.speedKmh ?? 0)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text("km/h")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var etaBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(state.etaMinutes ?? 0)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text("mins")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
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
    state: .stationary, startDate: .now, location: "台北101", area: "P1區域", floor: "B2", spot: "B1258"
)

#Preview(as: .dynamicIsland(.compact), using: GorillaActivityAttributes()) {
    GorillaLiveActivity()
} contentStates: {
    parkingPreview
    drivingPreview
    stationaryPreview
}

#Preview(as: .dynamicIsland(.expanded), using: GorillaActivityAttributes()) {
    GorillaLiveActivity()
} contentStates: {
    parkingPreview
    drivingPreview
    stationaryPreview
}

#Preview(as: .content, using: GorillaActivityAttributes()) {
    GorillaLiveActivity()
} contentStates: {
    parkingPreview
    drivingPreview
    stationaryPreview
}
