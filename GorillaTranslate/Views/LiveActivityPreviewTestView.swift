import SwiftUI

// MARK: - Test gallery: all Live Activity style × state combinations
// Ported 1:1 from design/live-activities-preview.html

struct LiveActivityPreviewTestView: View {
    private let states: [GorillaActivityState] = [.parking, .driving, .stationary, .nonAutomotiveParking, .walking, .cycling]
    private let anchor = Date(timeIntervalSinceNow: -3723) // 01:02:03 ago

    // MARK: Design tokens (from live-activities-preview.html)

    private let timerColor = Color(red: 234/255, green: 234/255, blue: 234/255)  // #EAEAEA
    private let pauseGlyph = Color(red: 29/255,  green: 27/255,  blue: 32/255)   // #1D1B20
    /// Rainbow gradient from the reference design (look-screen 1.svg paint0_linear).
    /// Kept as a design token for reference — info-row texts currently render white.
    private let infoGradient = LinearGradient(
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

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                // ── Compact ──
                sectionHeader("Compact", dim: "230 × 37 pt · " + String(localized: "膠囊"))
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
                            expandedCard(state: state)
                            stateLabel(state)
                        }
                    }
                }

                // ── Lock Screen ──
                sectionHeader("Lock Screen", dim: "371 × 160 pt · r25 · Liquid Glass")
                VStack(spacing: 16) {
                    ForEach(states, id: \.self) { state in
                        column {
                            lockBackdrop(state: state)
                            stateLabel(state)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 32)
        }
        .background(Color.black)
        .navigationTitle(String(localized: "即時活動樣式"))
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

    // MARK: - Expanded card (371 × 160 · r44 · pure black, no divider)

    @ViewBuilder
    private func expandedCard(state: GorillaActivityState) -> some View {
        cardContent(state: state)
            .frame(width: 371, height: 160)
            .background(alignment: .topTrailing) {
                Image("GorillaWatermark")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 160)
                    .opacity(0.14)
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }

    // MARK: - Lock Screen card (371 × 160 · r25 · Liquid Glass)

    @ViewBuilder
    private func lockCard(state: GorillaActivityState) -> some View {
        cardContent(state: state)
            .frame(width: 371, height: 160)
            .background(alignment: .topTrailing) {
                Image("GorillaWatermark")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 160)
                    .opacity(0.20)
            }
            .background(
                LinearGradient(colors: [.white.opacity(0.46), .white.opacity(0.30)],
                               startPoint: .top, endPoint: .bottom)
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 16)
    }

    /// A dark wallpaper-ish backdrop so the Liquid Glass material has
    /// something to blur (mirrors the HTML stage gradient).
    @ViewBuilder
    private func lockBackdrop(state: GorillaActivityState) -> some View {
        lockCard(state: state)
            .padding(.vertical, 16)
            .padding(.horizontal, 3)
            .background(
                LinearGradient(colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.22),
                    Color(red: 0.05, green: 0.06, blue: 0.11),
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 32, style: .continuous)
            )
    }

    // MARK: - Shared card content (Expanded & Lock are identical layouts)

    @ViewBuilder
    private func cardContent(state: GorillaActivityState) -> some View {
        VStack(spacing: 0) {
            topRow(state: state)
            Spacer()
            bottomRow(state: state)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    /// Top row: tile icon + state name | big timer
    @ViewBuilder
    private func topRow(state: GorillaActivityState) -> some View {
        HStack {
            HStack(spacing: 10) {
                tileIcon(state)
                Text(state.label)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            timerText(anchor, size: 28, color: timerColor)
        }
    }

    /// Test-page style tile icon: colored tile + white SF Symbol.
    /// Exception: 停留中 pause bars are black on the yellow tile.
    @ViewBuilder
    private func tileIcon(_ state: GorillaActivityState) -> some View {
        Image(systemName: state.symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(state == .stationary ? pauseGlyph : .white)
            .frame(width: 34, height: 34)
            .background(state.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Preview the same stable information shown by the widget.
    private func bottomRow(state: GorillaActivityState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(state == .driving || state == .cycling ? "香港國際機場" : "銀湖・天峰",
                  systemImage: state == .driving || state == .cycling ? "flag.checkered" : "mappin.and.ellipse")
                .font(.system(size: 17, weight: .semibold)).lineLimit(2)
            if state == .parking || state == .stationary {
                HStack(spacing: 18) {
                    Label("A", systemImage: "square.grid.2x2")
                    Label("B2", systemImage: "building.2")
                    Label("128", systemImage: "parkingsign.circle")
                }.font(.system(size: 15, weight: .semibold))
            }
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
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
