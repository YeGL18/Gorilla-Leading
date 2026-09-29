import SwiftUI
import MapKit
import CoreLocation
import UserNotifications

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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
                    .padding(.horizontal, isWide ? 40 : 24)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
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
                AboutFeatureRow(icon: "map.fill", color: .blue, title: "旅程與導航", detail: "把地圖、時速、目的地和路線放在同一個駕駛畫面。")
                AboutFeatureRow(icon: "parkingsign.circle.fill", color: .green, title: "咪錶探測", detail: "按距離、狀態與車型顯示附近咪錶位。")
                AboutFeatureRow(icon: "car.side.fill", color: .orange, title: "泊車記憶", detail: "記錄停車位置、樓層、時間、相片與停車場。")
                AboutFeatureRow(icon: "brain.head.profile.fill", color: .purple, title: "日常預測", detail: "從你確認過的行程模式提供目的地提示。")
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
    @State private var speed = 18
    @State private var distance = 2.4

    var body: some View {
        ZStack(alignment: .topLeading) {
            LeadingMapDemo(mode: .journey)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(speed)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(speed)))
                    Text("km/h")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("距離學校")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(distance, format: .number.precision(.fractionLength(1)))
                            .font(.title3.bold())
                            .monospacedDigit()
                            .contentTransition(.numericText(value: distance))
                        Text("km")
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task {
            let speeds = [18, 34, 52, 67, 45, 28]
            var index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.05))
                guard !Task.isCancelled else { break }
                index = (index + 1) % speeds.count
                withAnimation(.smooth(duration: 0.55)) {
                    speed = speeds[index]
                    distance = max(0.3, distance - 0.2)
                }
            }
        }
    }
}

private struct LeadingParkingVisual: View {
    @State private var available = 3

    var body: some View {
        ZStack(alignment: .bottom) {
            LeadingMapDemo(mode: .meters)
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("附近有")
                Text("\(available)")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(available)))
                Text("個空置咪錶位")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { break }
                withAnimation(.smooth(duration: 0.5)) {
                    available = available == 3 ? 2 : 3
                }
            }
        }
    }
}

private struct LeadingMemoryVisual: View {
    @State private var minutes = 0
    @State private var floor = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            LeadingMapDemo(mode: .memory)

            HStack(spacing: 16) {
                Label("已泊車", systemImage: "parkingsign.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(minutes):00")
                        .font(.title2.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(minutes)))
                    Text("B\(floor) · 中環中心")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(floor)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { break }
                withAnimation(.smooth(duration: 0.55)) {
                    minutes = (minutes + 1) % 60
                    if minutes.isMultiple(of: 4) { floor = floor == 1 ? 2 : 1 }
                }
            }
        }
    }
}

private struct LeadingPrivacyVisual: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            LeadingMapDemo(mode: .privacy)
            Circle()
                .stroke(Color.blue.opacity(pulse ? 0.12 : 0.34), lineWidth: 3)
                .frame(width: pulse ? 180 : 96, height: pulse ? 180 : 96)
                .animation(.easeOut(duration: 1.7).repeatForever(autoreverses: false), value: pulse)
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.blue, in: Circle())
                .shadow(color: .blue.opacity(0.24), radius: 14, y: 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("定位範圍由你掌控")
    }
}

private struct LeadingMapDemo: View {
    enum Mode {
        case journey
        case meters
        case memory
        case privacy
    }

    let mode: Mode
    @State private var phase = 0
    @State private var routeProgress: CGFloat = 0.08
    @State private var pulse = false

    private let center = CLLocationCoordinate2D(latitude: 22.2848, longitude: 114.1588)
    private let route = [
        CLLocationCoordinate2D(latitude: 22.2818, longitude: 114.1545),
        CLLocationCoordinate2D(latitude: 22.2837, longitude: 114.1572),
        CLLocationCoordinate2D(latitude: 22.2860, longitude: 114.1601),
        CLLocationCoordinate2D(latitude: 22.2881, longitude: 114.1630)
    ]
    private let meters = [
        CLLocationCoordinate2D(latitude: 22.2828, longitude: 114.1562),
        CLLocationCoordinate2D(latitude: 22.2842, longitude: 114.1591),
        CLLocationCoordinate2D(latitude: 22.2862, longitude: 114.1610),
        CLLocationCoordinate2D(latitude: 22.2873, longitude: 114.1578)
    ]

    var body: some View {
        ZStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            )), interactionModes: []) {
                if mode == .journey {
                    ForEach(Array(route.enumerated()), id: \.offset) { index, coordinate in
                        if index == phase % route.count {
                            Annotation("", coordinate: coordinate) {
                                userMarker
                            }
                        }
                    }
                }

                if mode == .meters {
                    ForEach(Array(meters.enumerated()), id: \.offset) { index, coordinate in
                        Annotation("", coordinate: coordinate) {
                            meterMarker(index: index)
                        }
                    }
                }

                if mode == .memory {
                    Annotation("", coordinate: route[1]) {
                        Image(systemName: "parkingsign.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.orange, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            .symbolEffect(.bounce, value: phase)
                    }
                }

                if mode == .privacy {
                    Annotation("", coordinate: center) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .allowsHitTesting(false)

            if mode == .journey {
                LeadingRouteShape()
                    .trim(from: 0, to: routeProgress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .padding(36)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            pulse = true
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                routeProgress = 1
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(mode == .meters ? 1.4 : 1.8))
                guard !Task.isCancelled else { break }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    phase += 1
                }
            }
        }
    }

    private var userMarker: some View {
        Image(systemName: "location.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(.blue, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 4))
            .shadow(color: .black.opacity(0.2), radius: 7, y: 4)
            .symbolEffect(.pulse, value: phase)
    }

    private func meterMarker(index: Int) -> some View {
        let state = (index + phase) % 4
        let color: Color = state == 0 ? .red : (state == 1 ? .yellow : .green)
        return Text("P")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: color.opacity(0.25), radius: 7, y: 4)
            .scaleEffect(state == 2 ? 1.1 : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state)
    }
}

private struct LeadingRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.12))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY - rect.height * 0.34),
            control2: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.midY + rect.height * 0.14)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.midY - rect.height * 0.18),
            control2: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY + rect.height * 0.28)
        )
        return path
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
