import SwiftUI
import MapKit
import CoreLocation
import UserNotifications

struct LeadingJourneyMotion {
    struct Turn { let distance: Double; let angle: Double }
    struct Sample { let distance: Double; let speedKmh: Double }
    private let stations: [Double]
    private let speeds: [Double]
    private let times: [Double]
    var duration: Double { times.last ?? 0 }

    init(distance: Double, turns: [Turn]) {
        let length = max(0.01, distance)
        let count = max(2, Int(ceil(length / 2)))
        let stations = (0...count).map { length * Double($0) / Double(count) }
        // A repeatable 48–62 km/h cruise wave, not random changes to the label.
        // Both the displayed speed and marker motion integrate this same profile.
        var speeds = stations.map { distance in
            (55 + 7 * cos(2 * .pi * (distance - 110) / 240)) / 3.6
        }
        for turn in turns where turn.angle > 20 {
            let index = min(count, max(0, Int((turn.distance / length * Double(count)).rounded())))
            speeds[index] = min(speeds[index], max(3.7, 11.8 - turn.angle / 14))
        }
        speeds[0] = 0
        speeds[count] = 0
        // Constrain acceleration and braking before integrating distance into time.
        for i in 1...count {
            speeds[i] = min(speeds[i], sqrt(speeds[i - 1] * speeds[i - 1] + 2 * 2.6 * (stations[i] - stations[i - 1])))
        }
        for i in stride(from: count - 1, through: 0, by: -1) {
            speeds[i] = min(speeds[i], sqrt(speeds[i + 1] * speeds[i + 1] + 2 * 3.8 * (stations[i + 1] - stations[i])))
        }
        var times = [0.0]
        for i in 1...count {
            let dt = 2 * (stations[i] - stations[i - 1]) / max(0.01, speeds[i - 1] + speeds[i])
            times.append(times[i - 1] + dt)
        }
        self.stations = stations
        self.speeds = speeds
        self.times = times
    }

    func sample(at elapsed: Double) -> Sample {
        guard elapsed > 0 else { return Sample(distance: 0, speedKmh: 0) }
        guard elapsed < duration else { return Sample(distance: stations.last ?? 0, speedKmh: 0) }
        var lower = 0, upper = times.count - 1
        while upper - lower > 1 {
            let middle = (lower + upper) / 2
            if times[middle] <= elapsed { lower = middle } else { upper = middle }
        }
        let dt = elapsed - times[lower]
        let acceleration = (speeds[upper] - speeds[lower]) / (times[upper] - times[lower])
        return Sample(distance: stations[lower] + speeds[lower] * dt + 0.5 * acceleration * dt * dt,
                      speedKmh: max(0, speeds[lower] + acceleration * dt) * 3.6)
    }
}

private enum LeadingTourPage: Int, CaseIterable {
    case welcome
    case journey
    case parking
    case memory
    case privacy
}

struct GorillaOnboardingView: View {
    let isReplay: Bool
    let onComplete: () -> Void

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: LeadingTourPage
    @State private var pageVisible = false
    @State private var direction = 1
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    init(isReplay: Bool = false, initialPage: Int = 0, onComplete: @escaping () -> Void) {
        self.isReplay = isReplay
        self.onComplete = onComplete
        _page = State(initialValue: LeadingTourPage(rawValue: initialPage) ?? .welcome)
    }

