import SwiftUI

// MARK: - Test gallery: all 12 Live Activity style × state combinations

struct LiveActivityPreviewTestView: View {
    private let states: [GorillaActivityState] = [.parking, .driving, .stationary]
    private let anchor = Date(timeIntervalSinceNow: -3723) // 01:02:03 ago

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                // ── Compact ──
                sectionHeader("Compact", dim: "230 × 37 pt · 膠囊")
                VStack(spacing: 16) {
                    ForEach(states, id: \.self) { state in
                        column {
                            compactView(state: state)
                            stateLabel(state)
                        }
                    }
                }

                // ── Minimal ──
                sectionHeader("Minimal", dim: "45 × 37 pt")
                HStack(spacing: 32) {
                    ForEach(states, id: \.self) { state in
                        column {
                            minimalView(state: state)
                            stateLabel(state)
                        }
                    }
                }

                // ── Expanded ──
                sectionHeader("Expanded", dim: "371 × 160 pt · r44")
                VStack(spacing: 16) {
                    ForEach(states, id: \.self) { state in
                        column {
                            expandedView(state: state)
                            stateLabel(state)
                        }
                    }
                }

                // ── Lock Screen ──
                sectionHeader("Lock Screen", dim: "371 × 100 pt · r22")
                VStack(spacing: 16) {
                    ForEach(states, id: \.self) { state in
                        column {
                            lockScreenView(state: state)
                            stateLabel(state)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .background(Color.black)
        .navigationTitle("即時活動樣式")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Compact (230 × 37)

    @ViewBuilder
    private func compactView(state: GorillaActivityState) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: state.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(state.color)
                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 12)

            Spacer()

            timerText(anchor, size: 14, color: state.color)
                .padding(.trailing, 12)
        }
        .frame(width: 230, height: 37)
        .background(Color.black, in: Capsule())
    }

    // MARK: - Minimal (45 × 37)

    @ViewBuilder
    private func minimalView(state: GorillaActivityState) -> some View {
        Image(systemName: state.symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(state.color)
            .frame(width: 45, height: 37)
            .background(Color.black, in: Capsule())
    }

    // MARK: - Expanded (371 × 160)

    @ViewBuilder
    private func expandedView(state: GorillaActivityState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: icon+label | timer
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(state.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(state.label)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                timerText(anchor, size: 30, color: .white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer()

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 20)

            // Bottom info row
            infoRow(state: state, dimmed: false)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 18)
        }
        .frame(width: 371, height: 160)
        .background(
            LinearGradient(colors: [Color(white: 0.17), Color(white: 0.11)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 44, style: .continuous)
        )
        .overlay(alignment: .top) {
            // Specular highlight
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.08))
                .frame(width: 355, height: 1.5)
                .offset(y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }

    // MARK: - Lock Screen (371 × 100)

    @ViewBuilder
    private func lockScreenView(state: GorillaActivityState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: state.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(state.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Spacer()

                timerText(anchor, size: 24, color: .white)
            }

            Spacer(minLength: 12)

            infoRow(state: state, dimmed: state == .stationary)
        }
        .padding(16)
        .frame(width: 371, height: 100)
        .background(
            LinearGradient(colors: [Color(white: 0.17), Color(white: 0.11)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.08))
                .frame(width: 359, height: 1.5)
                .offset(y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Shared components

    @ViewBuilder
    private func timerText(_ start: Date, size: CGFloat, color: Color) -> some View {
        Text(start, style: .timer)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
    }

    @ViewBuilder
    private func infoRow(state: GorillaActivityState, dimmed: Bool) -> some View {
        let infoColor: Color = dimmed ? .white.opacity(0.55) : .white.opacity(0.85)
        switch state {
        case .driving:
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("2")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("km/h")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text("Sai Sha Rd 599")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("39")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("mins")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        default:
            HStack(spacing: 12) {
                Text("台北101")
                    .foregroundStyle(infoColor)
                Text("P1區域")
                    .foregroundStyle(infoColor)
                Text("B2")
                    .foregroundStyle(infoColor)
                Text("· B1258")
                    .foregroundStyle(infoColor)
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, dim: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text(dim)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func column<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) { content() }
    }

    @ViewBuilder
    private func stateLabel(_ state: GorillaActivityState) -> some View {
        Text(state.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(state.color.opacity(0.8))
    }
}