    private var isLastPage: Bool { page == .privacy }

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height
            let compactHeight = geo.size.height < 720

            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, isWide ? 24 : 20)
                        .padding(.top, 8)

                    ZStack {
                        pageContent(isWide: isWide, compactHeight: compactHeight)
                            .id(page)
                            .transition(pageTransition)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .bottom) {
                actionBar
                    .frame(maxWidth: 520)
                    .padding(.horizontal, isWide ? 40 : 24)
                    .padding(.bottom, 8)
            }
            .gesture(pageSwipeGesture)
        }
        .task(id: page) {
            pageVisible = false
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(90))
            }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.58, dampingFraction: 0.84)) {
                pageVisible = true
            }
            if page == .privacy {
                await refreshNotificationStatus()
            }
        }
        .interactiveDismissDisabled(!isReplay)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                goBack()
            } label: {
                Image(systemName: page == .welcome && isReplay ? "xmark" : "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .opacity(page == .welcome && !isReplay ? 0 : 1)
            .disabled(page == .welcome && !isReplay)
            .accessibilityLabel(page == .welcome && isReplay ? "關閉" : "上一頁")

            HStack(spacing: 7) {
                ForEach(LeadingTourPage.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= page.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 5)
                        .animation(.smooth(duration: 0.35), value: page)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(page.rawValue + 1) 頁，共 \(LeadingTourPage.allCases.count) 頁")

            Button("略過") {
                finish()
            }
            .font(.callout.weight(.semibold))
            .opacity(isLastPage ? 0 : 1)
            .disabled(isLastPage)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func pageContent(isWide: Bool, compactHeight: Bool) -> some View {
        switch page {
        case .welcome:
            tourLayout(
                title: "歡迎使用 Gorilla Leading",
                detail: "一個理解行程、泊車與你每日移動節奏的駕駛助手。",
                facts: [
                    LeadingFact(icon: "location.north.line.fill", color: .blue, title: "一路跟隨", detail: "把路線、時速與目的地放在同一個畫面。"),
                    LeadingFact(icon: "parkingsign.circle.fill", color: .green, title: "泊得更從容", detail: "記住停車位置，也替你留意附近咪錶位。")
                ],
                isWide: isWide,
                compactHeight: compactHeight
            ) {
                LeadingWelcomeVisual()
            }

        case .journey:
            tourLayout(
                title: "路況在變，畫面跟住你走",
                detail: "地圖、時速與目的地預測會隨行程更新，重要資訊逐層浮現。",
                facts: [
                    LeadingFact(icon: "speedometer", color: .cyan, title: "流暢時速", detail: "數字連續滾動，變化一眼睇清。"),
                    LeadingFact(icon: "point.topleft.down.to.point.bottomright.curvepath", color: .indigo, title: "目的地預測", detail: "從你的慣常路線提供合時提示。")
                ],
                isWide: isWide,
                compactHeight: compactHeight
            ) {
                LeadingJourneyVisual()
            }

        case .parking:
            tourLayout(
                title: "附近咪錶位，未到埗先看見",
                detail: "只顯示合適範圍內的泊位，狀態、車型與路線都留在地圖上。",
                facts: [
                    LeadingFact(icon: "circle.fill", color: .green, title: "綠色", detail: "有空置而且適合所選車型。"),
                    LeadingFact(icon: "circle.fill", color: .yellow, title: "黃色", detail: "空置，但不適用於所選車型。")
                ],
                isWide: isWide,
                compactHeight: compactHeight
            ) {
                LeadingParkingVisual()
            }

        case .memory:
            tourLayout(
                title: "由停車一刻，記到返來一刻",
                detail: "泊車記憶、樓層探測與 Live Activity，讓重要狀態一直留在手邊。",
                facts: [
                    LeadingFact(icon: "car.side.fill", color: .orange, title: "泊車記憶", detail: "位置、時間、相片與停車場自動歸納。"),
                    LeadingFact(icon: "building.2.crop.circle", color: .mint, title: "樓層探測", detail: "透過速度與氣壓變化協助記錄樓層。")
                ],
                isWide: isWide,
                compactHeight: compactHeight
            ) {
                LeadingMemoryVisual()
            }

        case .privacy:
            privacyPage(isWide: isWide, compactHeight: compactHeight)
        }
    }

    private func tourLayout<Visual: View>(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        facts: [LeadingFact],
        isWide: Bool,
        compactHeight: Bool,
        @ViewBuilder visual: () -> Visual
    ) -> some View {
        ScrollView {
            Group {
                if isWide {
                    HStack(spacing: 36) {
                        visual()
                            .frame(maxWidth: 560, maxHeight: .infinity)
                            .leadingReveal(pageVisible, delay: 0.14)

                        tourText(title: title, detail: detail, facts: facts)
                            .frame(maxWidth: 470, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: compactHeight ? 16 : 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.largeTitle.bold())
                                .leadingReveal(pageVisible, delay: 0)
                            Text(detail)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .leadingReveal(pageVisible, delay: 0.07)
                        }

                        visual()
                            .frame(maxWidth: .infinity)
                            .frame(height: compactHeight ? 235 : 310)
                            .leadingReveal(pageVisible, delay: 0.14)

                        factsView(facts)
                            .leadingReveal(pageVisible, delay: 0.22)
                    }
                }
            }
            .padding(.horizontal, isWide ? 40 : 24)
            .padding(.vertical, compactHeight ? 12 : 26)
            .padding(.bottom, 78)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func tourText(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        facts: [LeadingFact]
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.largeTitle.bold())
                    .leadingReveal(pageVisible, delay: 0)
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .leadingReveal(pageVisible, delay: 0.07)
            }
            factsView(facts)
                .leadingReveal(pageVisible, delay: 0.22)
        }
    }

    private func factsView(_ facts: [LeadingFact]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: fact.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(fact.color)
                        .frame(width: 32, height: 32)
                        .symbolEffect(.bounce, value: pageVisible)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.title)
                            .font(.headline)
                        Text(fact.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .leadingReveal(pageVisible, delay: 0.22 + Double(index) * 0.07)
            }
        }
    }

    private func privacyPage(isWide: Bool, compactHeight: Bool) -> some View {
        ScrollView {
            Group {
                if isWide {
                    HStack(spacing: 36) {
                        LeadingPrivacyVisual()
                            .frame(maxWidth: 560, maxHeight: .infinity)
                            .leadingReveal(pageVisible, delay: 0.12)
                        privacyCopy
                            .frame(maxWidth: 480)
                    }
                } else {
                    VStack(alignment: .leading, spacing: compactHeight ? 15 : 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("由你決定 Gorilla 可以看見甚麼")
                                .font(.largeTitle.bold())
                                .leadingReveal(pageVisible, delay: 0)
                            Text("權限只在功能需要時使用，之後可以隨時在設定更改。")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .leadingReveal(pageVisible, delay: 0.07)
                        }

                        LeadingPrivacyVisual()
                            .frame(height: compactHeight ? 190 : 245)
                            .leadingReveal(pageVisible, delay: 0.12)

                        permissionControls
                            .leadingReveal(pageVisible, delay: 0.2)
                    }
                }
            }
            .padding(.horizontal, isWide ? 40 : 24)
            .padding(.vertical, compactHeight ? 12 : 24)
            .padding(.bottom, 78)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var privacyCopy: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("由你決定 Gorilla 可以看見甚麼")
                    .font(.largeTitle.bold())
                    .leadingReveal(pageVisible, delay: 0)
                Text("權限只在功能需要時使用，之後可以隨時在設定更改。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .leadingReveal(pageVisible, delay: 0.07)
            }
            permissionControls
                .leadingReveal(pageVisible, delay: 0.2)
        }
    }

    private var permissionControls: some View {
        VStack(spacing: 0) {
            permissionRow(
                icon: "location.fill",
                color: .blue,
                title: "定位服務",
                detail: "用於行程、泊車記憶與附近咪錶位。",
                enabled: locationManager.authorizationStatus != .notDetermined,
                action: requestLocation
            )

            Divider().padding(.leading, 54)

            permissionRow(
                icon: "bell.badge.fill",
                color: .orange,
                title: "通知",
                detail: "在適當時機提示目的地、咪錶與泊車狀態。",
                enabled: notificationStatus != .notDetermined,
                action: requestNotifications
            )
        }
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func permissionRow(
        icon: String,
        color: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(enabled ? "已設定" : "開啟") {
                action()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(enabled)
        }
        .padding(.vertical, 13)
    }

    private var actionBar: some View {
        Button {
            isLastPage ? finish() : goForward()
        } label: {
            HStack(spacing: 9) {
                Text(isLastPage ? "開始使用" : "繼續")
                    .font(.headline)
                Image(systemName: isLastPage ? "checkmark" : "arrow.right")
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(.clear.interactive(), in: .capsule)
        .buttonBorderShape(.capsule)
        .accessibilityHint(isLastPage ? "完成介紹並進入 Gorilla Leading" : "前往下一頁")
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion: Edge = direction > 0 ? .trailing : .leading
        let removal: Edge = direction > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -70 {
                    goForward()
                } else if value.translation.width > 70 {
                    goBack()
                }
            }
    }

    private func goForward() {
        guard !isLastPage,
              let next = LeadingTourPage(rawValue: page.rawValue + 1) else { return }
        direction = 1
        pageVisible = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.52, dampingFraction: 0.86)) {
            page = next
        }
    }

    private func goBack() {
        if page == .welcome {
            if isReplay { finish() }
            return
        }
        guard let previous = LeadingTourPage(rawValue: page.rawValue - 1) else { return }
        direction = -1
        pageVisible = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.52, dampingFraction: 0.86)) {
            page = previous
        }
    }

    private func finish() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.35)) {
            onComplete()
        }
    }

    private func requestLocation() {
        locationManager.startLocationServicesIfNeeded()
    }

    private func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshNotificationStatus()
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }
}

struct AboutGorillaLeadingView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @AppStorage("parkingTimerColorHex") private var parkingTimerColorHex = "46ADB8"
    @State private var showTour = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("GorillaLeadingIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)

                    Text("Gorilla Leading")
                        .font(.title.bold())
                    Text("理解你的路，也記住你停低的地方。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(versionText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .listRowBackground(Color.clear)

            Section("Gorilla Leading") {
                AboutFeatureRow(icon: "map.fill", color: .cyan, title: "旅程與導航", detail: "把地圖、時速、目的地和路線放在同一個駕駛畫面。")
                AboutFeatureRow(icon: "parkingsign.circle.fill", color: .green, title: "咪錶探測", detail: "按距離、狀態與車型顯示附近咪錶位。")
                AboutFeatureRow(icon: "car.side.fill", color: Color(hex: parkingTimerColorHex), title: "泊車記憶", detail: "記錄停車位置、樓層、時間、相片與停車場。")
                AboutFeatureRow(icon: "brain.head.profile.fill", color: Color(hex: "0098FF"), title: "日常預測", detail: "從你確認過的行程模式提供目的地提示。")
            }

            Section("私隱") {
                Label("位置資料由你掌控", systemImage: "hand.raised.fill")
                Text("Gorilla Leading 只會在功能需要時使用系統權限。你可以隨時在 iOS 設定更改定位及通知權限。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showTour = true
                } label: {
                    Label("重新觀看首次介紹", systemImage: "play.rectangle.on.rectangle")
                }
            }

            Section {
                GorillaSupportLinks()
            }
            Section {
                NavigationLink { TrafficDataSourcesView() } label: {
                    Label("資料來源與使用條款", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("關於 Gorilla Leading")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showTour) {
            GorillaOnboardingView(isReplay: true) {
                showTour = false
            }
            .environmentObject(locationManager)
        }
    }
}

enum GorillaSupport {
    static let website = URL(string: "https://gorilla-leading.divine-amber-0182.chatgpt.site")!
    static let review = URL(string: "https://apps.apple.com/app/id6822058970?action=write-review")!
}

struct GorillaSupportLinks: View {
    var body: some View {
        Group {
            Link(destination: GorillaSupport.review) {
                Label("為 Gorilla Leading 評分", systemImage: "star")
            }
            Link(destination: GorillaSupport.website.appendingPathComponent("help/")) {
                Label("幫助", systemImage: "questionmark.circle")
            }
            Link(destination: GorillaSupport.website.appendingPathComponent("privacy/")) {
                Label("私隱政策", systemImage: "hand.raised")
            }
            Link(destination: GorillaSupport.website.appendingPathComponent("terms/")) {
                Label("使用條款", systemImage: "doc.text")
            }
        }
    }
}

private struct AboutFeatureRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct LeadingFact {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
}

private struct LeadingWelcomeVisual: View {
    @State private var activeBadge = 0

    private let badges = [
        ("location.fill", Color.blue),
        ("parkingsign.circle.fill", Color.green),
        ("speedometer", Color.orange)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 260, height: 260)
                .scaleEffect(activeBadge == 1 ? 1.04 : 0.94)

            Image("GorillaLeadingIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 24, y: 12)

            ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
                Image(systemName: badge.0)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(badge.1, in: Circle())
                    .shadow(color: badge.1.opacity(0.28), radius: 12, y: 6)
                    .offset(badgeOffset(index))
                    .scaleEffect(activeBadge == index ? 1.14 : 0.92)
                    .opacity(activeBadge == index ? 1 : 0.72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.35))
                guard !Task.isCancelled else { break }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    activeBadge = (activeBadge + 1) % badges.count
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gorilla Leading 應用程式圖示，配合定位、咪錶和時速功能")
    }

    private func badgeOffset(_ index: Int) -> CGSize {
        switch index {
        case 0: return CGSize(width: -112, height: -78)
        case 1: return CGSize(width: 118, height: -24)
        default: return CGSize(width: -88, height: 108)
        }
    }
}

private struct LeadingJourneyVisual: View {
    @State private var speed = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LeadingMapDemo(mode: .journey, onSpeedChange: { speed = $0 })

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(speed)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(speed)))
                        .animation(.smooth(duration: 0.2), value: speed)
                        .accessibilityIdentifier("tourJourneySpeed")
                    Text("km/h")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("示範行程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("中環").font(.headline)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct LeadingParkingVisual: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LeadingMapDemo(mode: .meters)
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("中環 · 紅棉路")
                Text("狀態示範").foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct LeadingMemoryVisual: View {
    @State private var startedAt = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            LeadingMapDemo(mode: .memory)

            VStack(spacing: 10) {
                Text("昂船洲大橋觀景點")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                // Match the home screen's compact status capsule, not a second invented panel.
                HStack(spacing: 8) {
                    Text("已泊車")
                    Text(startedAt, style: .timer)
                        .monospacedDigit().fixedSize()
                }
                .font(.body.bold())
                .padding(.horizontal, 24).padding(.vertical, 14)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct LeadingPrivacyVisual: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LeadingMapDemo(mode: .privacy)
            VStack(alignment: .leading, spacing: 4) {
                Label("位置由你掌控", systemImage: "location.shield.fill")
                    .font(.subheadline.bold())
                Text("淺水灣 · 示範位置")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("定位範圍由你掌控")
    }
}

private struct LeadingMapDemo: UIViewRepresentable {
    enum Mode {
        case journey
        case meters
        case memory
        case privacy
    }

    let mode: Mode
    var onSpeedChange: ((Int) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(mode: mode, onSpeedChange: onSpeedChange) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        context.coordinator.configure(map, reduceMotion: reduceMotion)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSpeedChange = onSpeedChange
        context.coordinator.displayLink?.isPaused = reduceMotion
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.displayLink?.invalidate()
        map.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        let mode: Mode
        weak var map: MKMapView?
        var displayLink: CADisplayLink?
        var route: [MKMapPoint] = []
        var distances: [Double] = []
        var motion: LeadingJourneyMotion?
        var elapsed = 0.0
        var lastTick = CACurrentMediaTime()
        var lastPublishedSpeed = -1
        var lastSpeedPublish = 0.0
        var onSpeedChange: ((Int) -> Void)?
        let moving = MKPointAnnotation()
        let meterColors: [UIColor] = [.systemGreen, .systemYellow, .systemRed]

        init(mode: Mode, onSpeedChange: ((Int) -> Void)?) {
            self.mode = mode
            self.onSpeedChange = onSpeedChange
        }

        func configure(_ map: MKMapView, reduceMotion: Bool) {
            self.map = map
            switch mode {
            case .journey:
                // Fixed Central road geometry, checked against MapKit directions.
                // The tour must not wait for a network route or jump when a request finishes.
                let points = [
                    (22.2851603, 114.1552321), (22.2850370, 114.1553998),
                    (22.2849446, 114.1554910), (22.2842016, 114.1561106),
                    (22.2840136, 114.1562477), (22.2826429, 114.1573558),
                    (22.2819800, 114.1578674), (22.2817311, 114.1588461),
                    (22.2817488, 114.1588510), (22.2818003, 114.1588867),
                    (22.2818031, 114.1589587)
                ]
                installRoute(points.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }, fit: true)
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                link.isPaused = reduceMotion
                link.add(to: .main, forMode: .common)
                displayLink = link
            case .meters:
                // TD parking-space dataset, 2026-10-24. Positions are real; colours are illustrative.
                let points = [(22.2775822, 114.1594125), (22.2768088, 114.1577492)]
                for (index, point) in points.enumerated() {
                    let pin = MKPointAnnotation()
                    pin.coordinate = CLLocationCoordinate2D(latitude: point.0, longitude: point.1)
                    pin.title = "\(index)"
                    map.addAnnotation(pin)
                }
                map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 22.2772, longitude: 114.1586),
                    latitudinalMeters: 550, longitudinalMeters: 550), animated: false)
            case .memory:
                // Viewpoint on land, not the bridge deck: OSM node 1645491862.
                setPlace(CLLocationCoordinate2D(latitude: 22.3231921, longitude: 114.1223040), meters: 1250)
            case .privacy:
                setPlace(CLLocationCoordinate2D(latitude: 22.2376, longitude: 114.1971), meters: 1100)
            }
        }

        func setPlace(_ coordinate: CLLocationCoordinate2D, meters: Double) {
            moving.coordinate = coordinate
            map?.addAnnotation(moving)
            map?.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters), animated: false)
        }

        func installRoute(_ coordinates: [CLLocationCoordinate2D], fit: Bool) {
            guard let map, coordinates.count > 1 else { return }
            route = coordinates.map(MKMapPoint.init)
            distances = [0]
            for index in 1..<route.count {
                distances.append(distances[index - 1] + route[index - 1].distance(to: route[index]))
            }
            map.removeOverlays(map.overlays)
            let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
            map.addOverlay(line)
            moving.coordinate = coordinates[0]
            if !map.annotations.contains(where: { $0 === moving }) { map.addAnnotation(moving) }
            if fit { map.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 100, left: 46, bottom: 42, right: 46), animated: false) }
            let turns = (1..<(route.count - 1)).map { i -> LeadingJourneyMotion.Turn in
                let a = route[i - 1], b = route[i], c = route[i + 1]
                let incoming = atan2(b.y - a.y, b.x - a.x)
                let outgoing = atan2(c.y - b.y, c.x - b.x)
                let angle = abs(atan2(sin(outgoing - incoming), cos(outgoing - incoming))) * 180 / .pi
                return LeadingJourneyMotion.Turn(distance: distances[i], angle: angle)
            }
            motion = LeadingJourneyMotion(distance: distances.last ?? 0, turns: turns)
            lastTick = CACurrentMediaTime()
        }

        @objc func tick() {
            guard let motion else { return }
            let now = CACurrentMediaTime()
            elapsed += min(0.1, max(0, now - lastTick))
            lastTick = now
            let sample = motion.sample(at: elapsed)
            let target = sample.distance
            let index = max(1, distances.firstIndex(where: { $0 >= target }) ?? (route.count - 1))
            let a = route[index - 1], b = route[index]
            let fraction = (target - distances[index - 1]) / max(0.001, distances[index] - distances[index - 1])
            // The arrow and route share exactly the same projected coordinates.
            moving.coordinate = MKMapPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction).coordinate
            map?.view(for: moving)?.transform = CGAffineTransform(rotationAngle: atan2(b.x - a.x, a.y - b.y) - .pi / 4)
            let speed = Int(sample.speedKmh.rounded())
            let finished = elapsed >= motion.duration
            if speed != lastPublishedSpeed && (now - lastSpeedPublish >= 0.1 || finished) {
                lastPublishedSpeed = speed
                lastSpeedPublish = now
                onSpeedChange?(speed)
            }
            if finished { displayLink?.invalidate() }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if mode == .journey {
                let view = MKAnnotationView(annotation: annotation, reuseIdentifier: nil)
                view.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
                let dot = UIView(frame: view.bounds)
                dot.backgroundColor = .systemBlue
                dot.layer.cornerRadius = 16
                dot.layer.borderColor = UIColor.white.cgColor
                dot.layer.borderWidth = 3
                if mode == .journey {
                    let arrow = UIImageView(image: UIImage(systemName: "location.fill")?.withRenderingMode(.alwaysTemplate))
                    arrow.tintColor = .white
                    arrow.contentMode = .scaleAspectFit
                    arrow.frame = dot.bounds.insetBy(dx: 8, dy: 8)
                    dot.addSubview(arrow)
                }
                view.addSubview(dot)
                return view
            }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            let index = Int((annotation.title ?? nil) ?? "") ?? 0
            view.markerTintColor = mode == .meters ? meterColors[index % meterColors.count] : (mode == .privacy ? .systemTeal : .systemOrange)
            if mode == .privacy {
                view.glyphImage = UIImage(systemName: "beach.umbrella.fill")
            } else {
                view.glyphText = "P"
            }
            view.glyphTintColor = mode == .meters && index == 1 ? .black : .white
            view.titleVisibility = .hidden
            view.displayPriority = .required
            return view
        }
    }
}

private struct LeadingRevealModifier: ViewModifier {
    let visible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: visible || reduceMotion ? 0 : 9)
            .offset(x: visible || reduceMotion ? 0 : 34, y: visible || reduceMotion ? 0 : 8)
            .scaleEffect(visible || reduceMotion ? 1 : 0.98)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.56, dampingFraction: 0.82).delay(delay),
                value: visible
            )
    }
}

private extension View {
    func leadingReveal(_ visible: Bool, delay: Double) -> some View {
        modifier(LeadingRevealModifier(visible: visible, delay: delay))
    }
}
