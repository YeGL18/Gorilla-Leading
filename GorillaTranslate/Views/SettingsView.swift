import SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import WidgetKit
import Charts

struct SettingsView: View {
    @State private var simSpeed: Double = 0
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("capsuleAnimationStyle") private var capsuleAnimationStyle: Int = 1
    @AppStorage("capsuleDarkGlassEnabled") private var capsuleDarkGlassEnabled = true
    @AppStorage("highFrequencyTracking") var highFrequencyTracking: Bool = true
    @AppStorage("mapTrackingAnimation") var mapTrackingAnimation: Int = 1
    @AppStorage("speedBlurEnabled") private var speedBlurEnabled: Bool = true
    @AppStorage("speedParallaxEnabled") private var speedParallaxEnabled: Bool = true
    @AppStorage("speedNumberHidden") private var speedNumberHidden: Bool = false
    @AppStorage("orbMasterEnabled") var orbMasterEnabled: Bool = true
    @AppStorage("orbCapsule") var orbCapsule: Bool = false
    @AppStorage("orbExpanded") var orbExpanded: Bool = false
    @AppStorage("orbParkingMemory") var orbParkingMemory: Bool = false
    @AppStorage("orbBackgroundHome") var orbBackgroundHome: Bool = true
    @AppStorage("orbBackgroundSpeed") var orbBackgroundSpeed: Bool = true
    @AppStorage("orbColorPreset") var orbColorPreset: Int = 0  // 0=金黃, 1=動態橙, 2=#9BF783, 3=#99E695, 4=#97D5AB
    @AppStorage("orbOverlapGlowEnabled") var orbOverlapGlowEnabled: Bool = true
    @AppStorage("orbCanvasDitherEnabled") private var orbCanvasDitherEnabled = true
    @AppStorage("darkKnightMode") private var legacyDarkKnightMode = false
    @AppStorage("colorGroupMode") private var colorGroupRaw = -1
    private var colorGroup: GorillaColorGroup {
        .resolve(raw: colorGroupRaw, legacyDarkKnight: legacyDarkKnightMode, legacyTimeBased: useTimeBasedOrb)
    }
    @AppStorage("useTimeBasedOrb") var useTimeBasedOrb: Bool = false
    @AppStorage("vlmRecognitionEnabled") private var vlmRecognitionEnabled: Bool = true
    @AppStorage("floorConvention") private var floorConvention: Int = 2  // 0=香港, 1=內地, 2=自動
    @AppStorage("kalmanSmoothingEnabled") var kalmanSmoothingEnabled: Bool = true
    @AppStorage("launchAnimationEnabled") var launchAnimationEnabled: Bool = true
    @AppStorage("parkingTimerColorHex") var parkingTimerColorHex: String = "12D2C2"
    @AppStorage("bestRouteColorHex") var bestRouteColorHex: String = "BCBA1E"
    @State private var timePreviewHour: Double = Double(Calendar.current.component(.hour, from: Date()))
    @State private var isAutoPlaying = false
    @State private var autoPlayTimer: Timer?
    @StateObject private var previewClock = AnimationClock()
    @StateObject private var previewPhaseManager = TimePhaseManager()
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var destinationManager: DestinationManager
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore

    @State private var showingDestinationPicker = false
    @State private var showingAddDestination = false
    @State private var showingEditDestination = false
    @State private var editingDestination: Destination?
    @State private var destinationsExpanded = false

    // Color bindings
    private var parkingColor: Binding<Color> {
        Binding<Color>(
            get: { Color(hex: parkingTimerColorHex) ?? Color(hex: "12D2C2") ?? .cyan },
            set: { newColor in
                parkingTimerColorHex = newColor.hexString
            }
        )
    }
    private var routeColor: Binding<Color> {
        Binding<Color>(
            get: { Color(hex: bestRouteColorHex) ?? Color(hex: "BCBA1E") ?? .green },
            set: { newColor in
                bestRouteColorHex = newColor.hexString
            }
        )
    }
    private func resetParkingColor() {
        parkingTimerColorHex = "12D2C2"
    }
    private func resetRouteColor() {
        bestRouteColorHex = "BCBA1E"
    }

    var body: some View {
        NavigationStack {
            List {
                // ── 車藍牙：認住「我嘅車」 ──
                Section {
                    DisclosureGroup("我嘅車藍牙") {
                    if let car = locationManager.myCarBluetooth {
                        LabeledContent(String(localized: "我嘅車藍牙")) {
                            Text(car.name).foregroundStyle(.primary)
                        }
                        Button(role: .destructive) {
                            locationManager.clearMyCarBluetooth()
                        } label: {
                            Text(String(localized: "清除選擇"))
                        }
                    }
                    if locationManager.seenBluetoothDevices.isEmpty {
                        Text(String(localized: "未見到任何車載藍牙裝置。手機同架車藍牙連住之後，呢度會自動出現。"))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "最近見到"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(locationManager.seenBluetoothDevices) { device in
                            Button {
                                locationManager.selectMyCarBluetooth(device)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .foregroundStyle(.primary)
                                        Text(String(format: String(localized: "最後見到：%@"), device.lastSeen.formatted(date: .abbreviated, time: .shortened)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if locationManager.myCarBluetooth?.id == device.id {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                    Text(String(localized: "選定之後，只有呢部車嘅藍牙斷線先會計入落車判定，藍牙耳機／家用音響斷線唔會誤判。未選定就用「啱啱揸緊車」推斷落車。"))
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }
                // ── 1. 語言 ──
                Section {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        HStack {
                            Text(String(localized: "語言"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text({
                                switch LanguageManager.languageCode {
                                case "zh-Hant": "繁體中文"
                                case "zh-Hans": "简体中文"
                                case "ja": "日本語"
                                default: "English"
                                }
                            }())
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label(String(localized: "語言"), systemImage: "globe")
                } footer: {
                    Text(String(localized: "在 iOS 設定中更改此 App 的語言"))
                }

                // ── 2. 目的地 ──
                Section {
                    NavigationLink { TrafficCameraSettingsView() } label: {
                        Label("交通相機", systemImage: "camera.fill")
                    }
                }
                Section {
                    DisclosureGroup(isExpanded: $destinationsExpanded) {
                        destinationRows
                    } label: {
                        HStack {
                            Label(String(localized: "目的地"), systemImage: "mappin.circle")
                            Spacer()
                            Text(destinationManager.destinations.count, format: .number)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── 3. 外觀 ──
                Section {
                    DisclosureGroup("外觀") {
                    GorillaColorGroupPicker()
                    Picker(String(localized: "外觀模式"), selection: $appearanceMode) {
                        Text(String(localized: "System")).tag(0)
                        Text(String(localized: "Dark")).tag(1)
                        Text(String(localized: "Light")).tag(2)
                    }
                    Picker(String(localized: "玻璃樣式"), selection: $capsuleDarkGlassEnabled) {
                        Text(String(localized: "透明")).tag(false)
                        Text(String(localized: "深色玻璃")).tag(true)
                    }
                    Picker(String(localized: "膠囊動畫"), selection: $capsuleAnimationStyle) {
                        Text(String(localized: "標準")).tag(0)
                        Text(String(localized: "提升縮放")).tag(1)
                    }
                    LaunchAnimationSettingsSection()
                    if colorGroup.showsOrbControls {
                        NavigationLink { orbEffectsPage } label: {
                            Label(String(localized: "光球效果"), systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("orbEffectsSettings")
                    }
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }

                SoundSettingsSection()

                Section {
                    NavigationLink { VisitRecordingSettingsView() } label: {
                        Label("Visit Recording", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink { BackupToolsView() } label: {
                        Label("Backup & Restore", systemImage: "externaldrive")
                    }
                    NavigationLink { PerformanceSessionView() } label: {
                        Label("Performance Check", systemImage: "waveform.path.ecg")
                    }
                } header: { Text("Data & Diagnostics") }

                // ── 4. 自定義顏色 ──
                Section {
                    DisclosureGroup("自定義顏色") {
                    HStack {
                        Text("泊車記憶顏色")
                            .foregroundStyle(.primary)
                        Spacer()
                        ColorPicker("", selection: parkingColor, supportsOpacity: false)
                            .labelsHidden()
                        Button("預設") {
                            resetParkingColor()
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Text("最優路線顏色")
                            .foregroundStyle(.primary)
                        Spacer()
                        ColorPicker("", selection: routeColor, supportsOpacity: false)
                            .labelsHidden()
                        Button("預設") {
                            resetRouteColor()
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                    }
                    }
                }

                // ── 5. 地圖 ──
                Section {
                    DisclosureGroup("地圖") {
                    Toggle(isOn: $highFrequencyTracking) {
                        Label(String(localized: "高頻率地圖追蹤"), systemImage: "location.fill")
                    }
                    Text(String(localized: "開啟後地圖視角更新更流暢，但會增加耗電。關閉後更新頻率降低，延長電池壽命。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(String(localized: "追蹤動畫"), selection: $mapTrackingAnimation) {
                        Text(String(localized: "標準")).tag(0)
                        Text(String(localized: "柔軟")).tag(1)
                    }
                    Toggle(isOn: $kalmanSmoothingEnabled) {
                        Label(String(localized: "卡爾曼濾波"), systemImage: "waveform.path.ecg")
                    }
                    Text(String(localized: "開啟後時速顯示會更平滑，數字輪播動畫更連續。關閉則使用原始 GPS 數據。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }

                // ── 6. 泊車功能 ──
                Section {
                    DisclosureGroup("泊車功能") {
                    Picker(String(localized: "地點樓層判定"), selection: Binding(
                        get: { parkingFloorStore.floorMode }, set: { parkingFloorStore.setFloorMode($0) }
                    )) {
                        ForEach(ParkingFloorMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Text(String(localized: "切換不會合併或刪除舊記錄。不同樓層模式會保留每次泊車樓層，並按樓層分組。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(isOn: $vlmRecognitionEnabled) {
                        Label(String(localized: "VLM 車位識別"), systemImage: "brain.head.profile")
                    }
                    Text(String(localized: "拍照後自動使用 VLM 識別車位號、樓層、區域代碼。關閉後拍照唔會觸發識別。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "行車後降至 30 km/h 以下開始樓層探測；停穩 10 秒後詢問是否已泊好，未確認就繼續採樣，每隔 10 秒再問。只在前景採樣，離開時保留穩定停車估算。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Picker(String(localized: "樓層慣例"), selection: $floorConvention) {
                            Text(String(localized: "香港 (G, 1, 2…)")).tag(0)
                            Text(String(localized: "內地 (1, 2, 3…)")).tag(1)
                            Text(String(localized: "自動偵測")).tag(2)
                        }
                        if floorConvention == 2 {
                            FloorConventionBadge(compact: true)
                        }
                    }
                    Text(floorConvention == 0
                        ? String(localized: "地面為 G 樓，上方為 1 樓、2 樓。")
                        : floorConvention == 1
                        ? String(localized: "地面為 1 樓，上方為 2 樓、3 樓。")
                        : String(localized: "根據 GPS 位置自動判斷。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }

                MeterSettingsSection()

                // ── 6.5 時速顯示效果 ──
                Section {
                    DisclosureGroup("時速顯示效果") {
                    SpeedUnitPicker()
                    Toggle(isOn: $speedBlurEnabled) {
                        Label(String(localized: "時速模糊光暈"), systemImage: "aqi.medium")
                    }
                    Toggle(isOn: $speedParallaxEnabled) {
                        Label(String(localized: "時速陀螺儀動畫"), systemImage: "gyroscope")
                    }
                    Toggle(isOn: $speedNumberHidden) {
                        Label(String(localized: "隱藏時速數字"), systemImage: "eye.slash")
                    }
                    Text("模糊光暈：時速數字底下嘅模糊發光層。\n陀螺儀動畫：傾斜手機或加速時數字會跟隨擺動。\n隱藏時速數字：連單位一齊隱藏，其他顯示照舊。")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }


                Section {
                    NavigationLink {
                        GorillaPageView()
                    } label: {
                        Label {
                            Text("Gorilla")
                        } icon: {
                            Image(uiImage: GorillaBrand.tabIcon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                    }
                    NavigationLink {
                        AboutGorillaLeadingView()
                    } label: {
                        Label("關於 Gorilla Leading", systemImage: "info.circle")
                    }
                } header: {
                    Text("關於 Gorilla")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.defaultMinListHeaderHeight, 36)
            .listRowSpacing(0)
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ParkingFloorTestView()
                    } label: {
                        Text(String(localized: "測試"))
                    }
                }
            }
            .sheet(isPresented: $showingAddDestination) {
                AddDestinationView()
            }
            .sheet(isPresented: $showingEditDestination) {
                if let destination = editingDestination {
                    DestinationNameEditorView(coordinate: destination.coordinate, existingDestination: destination)
                }
            }
            .onChange(of: timePreviewHour) { _, newValue in
                NotificationCenter.default.post(
                    name: .timePhasePreviewChanged,
                    object: nil,
                    userInfo: ["hour": newValue]
                )
            }
            .onChange(of: parkingTimerColorHex) { _, newValue in
                let appGroup = UserDefaults(suiteName: "group.com.gorilla.translate")
                appGroup?.set(newValue, forKey: "parkingTimerColorHex")
                appGroup?.synchronize()
                WidgetCenter.shared.reloadTimelines(ofKind: "GorillaLiveActivity")
            }
            .onChange(of: bestRouteColorHex) { _, newValue in
                let appGroup = UserDefaults(suiteName: "group.com.gorilla.translate")
                appGroup?.set(newValue, forKey: "bestRouteColorHex")
                appGroup?.synchronize()
            }
        }
    }

    private var orbEffectsPage: some View {
        List {
            Section {
                Toggle(isOn: $orbMasterEnabled) {
                    Label(String(localized: "光球效果總開關"), systemImage: "sparkles")
                }
                .accessibilityIdentifier("orbMasterEnabled")
                if orbMasterEnabled {
                    if colorGroup == .normal {
                        Picker(String(localized: "光球配色"), selection: $colorSchemeIndex) {
                            Text(String(localized: "Default")).tag(0)
                            Text("27").tag(1)
                        }
                    }
                    if colorGroup != .timeBased {
                        Picker(String(localized: "光球繪製方式"), selection: $orbCanvasDitherEnabled) {
                            Text(String(localized: "原生模糊")).tag(false)
                            Text("Canvas Symbols + Dither").tag(true)
                        }
                        .accessibilityIdentifier("orbCanvasDitherEnabled")
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "光球混色"))
                                .font(.subheadline)
                            Picker(String(localized: "光球混色"), selection: $orbOverlapGlowEnabled) {
                                Text(String(localized: "原本效果")).tag(false)
                                Text(String(localized: "白色混色")).tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                    }
                    Toggle(String(localized: "緊湊膠囊"), isOn: $orbCapsule)
                    Toggle(String(localized: "擴展膠囊"), isOn: $orbExpanded)
                    Toggle(String(localized: "泊車記憶"), isOn: $orbParkingMemory)
                    Toggle(String(localized: "主頁背景"), isOn: $orbBackgroundHome)
                    Toggle(String(localized: "時速頁背景"), isOn: $orbBackgroundSpeed)
                    // 圓點顏色：一行色點直接點選（控制圓點動畫嘅圓點顏色，選中加高亮圈）
                    if colorGroup == .normal {
                        HStack(spacing: 12) {
                            Text(String(localized: "圓點顏色"))
                            Spacer()
                            ForEach(
                                Array(["FFD700", "FF8C00", "9BF783", "99E695", "97D5AB"].enumerated()), id: \.offset
                            ) { index, hex in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        orbColorPreset = index
                                    }
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    orbColorPreset == index
                                                        ? Color.primary.opacity(0.9)
                                                        : Color.primary.opacity(0.15),
                                                    lineWidth: orbColorPreset == index ? 2.5 : 1
                                                )
                                        )
                                        .scaleEffect(orbColorPreset == index ? 1.15 : 1.0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if colorGroup == .timeBased {
                        VStack(spacing: 12) {
                            HStack {
                                Text(String(localized: "預覽時間"))
                                Spacer()
                                if isAutoPlaying {
                                    Text("\(Int(timePreviewHour)):00")
                                        .foregroundStyle(.orange)
                                        .monospacedDigit()
                                } else {
                                    Text("\(Int(timePreviewHour)):00")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 12) {
                                Slider(value: $timePreviewHour, in: 0...24, step: 0.5)
                                    .tint(.orange)
                                    .disabled(isAutoPlaying)
                                    .onChange(of: timePreviewHour) { _, newValue in
                                        if !isAutoPlaying {
                                            previewPhaseManager.setPreviewHour(newValue)
                                        }
                                    }
                                Button {
                                    toggleAutoPlay()
                                } label: {
                                    Image(systemName: isAutoPlaying ? "stop.fill" : "play.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .glassEffect(.regular, in: .circle)
                                }
                            }
                            HStack {
                                Text("0:00").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("6:00").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("12:00").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("18:00").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("24:00").font(.caption).foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                let phoneHeight = geo.size.width * (19.5 / 9.0)
                                TimeBasedOrbView(
                                    phaseManager: previewPhaseManager, clock: previewClock, orbEnabled: true
                                )
                                .frame(width: geo.size.width, height: phoneHeight)
                            }
                            .frame(height: UIScreen.main.bounds.width * (19.5 / 9.0))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onAppear {
                                previewClock.start()
                                previewPhaseManager.start()
                                previewPhaseManager.setPreviewHour(timePreviewHour)
                            }
                            .onDisappear {
                                stopAutoPlay()
                                previewClock.stop()
                                previewPhaseManager.stop()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "光球效果"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopAutoPlay()
            previewClock.stop()
            previewPhaseManager.stop()
        }
    }
    @ViewBuilder
    private var destinationRows: some View {
        if destinationManager.destinations.isEmpty {
            Text(String(localized: "No saved destinations yet"))
                .foregroundStyle(.secondary)
        }
        ForEach(destinationManager.destinations) { destination in
            HStack {
                Circle().fill(destination.color).frame(width: 12, height: 12)
                Text(destination.name)
                Spacer()
                if destinationManager.selectedDestination?.id == destination.id {
                    Image(systemName: "checkmark").foregroundStyle(.blue)
                }
                if let distance = destination.formattedDistance, let time = destination.formattedTime {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(distance).font(.caption)
                        Text(time).font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { destinationManager.selectDestination(destination) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    destinationManager.deleteDestination(destination)
                } label: { Image(systemName: "trash") }
                Button {
                    editingDestination = destination
                    showingEditDestination = true
                } label: { Image(systemName: "pencil") }
                .tint(.blue)
            }
        }
        Button {
            showingAddDestination = true
        } label: {
            Label(String(localized: "新增目的地"), systemImage: "plus")
        }
    }

    private func toggleAutoPlay() {
        if isAutoPlaying {
            stopAutoPlay()
        } else {
            startAutoPlay()
        }
    }
    
    private func startAutoPlay() {
        isAutoPlaying = true
        timePreviewHour = 0
        
        // 800倍速：每秒前进 800/3600 小时 = 0.222 小时/秒
        // 24小时需要 24 / 0.222 = 108 秒 ≈ 1.8 分钟
        let interval: TimeInterval = 1.0 / 60.0  // 60fps
        let speedMultiplier = 800.0
        let hourIncrement = speedMultiplier * interval / 3600.0
        
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                self.timePreviewHour += hourIncrement
                if self.timePreviewHour >= 24.0 {
                    self.timePreviewHour = 0
                }
                
                self.previewPhaseManager.setPreviewHour(self.timePreviewHour)
            }
        }
    }
    
    private func stopAutoPlay() {
        isAutoPlaying = false
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
    }

    private func visitConnector(from earlier: LocationManager.VisitRecord, to later: LocationManager.VisitRecord) -> some View {
        let gap: TimeInterval
        if let dep = earlier.departureDate {
            gap = later.arrivalDate.timeIntervalSince(dep)
        } else {
            gap = later.arrivalDate.timeIntervalSince(earlier.arrivalDate)
        }
        let gapMins = max(0, Int(gap / 60))

        return HStack(spacing: 6) {
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 2)
            Image(systemName: "car.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(gapMins)min")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 6)
        .padding(.leading, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transportIcon(_ type: String) -> String {
        switch type {
        case "Walking": return "figure.walk"
        case "Driving": return "car.fill"
        case "Transit": return "tram.fill"
        case "Passing": return "arrow.triangle.swap"
        default: return "mappin.circle.fill"
        }
    }
}

private struct SoundSettingsSection: View {
    @AppStorage(SFXPreferences.launchKey) private var launchVersion = 0
    @AppStorage(SFXPreferences.movementKey) private var movementVersion = 1
    @AppStorage("sfxAccelerationEnabled") private var accelerationEnabled = false
    @AppStorage("interactionHapticsEnabled") private var hapticsEnabled = true
    @StateObject private var preview = SFXPlayer()

    var body: some View {
        Section {
            DisclosureGroup("音效與觸感") {
            Picker(String(localized: "App 啟動音效"), selection: $launchVersion) {
                Text("Default Launch Sound").tag(0)
                Text("Gentle Sound").tag(1)
            }
            Button {
                preview.stopPreviews()
                preview.previewLaunchSound()
            } label: {
                Label(String(localized: "試聽啟動音效"), systemImage: "play.circle")
            }
            Picker(String(localized: "逗留／開車音效"), selection: $movementVersion) {
                Text("Gentle Sound").tag(0)
                Text("Minimal Sound").tag(1)
            }
            HStack {
                Button {
                    preview.stopPreviews()
                    preview.playEnterStationary()
                } label: {
                    Label(String(localized: "試聽逗留"), systemImage: "play.circle")
                }
                Spacer()
                Button {
                    preview.stopPreviews()
                    preview.playEnterDriving()
                } label: {
                    Label(String(localized: "試聽開車"), systemImage: "play.circle")
                }
            }
            .buttonStyle(.borderless)
            Toggle("Tap Haptics", systemImage: "hand.tap", isOn: $hapticsEnabled)
                .accessibilityIdentifier("interactionHapticsToggle")
            Toggle(isOn: $accelerationEnabled) {
                Label(String(localized: "加速音效"), systemImage: "speaker.wave.2")
            }
            Text(String(localized: "逗留與開車音效會成組切換。泊車時間提醒使用獨立通知音效。"))
                .font(.caption).foregroundStyle(.secondary)
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .onChange(of: launchVersion) { _, _ in preview.stopPreviews() }
        .onChange(of: movementVersion) { _, _ in preview.stopPreviews() }
        .onDisappear { preview.stopPreviews() }
    }
}

// MARK: - 測試頁分類排序

private struct TestItemDef: Identifiable {
    let id: String
    let title: String
    let icon: String
    @ViewBuilder let destination: () -> AnyView
}

private let allTestItems: [TestItemDef] = [
    TestItemDef(id: "meterMap", title: "全港咪錶測試", icon: "parkingsign.circle") { AnyView(ParkingMeterTestView()) },
    TestItemDef(id: "parkingFlow", title: "停車流程測試", icon: "parkingsign.circle.fill") { AnyView(ParkingFlowTestView()) },
    TestItemDef(id: "timeOrb", title: "時程光球動畫測試", icon: "sparkles") { AnyView(TimeOrbAnimationTestView()) },
    TestItemDef(id: "visitRecords", title: "到訪記錄測試", icon: "mappin.and.ellipse") { AnyView(VisitRecordsTestView()) },
    TestItemDef(id: "speedAnim", title: "模擬動畫時速動畫測試", icon: "speedometer") { AnyView(SpeedAnimationTestView()) },
    TestItemDef(id: "altimeter", title: "氣壓計曲線測試", icon: "barometer") { AnyView(AltimeterTestView()) },
    TestItemDef(id: "floorCurve", title: "樓層曲線懸浮窗測試", icon: "chart.line.uptrend.xyaxis") { AnyView(FloorCurveTestView()) },
    TestItemDef(id: "addressBeam", title: "地址膠囊 BorderBeam 測試", icon: "dot.squareshape.split.2x2") { AnyView(AddressCapsuleBeamTestView()) },
    TestItemDef(id: "placeMgmt", title: "地點管理", icon: "brain.head.profile") { AnyView(PlaceManagementView()) },
    TestItemDef(id: "photoTest", title: "泊車記憶拍照效果測試", icon: "camera.on.rectangle") { AnyView(ParkingMemoryPhotoTestView()) },
    TestItemDef(id: "swipeTest", title: "抽離牌組動畫測試", icon: "rectangle.split.3x1") { AnyView(ParkingMemorySwipeTestView()) },
    TestItemDef(id: "ocrTest", title: "泊車辨識測試 (OCR)", icon: "text.viewfinder") { AnyView(ParkingRecognitionTestView()) },
    TestItemDef(id: "llmTest", title: "泊車辨識測試 (LLM)", icon: "brain.head.profile") { AnyView(ParkingLLMRecognitionTestView()) },
    TestItemDef(id: "liveActivity", title: "即時活動樣式預覽", icon: "iphone.and.dynamicIsland") { AnyView(LiveActivityPreviewTestView()) },
    TestItemDef(id: "kalmanTest", title: "卡爾曼濾波對比測試", icon: "waveform.path.ecg") { AnyView(KalmanFilterTestView()) },
    TestItemDef(id: "prediction", title: "預測目的地測試", icon: "brain.head.profile") { AnyView(PredictionTestView()) },
]

struct ParkingFloorTestView: View {
    @State private var orderedIDs: [String] = []
    @State private var favoriteIDs: Set<String> = []
    @Environment(\.editMode) private var editMode

    private var orderedItems: [TestItemDef] {
        let dict = Dictionary(uniqueKeysWithValues: allTestItems.map { ($0.id, $0) })
        return orderedIDs.compactMap { dict[$0] }
    }

    private var favorites: [TestItemDef] { orderedItems.filter { favoriteIDs.contains($0.id) } }
    private var others: [TestItemDef] { orderedItems.filter { !favoriteIDs.contains($0.id) } }

    private func loadFromStorage() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "testItemOrder"),
           let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
            // 補充新增嘅測試項（喺存儲排序中冇嘅）
            let storedSet = Set(arr)
            let newIDs = allTestItems.map(\.id).filter { !storedSet.contains($0) }
            orderedIDs = arr + newIDs
        } else {
            orderedIDs = allTestItems.map(\.id)
        }
        if let data = defaults.data(forKey: "testItemFavorites"),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            favoriteIDs = Set(arr)
        }
    }

    private func saveToStorage() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(orderedIDs), forKey: "testItemOrder")
        defaults.set(try? JSONEncoder().encode(Array(favoriteIDs)), forKey: "testItemFavorites")
    }

    private func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) { favoriteIDs.remove(id) } else { favoriteIDs.insert(id) }
        // 切換常用後重新排列：常用排前面，保持各自內部順序
        let favIDs = orderedIDs.filter { favoriteIDs.contains($0) }
        let otherIDs = orderedIDs.filter { !favoriteIDs.contains($0) }
        orderedIDs = favIDs + otherIDs
        saveToStorage()
    }

    /// 常用 section 的 move
    private func moveFavorite(from source: IndexSet, to destination: Int) {
        let favIDs = orderedIDs.filter { favoriteIDs.contains($0) }
        let otherIDs = orderedIDs.filter { !favoriteIDs.contains($0) }
        var newFavIDs = favIDs
        newFavIDs.move(fromOffsets: source, toOffset: destination)
        orderedIDs = newFavIDs + otherIDs
        saveToStorage()
    }

    /// 其他 section 的 move
    private func moveOther(from source: IndexSet, to destination: Int) {
        let favIDs = orderedIDs.filter { favoriteIDs.contains($0) }
        let otherIDs = orderedIDs.filter { !favoriteIDs.contains($0) }
        var newOtherIDs = otherIDs
        newOtherIDs.move(fromOffsets: source, toOffset: destination)
        orderedIDs = favIDs + newOtherIDs
        saveToStorage()
    }

    var body: some View {
        List {
            // ⭐ 常用 header
            if !favorites.isEmpty {
                Label("⭐ 常用", systemImage: "star.fill")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

            // 常用項目
            ForEach(favorites) { item in
                rowView(item: item, isFavorite: true)
            }
            .onMove(perform: moveFavorite)

            // 其他 header
            if !others.isEmpty {
                Text("其他")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

            // 其他項目
            ForEach(others) { item in
                rowView(item: item, isFavorite: false)
            }
            .onMove(perform: moveOther)
        }
        .navigationTitle(String(localized: "測試"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .onAppear {
            loadFromStorage()
        }
    }

    @ViewBuilder
    private func rowView(item: TestItemDef, isFavorite: Bool) -> some View {
        HStack {
            if editMode?.wrappedValue == .active {
                Button {
                    toggleFavorite(item.id)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                item.destination()
            } label: {
                Label(String(localized: String.LocalizationValue(item.title)), systemImage: item.icon)
            }
        }
    }
}

struct ParkingFlowTestView: View {
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    @State private var renamingLotID: UUID?
    @State private var renamingFloor: Int?
    @State private var renamingText = ""
    @State private var showRenameAlert = false
    @State private var showClearAlert = false

    var body: some View {
        List {
            Section {
                ParkingCaptureStatusView(barometer: parkingFloorStore.barometer)
                Picker(String(localized: "地點樓層判定"), selection: Binding(
                    get: { parkingFloorStore.floorMode }, set: { parkingFloorStore.setFloorMode($0) }
                )) {
                    ForEach(ParkingFloorMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
            }
            if parkingFloorStore.lots.isEmpty {
                ContentUnavailableView(String(localized: "未有任何停車點記錄"),
                                       systemImage: "parkingsign.circle")
            }
            ForEach(parkingFloorStore.lots) { lot in
                Section {
                    NavigationLink { ParkingLotDetailView(lot: lot) } label: {
                        LabeledContent(lot.preferredDisplayName ?? String(localized: "停車場"),
                                       value: "\(lot.points.count)")
                    }
                    if parkingFloorStore.floorMode == .perVisit {
                        ForEach(floors(in: lot), id: \.self) { floor in
                            DisclosureGroup {
                                ForEach(points(in: lot, floor: floor)) { point in pointLink(point) }
                                Button {
                                    renamingLotID = lot.id
                                    renamingFloor = floor
                                    renamingText = lot.floorNames?[String(floor)] ?? ""
                                    showRenameAlert = true
                                } label: { Label(String(localized: "命名此樓層"), systemImage: "pencil") }
                            } label: {
                                Label(lot.floorNames?[String(floor)]
                                      ?? ParkingFloorStore.formatFloor(floor, coordinate: lot.centerCoordinate),
                                      systemImage: floor < 0 ? "arrow.down.square" : "building.2")
                                    .accessibilityIdentifier("parkingFloorGroup-\(floor)")
                            }
                        }
                        ForEach(lot.points.filter { $0.manualFloorIndex == nil && $0.predictedFloorIndex == nil }) {
                            pointLink($0)
                        }
                    } else {
                        ForEach(lot.points.sorted { $0.createdAt > $1.createdAt }.prefix(3)) { pointLink($0) }
                        if lot.points.count > 3 {
                            NavigationLink(String(localized: "所有停車點")) {
                                List(lot.points.sorted { $0.createdAt > $1.createdAt }) { pointLink($0) }
                                    .navigationTitle(lot.preferredDisplayName ?? String(localized: "停車場"))
                            }
                        }
                    }
                }
            }
            Section {
                Button(role: .destructive) { showClearAlert = true } label: {
                    Label(String(localized: "清除全部停車點數據"), systemImage: "trash")
                }
            }
        }
        .navigationTitle(String(localized: "停車流程測試"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "命名此樓層"), isPresented: $showRenameAlert) {
            TextField(String(localized: "名稱"), text: $renamingText)
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "確定")) {
                guard let id = renamingLotID, let floor = renamingFloor else { return }
                parkingFloorStore.setFloorName(lotID: id, floor: floor, name: renamingText)
            }
        }
        .alert(String(localized: "清除全部停車點數據"), isPresented: $showClearAlert) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "清除"), role: .destructive) { parkingFloorStore.clearAll() }
        }
    }

    private func floors(in lot: ParkingLotRecord) -> [Int] {
        Set(lot.points.filter(\.isAutomotive).compactMap(\.effectiveFloorIndex)).sorted(by: >)
    }

    private func points(in lot: ParkingLotRecord, floor: Int) -> [ParkingPointRecord] {
        lot.points.filter { $0.isAutomotive && $0.effectiveFloorIndex == floor }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func pointLink(_ point: ParkingPointRecord) -> some View {
        NavigationLink {
            ParkingPointDiagnosticsView(pointID: point.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: point.isAutomotive ? "car.fill" : "figure.walk")
                    .foregroundStyle(point.isAutomotive ? Color.green : Color.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.createdAt, format: .dateTime.month().day().hour().minute())
                    if point.isAutomotive {
                        Text(point.floorStatusLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if point.isAutomotive {
                    Text(point.displayFloor ?? String(localized: "未知"))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ParkingReferenceFloorView: View {
    @ObservedObject var barometer: BarometerSessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $barometer.referenceFloorIndex, in: -10...30) {
                        LabeledContent(String(localized: "起點樓層"),
                            value: ParkingFloorStore.formatFloor(barometer.referenceFloorIndex))
                    }
                    .disabled(!barometer.isUpdating)
                } footer: {
                    Text(String(localized: "氣壓計只能量度高度變化。起點預設為地面；若已在停車場內開始探測，請選擇實際起點樓層。"))
                }
            }
            .navigationTitle(String(localized: "起點樓層"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .onChange(of: barometer.isUpdating) { _, updating in
                if !updating { dismiss() }
            }
        }
    }
}

private struct ParkingCaptureStatusView: View {
    @ObservedObject var barometer: BarometerSessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(barometer.isUpdating ? String(localized: "持續採樣中")
                  : barometer.completedResult != nil ? String(localized: "已完成停泊") : String(localized: "等待行車"),
                  systemImage: barometer.isUpdating ? "waveform.path" : "parkingsign.circle")
                .foregroundStyle(barometer.isUpdating ? Color.teal : Color.secondary)
            if barometer.samples.count > 1 {
                Chart(Array(barometer.samples.suffix(240)), id: \.timestamp) { sample in
                    LineMark(x: .value("Time", sample.timestamp),
                             y: .value("Height", sample.relativeAltitude - (barometer.captureReferenceAltitude ?? 0)))
                        .foregroundStyle(Color.teal)
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 120)
            }
            HStack {
                Text(String(localized: "已緩存樣本"))
                Spacer()
                Text("\(barometer.samples.count)").monospacedDigit().contentTransition(.numericText())
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ParkingPointDiagnosticsView: View {
    let pointID: UUID
    @EnvironmentObject private var store: ParkingFloorStore
    private var point: ParkingPointRecord? { store.allPoints.first { $0.id == pointID } }

    var body: some View {
        if let point {
            List {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: point.coordinate,
                        latitudinalMeters: 240, longitudinalMeters: 240)), interactionModes: []) {
                        Marker(point.isAutomotive ? (point.displayFloor ?? String(localized: "停車點")) : String(localized: "逗留點"), coordinate: point.coordinate)
                    }
                    .frame(height: 200).listRowInsets(EdgeInsets())
                    LabeledContent(String(localized: "建立"), value: point.createdAt.formatted())
                    if point.isAutomotive {
                        Stepper(value: Binding(
                            get: { self.point?.manualFloorIndex ?? self.point?.predictedFloorIndex ?? 0 },
                            set: { store.setManualFloor(pointID: pointID, floorIndex: $0) }
                        ), in: -10...30) {
                            LabeledContent(String(localized: "樓層"), value: point.displayFloor ?? String(localized: "未知"))
                        }
                    }
                }
                if point.isAutomotive {
                    Section(String(localized: "氣壓探測")) {
                        Stepper(value: Binding(
                            get: { self.point?.barometerReferenceFloorIndex ?? 0 },
                            set: { store.setReferenceFloor(pointID: pointID, floor: $0) }
                        ), in: -10...30) {
                            LabeledContent(String(localized: "起點樓層"),
                                           value: ParkingFloorStore.formatFloor(point.barometerReferenceFloorIndex ?? 0))
                        }
                        LabeledContent(String(localized: "高度變化"),
                                       value: point.barometerAltitudeDeltaMeters.map { String(format: "%+.1f m", $0) } ?? "—")
                        LabeledContent(String(localized: "已緩存樣本"), value: "\(point.barometerSampleCount ?? 0)")
                        LabeledContent(String(localized: "校準資料"), value: String(localized:
                            point.barometerCalibrationEligible == true ? "完整採樣" :
                                (point.barometerCalibrationEligible == false ? "採樣不完整" : "完整性未確認")))
                        LabeledContent(String(localized: "信心度"),
                                       value: point.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    }
                }
                Section(String(localized: "位置")) {
                    LabeledContent(String(localized: "中心"), value: String(format: "%.6f, %.6f", point.latitude, point.longitude))
                }
            }
            .navigationTitle(store.lot(containing: pointID)?.displayName(for: point, mode: store.floorMode)
                             ?? String(localized: "停車點"))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(String(localized: "未知"), systemImage: "parkingsign.circle")
        }
    }
}

struct ParkingLotDetailView: View {
    let lot: ParkingLotRecord
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    @State private var renamingText = ""
    @State private var showRenameAlert = false
    @State private var showRecordList = false
    @State private var showBoundaryEditor = false
    @State private var showMerge = false
    @Environment(\.dismiss) private var dismiss
    private var liveLot: ParkingLotRecord { parkingFloorStore.lots.first { $0.id == lot.id } ?? lot }

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "名稱"),
                               value: liveLot.preferredDisplayName ?? String(localized: "未命名"))
                Button {
                    renamingText = liveLot.name ?? ""
                    showRenameAlert = true
                } label: { Label(String(localized: "地點改名"), systemImage: "pencil") }
                if parkingFloorStore.floorMode == .perVisit {
                    Picker(String(localized: "歸納樓層"), selection: Binding(
                        get: { liveLot.floorScopeIndex },
                        set: { parkingFloorStore.setLotFloorScope(lotID: lot.id, floor: $0) }
                    )) {
                        Text(String(localized: "所有樓層")).tag(Int?.none)
                        ForEach(-10...30, id: \.self) { floor in
                            Text(ParkingFloorStore.formatFloor(floor, coordinate: liveLot.centerCoordinate)).tag(Int?.some(floor))
                        }
                    }
                }
            } footer: {
                Text(String(localized: "同位置的上落客區與地下停車場可分別設定歸納樓層；跨樓層停車場選擇所有樓層。"))
            }
            Section(String(localized: "樓層校準")) {
                if let height = liveLot.learnedMetersPerFloor {
                    LabeledContent(String(localized: "每層高度"), value: String(format: "%.2f m", height))
                }
                LabeledContent(String(localized: "信心度"),
                    value: liveLot.learnedConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                let history = parkingFloorStore.calibrationHistory(for: liveLot)
                let profiles = ParkingFloorCalibration.profiles(history)
                ForEach(profiles) { profile in
                    LabeledContent(ParkingFloorStore.formatFloor(profile.floor, coordinate: liveLot.centerCoordinate),
                                   value: String(format: "%+.2f m · %.0f%%", profile.height, profile.confidence * 100))
                }
                let excludedCount = (liveLot.floorLearningHistory ?? []).count - history.count
                if excludedCount > 0 {
                    LabeledContent(String(localized: "未納入校準"), value: "\(excludedCount)")
                }
                if !history.isEmpty {
                    Chart(Array(history.enumerated()), id: \.offset) { entry in
                        PointMark(x: .value("Floors", entry.element.travelledFloors),
                                  y: .value("Height", entry.element.altitudeDeltaMeters))
                            .foregroundStyle(Color.teal)
                    }
                    .frame(height: 140)
                    .chartXAxisLabel(String(localized: "樓層變化"))
                    .chartYAxisLabel("m")
                    DisclosureGroup(String(localized: "學習記錄")) {
                        ForEach(Array(history.sorted { $0.createdAt > $1.createdAt }.enumerated()), id: \.offset) { entry in
                            HStack {
                                Text(entry.element.createdAt, format: .dateTime.month().day().hour().minute())
                                Spacer()
                                Text(ParkingFloorStore.formatFloor(entry.element.manualFloorIndex,
                                                                   coordinate: liveLot.centerCoordinate))
                                Text(String(format: "%+.1f m", entry.element.altitudeDeltaMeters))
                                    .foregroundStyle(.secondary)
                            }.font(.caption).monospacedDigit()
                        }
                    }
                }
            }
            Section(String(localized: "所有停車點")) {
                Button { showRecordList = true } label: {
                    Label(String(localized: "修正歷史樓層"), systemImage: "list.bullet")
                }
                ForEach(liveLot.points.sorted { $0.createdAt > $1.createdAt }) { point in
                    NavigationLink { ParkingPointDiagnosticsView(pointID: point.id) } label: {
                        HStack {
                            Text(point.createdAt, format: .dateTime.month().day().hour().minute())
                            Spacer()
                            if point.isAutomotive {
                                Text(point.displayFloor ?? String(localized: "未知"))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            }
            Section {
                Button { showBoundaryEditor = true } label: {
                    Label(String(localized: "調整停車場範圍"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                Button { showMerge = true } label: {
                    Label(String(localized: "合併停車場"), systemImage: "arrow.triangle.merge")
                }
                DisclosureGroup(String(localized: "位置")) {
                    LabeledContent(String(localized: "中心"),
                        value: String(format: "%.6f, %.6f", liveLot.centerLatitude, liveLot.centerLongitude))
                    LabeledContent(String(localized: "半徑"), value: "\(Int(liveLot.radiusMeters)) m")
                }
            }
        }
        .navigationTitle(liveLot.preferredDisplayName ?? String(localized: "停車場"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRecordList) {
            ParkingRecordListView(store: parkingFloorStore, lotID: lot.id, groupID: nil)
        }
        .sheet(isPresented: $showBoundaryEditor) {
            ParkingBoundaryEditor(store: parkingFloorStore, lot: liveLot)
        }
        .sheet(isPresented: $showMerge) {
            ParkingLotMergeView(store: parkingFloorStore, sourceID: lot.id) { dismiss() }
        }
        .alert(String(localized: "地點改名"), isPresented: $showRenameAlert) {
            TextField(String(localized: "名稱"), text: $renamingText)
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "確定")) { parkingFloorStore.setLotName(lotID: lot.id, name: renamingText) }
        }
    }
}

struct AddressCapsuleBeamTestView: View {
    @State private var palette: BorderBeamPalette = .ocean
    @State private var speedKmh: Double = 28
    @State private var address: String = "尖沙咀廣東道 3-27 號"
    @State private var stationarySeconds: Int = 137
    @State private var drivingSeconds: Int = 41 * 60 + 12
    @State private var etaSeconds: Int = 16 * 60 + 48

    var body: some View {
        let statusTitle: String = {
            switch palette {
            case .ocean: return "已開車"
            case .senshackDark: return "已泊車"
            case .mono: return "已停留"
            }
        }()
        let statusValue: String = {
            switch palette {
            case .ocean: return formatClock(drivingSeconds)
            case .senshackDark: return formatClock(2 * 3600 + 47 * 60 + 9)
            case .mono: return formatClock(stationarySeconds)
            }
        }()
        let eta: String? = {
            switch palette {
            case .ocean: return formatCompact(etaSeconds)
            default: return nil
            }
        }()

        List {
            Section {
                Picker("狀態調色", selection: $palette) {
                    ForEach(BorderBeamPalette.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("速度")
                    Spacer()
                    Slider(value: $speedKmh, in: 0...110, step: 1)
                        .frame(maxWidth: 220)
                    Text("\(Int(speedKmh)) km/h")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 82, alignment: .trailing)
                }

                if palette == .senshackDark {
                    Stepper("已泊車秒數: \(stationarySeconds)", value: $stationarySeconds, in: 0...10 * 60 * 60, step: 30)
                } else if palette == .ocean {
                    Stepper("已開車秒數: \(drivingSeconds)", value: $drivingSeconds, in: 0...10 * 60 * 60, step: 30)
                } else {
                    Stepper("已停留秒數: \(stationarySeconds)", value: $stationarySeconds, in: 0...2 * 60 * 60, step: 10)
                }

                if palette == .ocean {
                    Stepper("ETA 秒數: \(etaSeconds)", value: $etaSeconds, in: 0...180 * 60, step: 30)
                }

                TextField("地址文字", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
            } header: {
                Label("參數", systemImage: "slider.horizontal.3")
            } footer: {
                Text("Rotate（光束繞圈）同 Pulse（強度呼吸）分開展示。")
            }

            Section {
                VStack(alignment: .leading, spacing: 18) {
                    beamHeader(title: "Rotate Only（光束繞圈）", detail: "pulse 關")
                    BorderBeamCapsuleDemo(
                        palette: palette,
                        address: address,
                        statusTitle: statusTitle,
                        statusValue: statusValue,
                        etaText: eta,
                        speedKmh: speedKmh,
                        enableRotate: true,
                        enablePulse: false
                    )
                }
            } header: {
                Text("1. Rotate Only")
            }

            Section {
                VStack(alignment: .leading, spacing: 18) {
                    beamHeader(title: "Pulse Only（強度呼吸）", detail: "rotate 關")
                    BorderBeamCapsuleDemo(
                        palette: palette,
                        address: address,
                        statusTitle: statusTitle,
                        statusValue: statusValue,
                        etaText: eta,
                        speedKmh: speedKmh,
                        enableRotate: false,
                        enablePulse: true
                    )
                }
            } header: {
                Text("2. Pulse Only")
            }

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    liquidGlassHeader(title: "Liquid Glass + Rotate", detail: "主頁 compact 44h·270w")
                    LiquidGlassCapsuleDemo(
                        palette: palette,
                        address: address,
                        showSpeed: false,
                        speedKmh: speedKmh,
                        etaText: nil,
                        enableRotate: true,
                        enablePulse: false
                    )
                    liquidGlassHeader(title: "同上（速度模式 370w）", detail: "show speed + eta")
                    LiquidGlassCapsuleDemo(
                        palette: palette,
                        address: address,
                        showSpeed: true,
                        speedKmh: speedKmh,
                        etaText: eta,
                        enableRotate: true,
                        enablePulse: false
                    )
                }
            } header: {
                Text("3. Liquid Glass + Rotate Only")
            }

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    liquidGlassHeader(title: "Liquid Glass + Pulse", detail: "主頁 compact 44h·270w")
                    LiquidGlassCapsuleDemo(
                        palette: palette,
                        address: address,
                        showSpeed: false,
                        speedKmh: speedKmh,
                        etaText: nil,
                        enableRotate: false,
                        enablePulse: true
                    )
                    liquidGlassHeader(title: "同上（速度模式 370w）", detail: "show speed + eta")
                    LiquidGlassCapsuleDemo(
                        palette: palette,
                        address: address,
                        showSpeed: true,
                        speedKmh: speedKmh,
                        etaText: eta,
                        enableRotate: false,
                        enablePulse: true
                    )
                }
            } header: {
                Text("4. Liquid Glass + Pulse Only")
            }
        }
        .navigationTitle("地址膠囊 BorderBeam")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func beamHeader(title: String, detail: String) -> some View {
        let size = BorderBeamSize.large
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%@ · border %.1f  glow %.0f  dur %.1fs",
                        detail,
                        size.borderWidth,
                        size.glowRadius,
                        size.duration))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func liquidGlassHeader(title: String, detail: String) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private func formatClock(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatCompact(_ totalSeconds: Int) -> String {
        let min = (totalSeconds + 59) / 60
        return "\(min) min"
    }
}

struct AltimeterTestView: View {
    @ObservedObject private var barometer = ParkingFloorStore.shared.barometer
    @EnvironmentObject private var locationManager: LocationManager
    @State private var baseAltitude: Double?
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 手動樓層調整
    @State private var manualFloor: Int = 0
    @State private var hasManualFloorSelection: Bool = true
    @State private var showLearnSuccess: Bool = false

    private var altitudeMin: Double {
        guard !barometer.samples.isEmpty else { return 0 }
        return barometer.samples.map { $0.relativeAltitude }.min() ?? 0
    }
    private var altitudeMax: Double {
        guard !barometer.samples.isEmpty else { return 0 }
        return barometer.samples.map { $0.relativeAltitude }.max() ?? 0
    }

    // 速度狀態
    private var speedAge: TimeInterval { now.timeIntervalSince(barometer.lastSpeedUpdateTime) }
    private var gpsIsStale: Bool { speedAge > 5 || barometer.currentSpeedKmh < 0 }
    private var effectiveSpeed: Double { gpsIsStale ? -1 : barometer.currentSpeedKmh }

    // 窗口計算結果
    private var window1: BarometerSessionManager.WindowResult? {
        barometer.altitudeWindow(around: now.addingTimeInterval(-120), before: 4*60, after: 1*60)
    }
    private var window2: BarometerSessionManager.WindowResult? {
        barometer.stationaryRecentWindow(seconds: 2*60)
    }
    private var window3: BarometerSessionManager.WindowResult? {
        barometer.recentWindow(seconds: 2*60)
    }

    // 最佳窗口（模擬 recordParkingPoint 嘅 fallback 鏈）
    private var bestWindow: BarometerSessionManager.WindowResult? {
        if let w = window1, w.samples >= 3 { return w }
        if let w = window2, w.sampleCount >= 3 { return w }
        return window3
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .navigationTitle("氣壓計曲線測試")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { t in now = t }
        .onChange(of: barometer.samples.count) { _, _ in
            if baseAltitude == nil, let first = barometer.samples.first {
                baseAltitude = first.relativeAltitude
            }
        }
    }

    // MARK: - 豎屏佈局（原有 List）

    private var portraitLayout: some View {
        List {
            // 氣壓計狀態
            Section {
                Toggle("主 APP 氣壓計", isOn: Binding(
                    get: { barometer.isUpdating },
                    set: { _ in
                        if barometer.isUpdating { barometer.stop() } else { barometer.startIfAuthorized() }
                    }
                ))
                .tint(.orange)
                infoRow("採樣點數", value: "\(barometer.samples.count)")
                infoRow("支援狀態", value: barometer.isAvailable ? "可用" : "裝置不支援",
                        color: barometer.isAvailable ? .green : .red)
                infoRow("權限", value: barometer.authorizationLabel)
            } header: {
                Label("氣壓計狀態", systemImage: "barometer")
            }

            // 實時感測
            Section {
                if let last = barometer.samples.last {
                    infoRow("相對高度", value: String(format: "%.3f m", last.relativeAltitude))
                    infoRow("氣壓", value: String(format: "%.2f kPa", last.pressure))
                    infoRow("平滑高度", value: String(format: "%.3f m", smoothedLast))
                }
                if let statAlt = barometer.stationaryAltitude {
                    infoRow("停留海拔", value: String(format: "%.3f m", statAlt), color: .green)
                }
                Divider()
                speedInfoRows
            } header: {
                Label("實時感測", systemImage: "sensor.tag.radiowaves.forward.fill")
            }

            // 方案 A：停留海拔
            Section {
                if let sp = stationaryPrediction {
                    infoRow("停留海拔", value: String(format: "%.3f m", sp.ref), color: .green)
                    infoRow("當前平滑", value: String(format: "%.3f m", sp.final))
                    infoRow("Δ", value: String(format: "%+.3f m", sp.delta),
                            color: sp.delta < 0 ? .blue : .orange)
                    Divider()
                    infoRow("Offset", value: sp.predicted.offset)
                    infoRow("Adjusted Δ", value: sp.predicted.adjustedDelta,
                            color: sp.predicted.adjustedDelta.hasPrefix("-") ? .blue : .orange)
                    infoRow("Predicted", value: sp.predicted.rawPredicted)
                    Divider()
                    infoRow("預測樓層", value: sp.predicted.floor, color: sp.predicted.floor == "—" ? .secondary : .blue)
                    infoRow("信心度", value: sp.predicted.confidence)
                } else {
                    Text("等待進入停留中（連續靜止 10 秒）")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("方案 A：停留海拔（泊車樓層）", systemImage: "figure.stand")
            }

            // 目前樓層推算 + 手動調整
            Section {
                if let cp = currentFloorPrediction {
                    infoRow("系統預測", value: cp.floor, color: .purple)
                    infoRow("高度差", value: cp.delta,
                            color: cp.delta.hasPrefix("-") ? .blue : .orange)
                    infoRow("信心度", value: cp.confidence)

                    Divider()

                    // 手動調整樓層
                    HStack {
                        Text("實際樓層")
                            .foregroundStyle(.primary)
                        Spacer()

                        Button {
                            manualFloor -= 1
                            hasManualFloorSelection = true
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)

                        Text(ParkingFloorStore.formatFloor(manualFloor))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .frame(width: 60)
                            .monospacedDigit()

                        Button {
                            manualFloor += 1
                            hasManualFloorSelection = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        learnMetersPerFloor()
                    } label: {
                        HStack {
                            Image(systemName: "brain")
                            Text("學習並套用")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    if showLearnSuccess {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("已學習！下次預測會更準確")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .transition(.opacity)
                    }
                } else {
                    Text("需要先進入停留狀態（靜止 10 秒）")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("目前樓層（即時推算）", systemImage: "figure.walk")
            } footer: {
                Text("調整實際樓層後按「學習並套用」，系統會計算每層樓嘅實際高度，令下次預測更準確")
            }

            // 方案 B：窗口計算
            Section {
                windowRow(label: "① 到達時間窗口", sublabel: "前4分+後1分",
                          window: window1, threshold: 3)
                windowRow(label: "② 靜止樣本窗口", sublabel: "最近2分, <30km/h",
                          window: window2, threshold: 3)
                windowRow(label: "③ 全部樣本窗口", sublabel: "最近2分, 不限速度",
                          window: window3, threshold: 3)
                Divider()
                if bestWindow != nil {
                    infoRow("採用窗口", value: bestWindowLabel, color: .blue)
                } else {
                    infoRow("採用窗口", value: "無可用", color: .red)
                }
            } header: {
                Label("方案 B：窗口計算", systemImage: "rectangle.dashed")
            }

            // 樓層預測（方案 B 結果）
            Section {
                floorPredictionRows
            } header: {
                Label("樓層預測（方案 B）", systemImage: "building.2")
            }

            // 高度曲線
            Section {
                chartSection(chartHeight: 200)
            } header: {
                Label("高度曲線", systemImage: "chart.xyaxis.line")
            }

            // 清除
            Section {
                clearButton
            }
        }
    }

    // MARK: - 橫屏佈局（雙欄 + 底部圖表）

    private var landscapeLayout: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    // 三欄區域
                    HStack(alignment: .top, spacing: 8) {
                        // 欄 1：狀態 + 實時感測
                        VStack(spacing: 6) {
                            compactToggle
                            compactStatusGrid
                            Divider()
                            compactSensorGrid
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        // 欄 2：方案 A + 目前樓層
                        VStack(spacing: 4) {
                            Text("方案 A：停留海拔")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            compactStationarySection

                            Text("目前樓層（即時推算）")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.purple)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            compactCurrentFloorSection
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        // 欄 3：方案 B
                        VStack(spacing: 4) {
                            Text("方案 B：窗口計算")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            compactWindowSection
                            Divider()
                            compactPredictionSection
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12)

                    // 圖表（全寬）
                    chartSection(chartHeight: 160)
                        .padding(.horizontal, 12)

                    // 清除按鈕
                    clearButton
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 橫屏專用組件

    private var compactToggle: some View {
        Toggle("氣壓計", isOn: Binding(
            get: { barometer.isUpdating },
            set: { _ in
                if barometer.isUpdating { barometer.stop() } else { barometer.startIfAuthorized() }
            }
        ))
        .tint(.orange)
        .font(.system(size: 13))
    }

    private var compactStatusGrid: some View {
        VStack(spacing: 2) {
            compactRow("採樣", value: "\(barometer.samples.count)")
            compactRow("狀態", value: barometer.isAvailable ? "可用" : "不支援",
                       color: barometer.isAvailable ? .green : .red)
            compactRow("權限", value: barometer.authorizationLabel)
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    private var compactSensorGrid: some View {
        VStack(spacing: 2) {
            if let last = barometer.samples.last {
                compactRow("高度", value: String(format: "%.3f m", last.relativeAltitude))
                compactRow("氣壓", value: String(format: "%.2f kPa", last.pressure))
                compactRow("平滑", value: String(format: "%.3f m", smoothedLast))
            }
            if let statAlt = barometer.stationaryAltitude {
                compactRow("停留海拔", value: String(format: "%.3f m", statAlt), color: .green)
            }
            compactRow("車速", value: gpsIsStale
                       ? String(format: "%.0f（滯留）", barometer.currentSpeedKmh)
                       : String(format: "%.1f km/h", barometer.currentSpeedKmh),
                       color: gpsIsStale ? .orange : (effectiveSpeed < BarometerSessionManager.captureSpeedThreshold ? .green : .red))
            compactRow("GPS", value: gpsIsStale
                       ? String(format: "失效 %.0fs", speedAge)
                       : String(format: "正常 %.0fs", speedAge),
                       color: gpsIsStale ? .red : .green)
            compactRow("標記", value: gpsIsStale ? String(localized: "未知") : String(format: "%.1f", barometer.currentSpeedKmh),
                       color: gpsIsStale ? .orange : .primary)
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    private var compactStationarySection: some View {
        VStack(spacing: 2) {
            if let sp = stationaryPrediction {
                compactRow("停留海拔", value: String(format: "%.3f m", sp.ref), color: .green)
                compactRow("當前平滑", value: String(format: "%.3f m", sp.final))
                compactRow("Δ", value: String(format: "%+.3f m", sp.delta),
                           color: sp.delta < 0 ? .blue : .orange)
                Divider()
                compactRow("Offset", value: sp.predicted.offset)
                compactRow("Adj Δ", value: sp.predicted.adjustedDelta,
                           color: sp.predicted.adjustedDelta.hasPrefix("-") ? .blue : .orange)
                compactRow("Predicted", value: sp.predicted.rawPredicted)
                Divider()
                compactRow("泊車樓層", value: sp.predicted.floor, color: sp.predicted.floor == "—" ? .secondary : .blue)
            } else {
                Text("等待停留 10s")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    private var compactCurrentFloorSection: some View {
        VStack(spacing: 4) {
            if let cp = currentFloorPrediction {
                compactRow("目前樓層", value: cp.floor, color: .purple)
                compactRow("高度差", value: cp.delta,
                           color: cp.delta.hasPrefix("-") ? .blue : .orange)
                compactRow("信心度", value: cp.confidence)

                Divider()

                // 手動調整樓層
                HStack {
                    Text("實際樓層")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button {
                        manualFloor -= 1
                        hasManualFloorSelection = true
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Text(ParkingFloorStore.formatFloor(manualFloor))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(width: 40)
                        .monospacedDigit()

                    Button {
                        manualFloor += 1
                        hasManualFloorSelection = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    learnMetersPerFloor()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                            .font(.system(size: 11))
                        Text("學習並套用")
                            .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)

                if showLearnSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("已學習！")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity)
                }
            } else {
                Text("等待停留 10s")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    private var compactWindowSection: some View {
        VStack(spacing: 2) {
            compactWindowRow(label: "①到達", window: window1)
            compactWindowRow(label: "②靜止", window: window2)
            compactWindowRow(label: "③全部", window: window3)
            Divider()
            if bestWindow != nil {
                compactRow("採用", value: bestWindowLabel, color: .blue)
            } else {
                compactRow("採用", value: "無可用", color: .red)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    private var compactPredictionSection: some View {
        VStack(spacing: 2) {
            if let best = bestWindow {
                compactRow("Δ", value: String(format: "%+.3f m", best.deltaMeters),
                           color: best.deltaMeters < 0 ? .blue : .orange)
                compactRow("參考", value: String(format: "%.3f m", best.referenceAlt))
                compactRow("最終", value: String(format: "%.3f m", best.finalAlt))
                compactRow("樣本", value: "\(best.sampleCount)")
                Divider()
                let predicted = predictFloorFrom(delta: best.deltaMeters, sampleCount: best.sampleCount)
                compactRow("Offset", value: predicted.offset)
                compactRow("Adj Δ", value: predicted.adjustedDelta,
                           color: predicted.adjustedDelta.hasPrefix("-") ? .blue : .orange)
                compactRow("Predicted", value: predicted.rawPredicted)
                Divider()
                compactRow("樓層", value: predicted.floor, color: predicted.floor == "—" ? .secondary : .blue)
                compactRow("信心", value: predicted.confidence)
                compactRow("每層", value: predicted.mpf)
            } else {
                Text("樣本不足")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - 共用組件

    private var speedInfoRows: some View {
        Group {
            infoRow("當前車速", value: gpsIsStale
                    ? String(format: "%.0f km/h（滯留）", barometer.currentSpeedKmh)
                    : String(format: "%.1f km/h", barometer.currentSpeedKmh),
                    color: gpsIsStale ? .orange : (effectiveSpeed < BarometerSessionManager.captureSpeedThreshold ? .green : .red))
            infoRow("GPS 狀態", value: gpsIsStale
                    ? String(format: "失效（%.0f 秒冇更新）", speedAge)
                    : String(format: "正常（%.0f 秒前更新）", speedAge),
                    color: gpsIsStale ? .red : .green)
            infoRow("速度標記", value: gpsIsStale ? String(localized: "未知") : String(format: "%.1f km/h", barometer.currentSpeedKmh),
                    color: gpsIsStale ? .orange : .primary)
        }
    }

    private var floorPredictionRows: some View {
        Group {
            if let best = bestWindow {
                infoRow("高度差 Δ", value: String(format: "%+.3f m", best.deltaMeters),
                        color: best.deltaMeters < 0 ? .blue : .orange)
                infoRow("參考高度", value: String(format: "%.3f m", best.referenceAlt))
                infoRow("最終高度", value: String(format: "%.3f m", best.finalAlt))
                infoRow("樣本數", value: "\(best.sampleCount)")
                Divider()
                let predicted = predictFloorFrom(delta: best.deltaMeters, sampleCount: best.sampleCount)
                infoRow("Offset", value: predicted.offset)
                infoRow("Adjusted Δ", value: predicted.adjustedDelta,
                        color: predicted.adjustedDelta.hasPrefix("-") ? .blue : .orange)
                infoRow("Predicted", value: predicted.rawPredicted)
                Divider()
                infoRow("預測樓層", value: predicted.floor, color: predicted.floor == "—" ? .secondary : .blue)
                infoRow("信心度", value: predicted.confidence)
                infoRow("每層高度", value: predicted.mpf)
            } else {
                Text("樣本不足，無法預測")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func chartSection(chartHeight: CGFloat) -> some View {
        if barometer.samples.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("高度曲線")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(String(format: "min %.1f  max %.1f", altitudeMin, altitudeMax))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                AltitudeChartView2(
                    samples: barometer.samples,
                    altitudeMin: altitudeMin,
                    altitudeMax: altitudeMax,
                    usedSampleRange: bestWindow?.usedSampleRange,
                    roadBaselineAlt: window1?.referenceAlt,
                    smoothedAlts: smoothedAlts,
                    stationaryAlt: barometer.stationaryAltitude
                )
                .frame(height: chartHeight)

                HStack(spacing: 12) {
                    legendDot(color: .gray, label: "原始曲線")
                    legendDot(color: Color(hex: "46ADB8"), label: "平滑曲線")
                    legendDot(color: .red, label: "高速樣本")
                    legendDot(color: .orange, label: "路面基準")
                    legendDot(color: .green, label: "停留海拔")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        } else {
            Text("累積 2 點以上先會顯示曲線")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.vertical, 8)
        }
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            barometer.clearSamples()
            baseAltitude = nil
        } label: {
            Label("清除數據", systemImage: "trash")
                .font(.system(size: 13))
        }
        .disabled(barometer.samples.isEmpty)
    }

    // MARK: - Helpers

    private var smoothedAlts: [Double] {
        let raw = barometer.samples.map { $0.relativeAltitude }
        guard raw.count > 1 else { return raw }
        let half = 2
        return raw.enumerated().map { i, _ in
            let lo = max(0, i - half)
            let hi = min(raw.count, i + half + 1)
            return raw[lo..<hi].reduce(0, +) / Double(hi - lo)
        }
    }

    private var smoothedLast: Double {
        smoothedAlts.last ?? 0
    }

    private var bestWindowLabel: String {
        if let w1 = window1, w1.samples >= 3 { return "① 到達時間" }
        if let w2 = window2, w2.sampleCount >= 3 { return "② 靜止" }
        return "③ 全部"
    }

    // 方案 A：停留海拔計算
    private var stationaryPrediction: (delta: Double, ref: Double, final: Double, predicted: (floor: String, confidence: String, mpf: String, offset: String, adjustedDelta: String, rawPredicted: String))? {
        guard let statAlt = barometer.stationaryAltitude, barometer.samples.count >= 3 else { return nil }
        let recent = barometer.samples.suffix(10)
        let smoothedFinal = recent.map { $0.relativeAltitude }.reduce(0, +) / Double(recent.count)
        let delta = smoothedFinal - statAlt
        let predicted = predictFloorFrom(delta: delta, sampleCount: recent.count)
        return (delta, statAlt, smoothedFinal, predicted)
    }

    private func predictFloorFrom(delta: Double, sampleCount: Int) -> (floor: String, confidence: String, mpf: String, offset: String, adjustedDelta: String, rawPredicted: String) {
        let lotIdx = ParkingFloorStore.shared.findLotIndex(near: locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(), radiusMeters: 180)
        let mpF: Double
        let offset: Double
        if let idx = lotIdx, let learned = ParkingFloorStore.shared.lots[idx].learnedMetersPerFloor {
            mpF = learned
            offset = ParkingFloorStore.shared.lots[idx].learnedOffsetMeters ?? 0
        } else {
            mpF = 3.0
            offset = 0
        }
        let adjusted = delta - offset
        guard mpF > 0 else { return ("—", "—", String(format: "%.1f m", mpF), String(format: "%+.3f m", offset), String(format: "%+.3f m", adjusted), "—") }
        let raw = adjusted / mpF
        let rounded = raw.rounded(.toNearestOrAwayFromZero)
        let predicted = max(-10, min(30, Int(rounded)))
        let floorStr = ParkingFloorStore.formatFloor(predicted)
        let sampleFactor = sampleCount >= 40 ? 1.0 : (Double(sampleCount) / 40.0)
        let conf = max(0.1, min(0.98, 0.15 + 0.85 * (0.25 * sampleFactor + 0.2 * (lotIdx != nil ? 1.0 : 0.35))))
        return (floorStr, String(format: "%.0f%%", conf * 100), String(format: "%.1f m", mpF), String(format: "%+.3f m", offset), String(format: "%+.3f m", adjusted), String(format: "%+.2f 層", raw))
    }

    // MARK: - 目前樓層推算（相對於泊車海拔）

    /// 目前樓層推算：用泊車時嘅停留海拔做基準，計算而家嘅高度差，推算目前樓層
    private var currentFloorPrediction: (floor: String, delta: String, confidence: String)? {
        // 需要有泊車時嘅停留海拔同目前嘅氣壓計樣本
        guard let parkingAlt = barometer.stationaryAltitude,
              barometer.samples.count >= 3 else { return nil }

        // 用最近 5 個樣本做平滑
        let recent = barometer.samples.suffix(5)
        let currentAlt = recent.map { $0.relativeAltitude }.reduce(0, +) / Double(recent.count)
        let delta = currentAlt - parkingAlt

        // 取得學習數據或用預設值
        let lotIdx = ParkingFloorStore.shared.findLotIndex(
            near: locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D(),
            radiusMeters: 180
        )
        let mpF: Double
        let offset: Double
        if let idx = lotIdx, let learned = ParkingFloorStore.shared.lots[idx].learnedMetersPerFloor {
            mpF = learned
            offset = ParkingFloorStore.shared.lots[idx].learnedOffsetMeters ?? 0
        } else {
            mpF = 3.0
            offset = 0
        }

        let adjusted = delta - offset
        guard mpF > 0 else { return ("—", String(format: "%+.3f m", delta), "—") }

        let raw = adjusted / mpF
        let rounded = raw.rounded(.toNearestOrAwayFromZero)
        let predicted = max(-10, min(30, Int(rounded)))
        let floorStr = ParkingFloorStore.formatFloor(predicted)

        // 信心度計算
        let sampleFactor = recent.count >= 40 ? 1.0 : (Double(recent.count) / 40.0)
        let conf = max(0.1, min(0.98, 0.15 + 0.85 * (0.25 * sampleFactor + 0.2 * (lotIdx != nil ? 1.0 : 0.35))))

        return (floorStr, String(format: "%+.3f m", delta), String(format: "%.0f%%", conf * 100))
    }

    // MARK: - 學習每層樓高度

    private func learnMetersPerFloor() {
        guard let parkingAlt = barometer.stationaryAltitude,
              barometer.samples.count >= 3 else { return }

        // 計算目前高度差
        let recent = barometer.samples.suffix(5)
        let currentAlt = recent.map { $0.relativeAltitude }.reduce(0, +) / Double(recent.count)
        let delta = currentAlt - parkingAlt

        // 手動調整嘅樓層數（相對於泊車樓層 = 0）
        let floorCount = manualFloor

        // 取得目前位置
        let coordinate = locationManager.lastLocation?.coordinate ?? CLLocationCoordinate2D()

        // 計算每層樓高度同 offset
        let metersPerFloor: Double
        let offset: Double

        if floorCount == 0 {
            // 用戶確認目前喺泊車層（G/F）
            // delta 就係海拔偏差，offset = delta 令 adjusted = 0 → 預測 = 0 層
            metersPerFloor = 3.0
            offset = delta
        } else {
            // 計算每層樓高度 = 高度差 / 樓層數
            metersPerFloor = abs(delta / Double(floorCount))
            // offset = delta - floorCount * mpF
            // 令 adjusted = delta - offset = floorCount * mpF → raw = floorCount
            offset = delta - Double(floorCount) * metersPerFloor
        }

        // 儲存學習數據
        ParkingFloorStore.shared.learnMetersPerFloor(
            near: coordinate,
            metersPerFloor: metersPerFloor,
            offset: offset
        )

        // 顯示成功提示
        withAnimation {
            showLearnSuccess = true
        }

        // 2 秒後隱藏提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showLearnSuccess = false
            }
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func infoRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func compactRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func compactWindowRow(label: String, window: BarometerSessionManager.WindowResult?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if let w = window {
                Text("\(w.sampleCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(w.sampleCount >= 3 ? .green : .red)
                    .monospacedDigit()
                Text(String(format: "%+.2f", w.deltaMeters))
                    .font(.system(size: 10))
                    .foregroundStyle(w.deltaMeters < 0 ? .blue : .orange)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func windowRow(label: String, sublabel: String,
                           window: BarometerSessionManager.WindowResult?, threshold: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                if let w = window {
                    Text("\(w.sampleCount) 樣本")
                        .font(.system(size: 12))
                        .foregroundStyle(w.sampleCount >= threshold ? .green : .red)
                        .monospacedDigit()
                } else {
                    Text("無數據").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(sublabel).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let w = window {
                    Text(String(format: "Δ %+.3f m", w.deltaMeters))
                        .font(.system(size: 11))
                        .foregroundStyle(w.deltaMeters < 0 ? .blue : .orange)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }
}

private struct AltitudeChartView2: View {
    let samples: [BarometerSample]
    let altitudeMin: Double
    let altitudeMax: Double
    var usedSampleRange: Range<Int>? = nil
    var roadBaselineAlt: Double? = nil
    var smoothedAlts: [Double]? = nil
    var stationaryAlt: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padH: CGFloat = 14
            let n = samples.count
            let xStep = n <= 1 ? w : w / CGFloat(n - 1)
            let span = max(0.01, altitudeMax - altitudeMin)

            ZStack(alignment: .topLeading) {
                // 網格線
                Path { p in
                    for i in 0..<5 {
                        let y = padH + (h - 2 * padH) * CGFloat(i) / 4.0
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 0.5))

                if n >= 2 {
                    // 灰色原始曲線
                    Path { p in
                        for (i, s) in samples.enumerated() {
                            let x = CGFloat(i) * xStep
                            let t = (s.relativeAltitude - altitudeMin) / span
                            let y = padH + (h - 2 * padH) * CGFloat(1.0 - t)
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

                    // 青色平滑曲線
                    if let smoothed = smoothedAlts, smoothed.count == n {
                        Path { p in
                            for (i, alt) in smoothed.enumerated() {
                                let x = CGFloat(i) * xStep
                                let t = (alt - altitudeMin) / span
                                let y = padH + (h - 2 * padH) * CGFloat(1.0 - t)
                                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                                else { p.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color(hex: "46ADB8"), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }

                    // 預測用樣本範圍填充
                    if let range = usedSampleRange, range.lowerBound < n {
                        Path { p in
                            var started = false
                            for i in range {
                                guard i < samples.count else { break }
                                let x = CGFloat(i) * xStep
                                let t = (samples[i].relativeAltitude - altitudeMin) / span
                                let y = padH + (h - 2 * padH) * CGFloat(1.0 - t)
                                if !started {
                                    p.move(to: CGPoint(x: x, y: h - padH))
                                    p.addLine(to: CGPoint(x: x, y: y))
                                    started = true
                                } else {
                                    p.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            if let lastI = range.last, lastI < samples.count {
                                p.addLine(to: CGPoint(x: CGFloat(lastI) * xStep, y: h - padH))
                                p.addLine(to: CGPoint(x: CGFloat(range.lowerBound) * xStep, y: h - padH))
                                p.closeSubpath()
                            }
                        }
                        .fill(LinearGradient(colors: [Color(hex: "46ADB8").opacity(0.2), Color(hex: "46ADB8").opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                    }

                    // 高速樣本紅點 + GPS失效橙點
                    ForEach(Array(samples.enumerated()), id: \.offset) { item in
                        let x = CGFloat(item.offset) * xStep
                        let t = (item.element.relativeAltitude - altitudeMin) / span
                        let y = padH + (h - 2 * padH) * CGFloat(1.0 - t)
                        if item.element.speedKmh >= BarometerSessionManager.stationarySpeedThreshold {
                            Circle()
                                .fill(Color.red.opacity(0.6))
                                .frame(width: 3, height: 3)
                                .position(x: x, y: y)
                        } else if item.element.speedKmh == 0 && item.offset > 0 {
                            // speedKmh == 0 可能係 GPS 失效自動歸零（非真正靜止）
                            // 呢度只標記最後一批連續 0 速度嘅樣本
                        }
                    }

                    // 路面基準線（水平虛線）
                    if let baseline = roadBaselineAlt {
                        let y = padH + (h - 2 * padH) * CGFloat(1.0 - (baseline - altitudeMin) / span)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    // 停留海拔標記（綠色實線）
                    if let statAlt = stationaryAlt {
                        let y = padH + (h - 2 * padH) * CGFloat(1.0 - (statAlt - altitudeMin) / span)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.green.opacity(0.7), style: StrokeStyle(lineWidth: 1.5))
                    }

                    // 最終高度標記
                    if let last = samples.last {
                        let x = CGFloat(n - 1) * xStep
                        let t = (last.relativeAltitude - altitudeMin) / span
                        let y = padH + (h - 2 * padH) * CGFloat(1.0 - t)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

struct GorillaColorGroupPicker: View {
    @AppStorage("colorGroupMode") private var raw = -1
    @AppStorage("darkKnightMode") private var legacyDarkKnight = false
    @AppStorage("useTimeBasedOrb") private var legacyTimeBased = false
    private var selection: Binding<Int> {
        Binding(get: { GorillaColorGroup.resolve(raw: raw, legacyDarkKnight: legacyDarkKnight,
                                                legacyTimeBased: legacyTimeBased).rawValue },
                set: {
                    raw = $0
                    legacyDarkKnight = $0 == GorillaColorGroup.darkKnight.rawValue
                    legacyTimeBased = $0 == GorillaColorGroup.timeBased.rawValue
                })
    }

    var body: some View {
        Picker("Visual Theme", selection: selection) {
            ForEach([GorillaColorGroup.normal, .timeBased, .darkKnight, .m3Concept], id: \.rawValue) { group in
                Text(LocalizedStringKey(group.titleKey)).tag(group.rawValue)
            }
        }
        .accessibilityIdentifier("colorGroupMode")
        if selection.wrappedValue == GorillaColorGroup.m3Concept.rawValue {
            HStack(spacing: 12) {
                ForEach(M3ConceptPalette.all, id: \.self) { hex in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.15)))
                        .accessibilityLabel("#" + hex)
                }
            }.accessibilityIdentifier("m3Palette")
        }
    }
}

struct VisitRecordingSettingsView: View {
    @AppStorage("visitMinimumNewMinutes") private var minimumNew = 10
    @AppStorage("visitMinimumActiveMinutes") private var minimumActive = 10
    @AppStorage("visitActivateMinutes") private var activateAfter = 15
    @AppStorage("visitMatchRadiusMeters") private var radius = 100
    @AppStorage("visitMergeConsecutive") private var merge = true
    @AppStorage("visitMergeMinutes") private var mergeMinutes = 20
    @AppStorage("visitDeactivateDays") private var deactivateDays = 0

    var body: some View {
        List {
            Section {
                minutePicker("New Places", selection: $minimumNew)
                minutePicker("Active Places", selection: $minimumActive)
            } header: { Text("Minimum Visit Length") } footer: {
                Text("Short completed stops are excluded from the timeline. Parking memory and its arrival timer remain immediate.")
            }
            Section {
                minutePicker("Activate After", selection: $activateAfter)
                Picker("Match Radius", selection: $radius) {
                    ForEach([50, 100, 150, 200, 300], id: \.self) {
                        Text(String(format: String(localized: "%lld m"), Int64($0))).tag($0)
                    }
                }
                Picker("Deactivate After", selection: $deactivateDays) {
                    Text("Never").tag(0)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                LabeledContent("Match Rule", value: String(localized: "Nearest Active Place"))
            } header: { Text("Active Places") } footer: {
                Text("A new place becomes active after a qualifying stay. Future visits match the nearest active place within its radius; inactive places do not match.")
            }
            Section {
                Toggle("Merge Consecutive Visits", isOn: $merge)
                    .accessibilityIdentifier("visitMergeConsecutive")
                minutePicker("Maximum Gap", selection: $mergeMinutes).disabled(!merge)
            } footer: {
                Text("Nearby consecutive visits can be joined across a short gap. Raw events remain available and changing these rules does not delete records or photos.")
            }
        }.navigationTitle("Visit Recording")
    }

    private func minutePicker(_ title: LocalizedStringKey, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach([1, 3, 5, 10, 15, 20, 30, 60], id: \.self) {
                Text(String(format: String(localized: "%lld min"), Int64($0))).tag($0)
            }
        }
    }
}

struct VisitRecordsTestView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @ObservedObject private var replayStore = TripReplayStore.shared
    @State private var showEditSheet: Bool = false
    @State private var editingVisitID: UUID? = nil
    @State private var editTransportType: String = "Driving"
    @State private var editIsAutomotive: Bool = true
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showMap: Bool = false
    @State private var showRawRecords = false
    @State private var timelineNow = Date()
    @State private var timelineEntries: [VisitTimeline.Entry] = []
    @AppStorage("visitMinimumNewMinutes") private var minimumNew = 10
    @AppStorage("visitMinimumActiveMinutes") private var minimumActive = 10
    @AppStorage("visitActivateMinutes") private var activateAfter = 15
    @AppStorage("visitMatchRadiusMeters") private var matchRadius = 100
    @AppStorage("visitMergeConsecutive") private var mergeConsecutive = true
    @AppStorage("visitMergeMinutes") private var mergeMinutes = 20
    @AppStorage("visitDeactivateDays") private var deactivateDays = 0

    private var timelineRules: VisitTimelineRules {
        VisitTimelineRules(
            newPlaceMinutes: minimumNew, activePlaceMinutes: minimumActive,
            activateMinutes: activateAfter, radiusMeters: Double(matchRadius),
            mergeConsecutive: mergeConsecutive, mergeMinutes: mergeMinutes,
            deactivateDays: deactivateDays)
    }

    private func rebuildTimeline(_ records: [LocationManager.VisitRecord]? = nil) {
        timelineEntries = VisitTimeline.make(records ?? locationManager.visits, rules: timelineRules, now: timelineNow)
    }

    private let transportOptions = [
        ("Driving", "car.fill", "開車", true),
        ("Walking", "figure.walk", "步行", false),
        ("Cycling", "bicycle", "騎行", false),
        ("Running", "figure.run", "跑步", false),
        ("Transit", "tram.fill", "公共交通", false),
        ("Train", "train.side.front.car", "高鐵/火車", false),
        ("Airplane", "airplane", "飛機", false),
        ("Ferry", "ferry.fill", "渡輪", false),
    ]

    var body: some View {
        List {
            // 週曆選擇器
            Section {
                weekDatePicker
            }

            if filteredVisits.isEmpty {
                Text("當日沒有到訪記錄")
                    .foregroundStyle(.secondary)
            } else {
                let visits = filteredVisits
                ForEach(Array(visits.enumerated()), id: \.element.id) { idx, visit in
                    // 一條記錄一個白色容器
                    visitCard(visit)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editTransportType = visit.transportType
                            editIsAutomotive = visit.isAutomotive
                            editingVisitID = visit.id
                            showEditSheet = true
                        }
                    // 行程行：冇容器（淨係左側連接線）
                    if idx < visits.count - 1 {
                        tripRow(from: visit, to: visits[idx + 1])
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }
            }

            // 底部操作按鈕
            Section {
                Button(role: .destructive) {
                    clearExceptLatest()
                } label: {
                    Label("清除最新行程以外的記錄", systemImage: "trash")
                }
                Button(role: .destructive) {
                    locationManager.clearVisits()
                } label: {
                    Label("清除所有到訪記錄", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle(LocalizedStringKey(showRawRecords ? "Raw Visit Events" : "到訪記錄"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { timelineNow = .now; rebuildTimeline() }
        .onReceive(locationManager.$visits) { rebuildTimeline($0) }
        .onChange(of: timelineRules) { _, _ in rebuildTimeline() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) {
            timelineNow = $0
            rebuildTimeline()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showRawRecords.toggle() } label: {
                        Label(LocalizedStringKey(showRawRecords ? "Visit Timeline" : "Raw Visit Events"),
                              systemImage: showRawRecords ? "list.bullet" : "doc.text.magnifyingglass")
                    }
                    Button {
                        showMap = true
                    } label: {
                        Label("在地圖上顯示", systemImage: "map")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let visitID = editingVisitID {
                editSheet(visitID: visitID)
            }
        }
        .sheet(isPresented: $showMap) {
            dayMapView
        }
    }

    // MARK: - 篩選後的記錄
    private var filteredVisits: [LocationManager.VisitRecord] {
        let calendar = Calendar.current
        let startOfDay = selectedDate
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return (showRawRecords ? locationManager.visits : timelineEntries.map(\.record))
            .filter { visit in
                // 跨日記錄兩日都要顯示（27 號尾條＋28 號頭條），所以用「重疊」篩選
                // 而唔係淨看到達日；兩邊嘅跨日時間再用 +1/-1 標注
                let start = visit.arrivalDate
                let end = visit.departureDate ?? Date()
                return start < endOfDay && end > startOfDay
            }
            .sorted { $0.arrivalDate < $1.arrivalDate }
    }

    // MARK: - 週曆選擇器
    private var weekDatePicker: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekDays = (-3...3).compactMap { offset -> Date? in
            calendar.date(byAdding: .day, value: offset, to: today)
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(weekDays, id: \.self) { date in
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(date)
                    let weekday = calendar.component(.weekday, from: date)
                    let dayNum = calendar.component(.day, from: date)
                    let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = date
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(weekdaySymbols[weekday - 1])
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? .white : .secondary)
                            Text("\(dayNum)")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(isSelected ? .white : .primary)
                            if isToday {
                                Circle()
                                    .fill(isSelected ? .white : .blue)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .frame(width: 40, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? .blue : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - 當天地圖
    @ViewBuilder
    private var dayMapView: some View {
        NavigationStack {
            Map(coordinateRegion: .constant(mapRegion), annotationItems: mapAnnotations) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: transportIcon(item.transportType))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(item.isAutomotive ? Color.green : Color.orange))
                        Text(item.time, format: .dateTime.hour().minute())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showMap = false }
                }
            }
        }
    }

    // MARK: - Map Annotation Items
    private struct MapAnnotationItem: Identifiable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
        let transportType: String
        let isAutomotive: Bool
        let time: Date
    }

    private var mapAnnotations: [MapAnnotationItem] {
        filteredVisits.map { visit in
            if let point = parkingFloorStore.allPoints.first(where: { abs($0.createdAt.timeIntervalSince(visit.arrivalDate)) < 60 }) {
                return MapAnnotationItem(
                    id: visit.id,
                    coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                    transportType: visit.transportType,
                    isAutomotive: point.isAutomotive,
                    time: visit.arrivalDate
                )
            }
            return MapAnnotationItem(
                id: visit.id,
                coordinate: CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude),
                transportType: visit.transportType,
                isAutomotive: visit.isAutomotive,
                time: visit.arrivalDate
            )
        }
    }

    private var mapRegion: MKCoordinateRegion {
        let adjustedCoords = filteredVisits.map { visit -> CLLocationCoordinate2D in
            if let point = parkingFloorStore.allPoints.first(where: { abs($0.createdAt.timeIntervalSince(visit.arrivalDate)) < 60 }) {
                return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            }
            return CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)
        }
        guard let first = adjustedCoords.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 22.3, longitude: 114.2), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        let minLat = adjustedCoords.map(\.latitude).min() ?? first.latitude
        let maxLat = adjustedCoords.map(\.latitude).max() ?? first.latitude
        let minLon = adjustedCoords.map(\.longitude).min() ?? first.longitude
        let maxLon = adjustedCoords.map(\.longitude).max() ?? first.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.5), longitudeDelta: max(0.01, (maxLon - minLon) * 1.5))
        return MKCoordinateRegion(center: center, span: span)
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter.string(from: selectedDate)
    }

    // MARK: - 清除最新行程以外
    private func clearExceptLatest() {
        guard let latest = locationManager.visits.sorted(by: { $0.arrivalDate > $1.arrivalDate }).first else { return }
        locationManager.visits = [latest]
        locationManager.saveVisits()
    }

    // MARK: - 到訪記錄卡片（一條記錄一個白色容器）
    @ViewBuilder
    private func visitCard(_ visit: LocationManager.VisitRecord) -> some View {
        let name = parkingFloorStore.displayName(for: visit)
        let missingDeparture = visit.departureDate == nil && locationManager.visits.contains { $0.arrivalDate > visit.arrivalDate }
        return HStack(alignment: .top, spacing: 12) {
            // 左側：交通方式圖標
            ZStack {
                Circle()
                    .fill(visit.isAutomotive ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: transportIcon(visit.transportType))
                    .font(.system(size: 16))
                    .foregroundStyle(visit.isAutomotive ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                // 地點名
                Text(name.isEmpty || name == "Unknown" ? String(localized: "未知") : name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !showRawRecords && timelineEntries.contains(where: { $0.id == visit.id && $0.candidate }) {
                    Text("Candidate Visit").font(.caption).foregroundStyle(.secondary)
                }

                // 時間範圍（跨日時間加 +1/-1 標注）
                HStack(spacing: 4) {
                    Text(timeOnly(visit.arrivalDate))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    dayOffsetBadge(for: visit.arrivalDate)
                    Text("→")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.5))
                    if let dep = visit.departureDate {
                        Text(timeOnly(dep))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        dayOffsetBadge(for: dep)
                    } else if missingDeparture {
                        Text("未知")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("至今")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                    }
                }

                // 判定結果
                HStack(spacing: 4) {
                    Circle()
                        .fill(visit.isAutomotive ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(LocalizedStringKey(visit.transportType == "Unknown" ? "Transport Pending" : (visit.isAutomotive ? "開車到達" : "非開車到達")))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(visit.isAutomotive ? .green : .red)
                }
            }

            Spacer(minLength: 8)

            // 右側：停留時長
            Text(missingDeparture ? "—" : visit.duration)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 跨日標注：時間唔屬於顯示日就加個 +1/-1 小膠囊
    /// （27 號睇 `00:52 [+1]`、28 號睇 `22:35 [-1]`）
    @ViewBuilder
    private func dayOffsetBadge(for date: Date) -> some View {
        let calendar = Calendar.current
        let viewDay = calendar.startOfDay(for: selectedDate)
        let dateDay = calendar.startOfDay(for: date)
        if dateDay != viewDay {
            let days = -(calendar.dateComponents([.day], from: dateDay, to: viewDay).day ?? 0)
            Text(days > 0 ? "+\(days)" : "\(days)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.secondary.opacity(0.15)))
                .offset(y: -3)
        }
    }

    // MARK: - 行程記錄（兩個到訪之間，冇容器）
    @ViewBuilder
    private func tripRow(from: LocationManager.VisitRecord, to: LocationManager.VisitRecord) -> some View {
        // 行程窗口：上一筆記錄嘅離場 → 下一筆記錄嘅到達
        let gapStart = from.departureDate
        let gap = to.arrivalDate.timeIntervalSince(gapStart ?? from.arrivalDate)
        // 重疊／壞數據（負數）就唔顯示行程行
        if gap > 0 {
            let items = gapStart.map { tripSegmentItems(from: $0, to: to.arrivalDate) }
                ?? [TripSegmentItem(icon: "clock", text: String(localized: "離場時間未記錄"))]
            HStack(alignment: .top, spacing: 24) {
                // 左側連接線
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 2)
                    .frame(minHeight: 30)

                VStack(alignment: .leading, spacing: 6) {
                    if let gapStart {
                        Text(String(localized: "Journey") + " · " + LocationManager.VisitRecord.formatSpan(to.arrivalDate.timeIntervalSince(gapStart)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !items.isEmpty { TripSegmentSummary(items: items) }
                    if let replay = replayStore.trips.first(where: { $0.destinationVisitID == to.id
                        && ($0.originVisitID == from.id || $0.start >= (gapStart ?? from.arrivalDate)) }) {
                        NavigationLink {
                            TripReplayDetailView(tripID: replay.id)
                        } label: {
                            Label("Trip Replay", systemImage: "play.circle")
                                .font(.caption).foregroundStyle(.tint)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 34)
            .padding(.vertical, 10)
        }
    }

    /// 行程分段以兩次到訪之間的實際窗口為準；重疊或缺失的偵測不猜交通方式。
    private func tripSegmentItems(from: Date, to: Date) -> [TripSegmentItem] {
        let segs = locationManager.tripDisplayTimeline(from: from, to: to)
            .filter { $0.isMovement && $0.resolvedEnd.timeIntervalSince($0.start) >= 60 }
        guard !segs.isEmpty else {
            return []
        }
        return segs.map {
            let duration = LocationManager.VisitRecord.formatSpan($0.resolvedEnd.timeIntervalSince($0.start))
            let text = $0.mode == "Unknown" ? String(localized: "交通方式未明") + " · " + duration : duration
            return TripSegmentItem(
                icon: tripSegmentIcon($0.mode),
                text: text
            )
        }
    }

    private func tripSegmentIcon(_ mode: String) -> String {
        switch mode {
        case "Driving": return "car.fill"
        case "Walking": return "figure.walk"
        case "Cycling": return "bicycle"
        case "Running": return "figure.run"
        case "Stationary": return "pause.fill"
        default: return "ellipsis"
        }
    }

    // MARK: - 編輯 Sheet
    @ViewBuilder
    private func editSheet(visitID: UUID) -> some View {
        NavigationStack {
            List {
                Section(header: Text("交通方式")) {
                    ForEach(transportOptions, id: \.0) { option in
                        Button {
                            editTransportType = option.0
                            editIsAutomotive = option.3
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.1)
                                    .font(.system(size: 18))
                                    .foregroundStyle(editTransportType == option.0 ? .blue : .secondary)
                                    .frame(width: 28)
                                Text(option.2)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if editTransportType == option.0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    HStack {
                        Text("判定結果")
                        Spacer()
                        Text(editIsAutomotive ? "開車到達" : "非開車到達")
                            .foregroundStyle(editIsAutomotive ? .green : .red)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("修改交通方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showEditSheet = false
                        editingVisitID = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        saveTransportChange(visitID: visitID)
                        showEditSheet = false
                        editingVisitID = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 保存修改
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore

    private func saveTransportChange(visitID: UUID) {
        let sourceIDs = Set(showRawRecords ? [visitID] : (timelineEntries.first { $0.id == visitID }?.sourceIDs ?? [visitID]))
        for idx in locationManager.visits.indices where sourceIDs.contains(locationManager.visits[idx].id) {
            let visit = locationManager.visits[idx]
            locationManager.visits[idx] = LocationManager.VisitRecord(
                id: visit.id, address: visit.address, latitude: visit.latitude, longitude: visit.longitude,
                arrivalDate: visit.arrivalDate, departureDate: visit.departureDate,
                transportType: editTransportType, isAutomotive: editIsAutomotive,
                horizontalAccuracy: visit.horizontalAccuracy, transportManuallySet: true
            )
            parkingFloorStore.updateAutomotiveFlag(createdAt: visit.arrivalDate, isAutomotive: editIsAutomotive)
        }
        locationManager.saveVisits()
    }

    // MARK: - Helpers
    private func transportIcon(_ type: String) -> String {
        switch type {
        case "Driving": return "car.fill"
        case "Walking": return "figure.walk"
        case "Cycling": return "bicycle"
        case "Running": return "figure.run"
        case "Transit": return "tram.fill"
        case "Train": return "train.side.front.car"
        case "Airplane": return "airplane"
        case "Ferry": return "ferry.fill"
        case "Passing": return "arrow.triangle.swap"
        default: return "mappin.circle.fill"
        }
    }
}

/// 行程分段顯示項目（參考圖：🚗33min ▶ 🚶1min ▶ 🚗3min ▶ 🚶12min）
private struct TripSegmentItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

private struct TripSegmentSummary: View {
    let items: [TripSegmentItem]

    var body: some View {
        FlowLayout(spacing: 12, lineSpacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .center, spacing: 6) {
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .frame(width: 8, height: 18)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18, height: 18)
                    Text(item.text)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 24)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// 簡單換行流式佈局：行程分段一行唔夠位就自然換行（同參考圖一致）
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        // Keep measurement and placement at the same width; shrinking to the
        // widest row can cause extra wraps without reserving their height.
        return (CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: y + lineHeight), positions, sizes)
    }
}

struct TimeOrbAnimationTestView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @State private var timePreviewHour: Double = Double(Calendar.current.component(.hour, from: Date()))
    @State private var isAutoPlaying = false
    @State private var autoPlayTimer: Timer?
    @StateObject private var previewClock = AnimationClock()
    @StateObject private var previewPhaseManager = TimePhaseManager()

    private var phaseName: String {
        switch previewPhaseManager.currentPhase {
        case .deepNight:   return String(localized: "深夜")
        case .preDawn:     return String(localized: "黎明前")
        case .sunrise:     return String(localized: "日出")
        case .morning:     return String(localized: "日出後")
        case .afternoon:   return String(localized: "下午")
        case .postSunset:  return String(localized: "傍晚")
        case .sunset:      return String(localized: "日落")
        }
    }

    private var phaseColor: Color {
        switch previewPhaseManager.currentPhase {
        case .deepNight:   return Color(hex: "1A1E2E") ?? .black
        case .preDawn:     return Color(hex: "927F6B") ?? .gray
        case .sunrise:     return Color(hex: "DCAC70") ?? .orange
        case .morning:     return Color(hex: "83A3C3") ?? .blue
        case .afternoon:   return Color(hex: "87A3C7") ?? .blue
        case .postSunset:  return Color(hex: "F79D6C") ?? .orange
        case .sunset:      return Color(hex: "926361") ?? .red
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("預覽時間")
                        Spacer()
                        Text(formattedHour(timePreviewHour))
                            .foregroundStyle(isAutoPlaying ? .orange : .secondary)
                            .monospacedDigit()
                    }

                    // 當前階段標註
                    HStack(spacing: 8) {
                        Circle()
                            .fill(phaseColor)
                            .frame(width: 10, height: 10)
                        Text(phaseName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if previewPhaseManager.phaseTransitionProgress > 0 {
                            Text(String(format: String(localized: "→ 漸變中 %d%%"),
                                        Int(previewPhaseManager.phaseTransitionProgress * 100)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Slider(value: $timePreviewHour, in: 0...24, step: 0.5)
                            .tint(.orange)
                            .disabled(isAutoPlaying)
                            .onChange(of: timePreviewHour) { _, v in
                                if !isAutoPlaying {
                                    previewPhaseManager.setPreviewHour(v)
                                }
                            }

                        Button {
                            toggleAutoPlay()
                        } label: {
                            Image(systemName: isAutoPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .circle)
                        }
                    }

                    // 階段時間軸
                    phaseTimeline
                    HStack {
                        Label("日出", systemImage: "sunrise")
                        Text(formattedHour(previewPhaseManager.schedule.sunriseHour))
                        Spacer()
                        Label("日落", systemImage: "sunset")
                        Text(formattedHour(previewPhaseManager.schedule.sunsetHour))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    if !previewPhaseManager.hasActualSunTimes {
                        Text("暫用預設時間，等待定位或日出日落資料")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Link("Sunrise-Sunset.org", destination: URL(string: "https://sunrise-sunset.org")!)
                        .font(.caption)

                    GeometryReader { geo in
                        let phoneHeight = geo.size.width * (19.5 / 9.0)
                        TimeBasedOrbView(phaseManager: previewPhaseManager, clock: previewClock, orbEnabled: true)
                            .frame(width: geo.size.width, height: phoneHeight)
                    }
                    .frame(height: UIScreen.main.bounds.width * (19.5 / 9.0))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .onAppear {
                    previewClock.start()
                    previewPhaseManager.start()
                    previewPhaseManager.setPreviewHour(timePreviewHour)
                }
                .onDisappear {
                    stopAutoPlay()
                    previewClock.stop()
                    previewPhaseManager.stop()
                }
            }
        }
        .navigationTitle("時程光球動畫測試")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(locationManager.$lastLocation) { location in
            guard let location, location.horizontalAccuracy >= 0 else { return }
            previewPhaseManager.fetchSunTimes(for: location.coordinate)
        }
    }

    // MARK: - 階段時間軸

    private func formattedHour(_ hour: Double) -> String {
        let minutes = Int((hour * 60).rounded())
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private var phaseTimeline: some View {
        let segments = previewPhaseManager.schedule.segments
        return VStack(spacing: 4) {
            // 色條
            GeometryReader { geo in
                let w = geo.size.width
                let h: CGFloat = 8
                ZStack(alignment: .leading) {
                    // 背景色塊
                    HStack(spacing: 0) {
                        ForEach(segments.indices, id: \.self) { i in
                            let segment = segments[i]
                            segment.phase.colors.background3
                                .frame(width: w * (segment.end - segment.start) / 24)
                        }
                    }
                    .clipShape(Capsule())

                    // 當前位置指示器
                    let x = w * timePreviewHour / 24
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: x - 6)
                }
            }
            .frame(height: 8)

            // 時間標籤
            HStack {
                Text("0").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("6").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("12").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("18").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("24").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    
    private func toggleAutoPlay() {
        if isAutoPlaying {
            stopAutoPlay()
        } else {
            startAutoPlay()
        }
    }
    
    private func startAutoPlay() {
        isAutoPlaying = true
        autoPlayTimer?.invalidate()
        autoPlayTimer = Timer(timeInterval: 0.35, repeats: true) { _ in
            DispatchQueue.main.async {
                timePreviewHour += 0.5
                if timePreviewHour > 24 { timePreviewHour = 0 }
                previewPhaseManager.setPreviewHour(timePreviewHour)
            }
        }
        if let t = autoPlayTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    private func stopAutoPlay() {
        isAutoPlaying = false
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
    }
}

struct SpeedAnimationTestView: View {
    @State private var simSpeed: Double = 0
    @StateObject private var sfxPlayer = SFXPlayer()
    @State private var sfxEnabled = true
    @AppStorage("sfxAccelerationEnabled") private var sfxAccelerationEnabled: Bool = false
    @AppStorage("darkKnightMode") private var legacyDarkKnightMode = false
    @AppStorage("colorGroupMode") private var colorGroupRaw = -1
    @AppStorage("orbColorPreset") private var orbColorPreset = 0
    private var colorGroup: GorillaColorGroup {
        .resolve(raw: colorGroupRaw, legacyDarkKnight: legacyDarkKnightMode)
    }
    @State private var accelArmedFromStop: Bool = true
    @State private var lastSpeedSample: Double = 0
    @State private var lastSpeedSampleAt: Date = Date()
    @State private var accelerationCooldownUntil: Date = .distantPast

    private var speedColor: Color {
        Color(hex: dotColorHex)
    }

    private var dotColorHex: String {
        colorGroup.dotColorHex(speed: simSpeed, preset: orbColorPreset)
    }

    var body: some View {
        List {
            Section {
                GorillaColorGroupPicker()
                Toggle("測試音效", isOn: $sfxEnabled)
                
                HStack(spacing: 12) {
                    Button("已停留") {
                        sfxPlayer.playEnterStationary()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("已開車") {
                        sfxPlayer.playEnterDriving()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("加速") {
                        if sfxAccelerationEnabled {
                            sfxPlayer.playAccelerationBurst()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("重置到 0") {
                    simSpeed = 0
                }
                .buttonStyle(.bordered)
            }
            
            Section {
                DotMatrixView(speed: $simSpeed, accentColor: speedColor, dynamicColorHex: dotColorHex)
                    .frame(minHeight: 360)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(colorGroup == .m3Concept ? Color(hex: M3ConceptPalette.black)
                        : (colorGroup == .darkKnight ? Color.black : Color.clear))
            }
        }
        .onChange(of: simSpeed) { _, newSpeed in
            guard sfxEnabled, sfxAccelerationEnabled else { return }
            
            let now = Date()
            let dt = now.timeIntervalSince(lastSpeedSampleAt)
            let prev = lastSpeedSample
            lastSpeedSampleAt = now
            lastSpeedSample = newSpeed
            
            if newSpeed <= 1 {
                accelArmedFromStop = true
                return
            }
            
            guard accelArmedFromStop else { return }
            guard now >= accelerationCooldownUntil else { return }
            guard dt > 0.02, dt < 1.0 else { return }
            
            let dv = newSpeed - prev
            if prev <= 2, newSpeed >= 10, dv >= 8, dt <= 0.35 {
                accelArmedFromStop = false
                accelerationCooldownUntil = now.addingTimeInterval(1.2)
                sfxPlayer.playAccelerationBurst()
            }
        }
        .navigationTitle("模擬動畫時速動畫測試")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 添加目的地视图
struct AddDestinationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var destinationManager: DestinationManager
    @EnvironmentObject private var locationManager: LocationManager
    
    @Namespace private var glassNamespace
    @State private var searchText = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var showingNameEditor = false
    @State private var searchResults: [MKLocalSearchCompletion] = []
    @State private var searchCompleter: MKLocalSearchCompleter?
    @State private var searchDelegate: SearchCompleterDelegate?
    
    var body: some View {
        ZStack {
            // 地圖全屏
            MapSelectionView(selectedCoordinate: $selectedCoordinate)
                .ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

            VStack(spacing: 0) {
                // 頂部懸浮控制欄
                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .glassEffect(.regular, in: .circle)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.6))
                            TextField("搜尋地點...", text: $searchText)
                                .font(.system(size: 17))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("searchCancel", in: glassNamespace)

                        if !searchText.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    searchText = ""
                                    searchResults.removeAll()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 42, height: 42)
                                    .glassEffect(.regular, in: .circle)
                            }
                            .glassEffectID("searchCancel", in: glassNamespace)
                            .transition(.scale.combined(with: .opacity))
                        }

                        if selectedCoordinate != nil {
                            Button {
                                showingNameEditor = true
                            } label: {
                                Text("下一步")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .glassEffect(.regular, in: .capsule)
                                    .background(
                                        Color(hex: "46ADB8").opacity(0.45)
                                            .clipShape(Capsule())
                                            .allowsHitTesting(false)
                                    )
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
                .onChange(of: searchText) { _, newValue in
                    searchCompleter?.queryFragment = newValue
                }

                // 搜索結果下拉列表
                if !searchResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.headline)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    searchAndSelectLocation(result)
                                }

                                if index < searchResults.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .clipShape(.rect(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxHeight: 300)
                }

                Spacer()
            }
        }
        .onAppear {
            setupSearchCompleter()
        }
        .sheet(isPresented: $showingNameEditor) {
            if let coordinate = selectedCoordinate {
                DestinationNameEditorView(coordinate: coordinate)
            }
        }
    }
    
    private func setupSearchCompleter() {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = .address
        let delegate = SearchCompleterDelegate { results in
            self.searchResults = results
        }
        completer.delegate = delegate
        searchCompleter = completer
        searchDelegate = delegate
    }
    
    private func searchAndSelectLocation(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let item = response?.mapItems.first {
                DispatchQueue.main.async {
                    // In mainland China, MKLocalSearch returns GCJ-02 coordinates
                    // (AutoNavi map data). Convert back to WGS-84 so the stored
                    // destination matches the app's coordinate convention
                    // (store WGS-84, convert to GCJ-02 at display/route time).
                    // Outside China this is a no-op.
                    selectedCoordinate = item.placemark.coordinate.gcj02ToWGS84
                    searchText = item.name ?? ""
                    searchResults.removeAll()
                }
            }
        }
    }
}

// 搜索结果代理
class SearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    let onUpdate: ([MKLocalSearchCompletion]) -> Void
    
    init(onUpdate: @escaping ([MKLocalSearchCompletion]) -> Void) {
        self.onUpdate = onUpdate
        super.init()
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onUpdate(completer.results)
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onUpdate([])
    }
}

// 地图选择视图
struct MapSelectionView: View {
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        MapViewWrapper(initialCenter: initialCenter, selectedCoordinate: $selectedCoordinate)
            .edgesIgnoringSafeArea(.bottom)
            .overlay(
                VStack {
                    Spacer()
                    if selectedCoordinate != nil {
                        Text("Press Next to continue")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            .padding(.bottom, 20)
                    } else {
                        Text("Long press on the map to select a location")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            .padding(.bottom, 20)
                    }
                }
            )
    }

    private var initialCenter: CLLocationCoordinate2D {
        if let location = locationManager.manager.location {
            return location.coordinate.wgs84ToGCJ02
        }
        return CLLocationCoordinate2D(latitude: 22.3, longitude: 114.2)  // 香港默認
    }
}

// 地图包装器
struct MapViewWrapper: UIViewRepresentable {
    var initialCenter: CLLocationCoordinate2D
    @Binding var selectedCoordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // 首次定位：用 GPS 位置居中
        let region = MKCoordinateRegion(center: initialCenter, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        mapView.setRegion(region, animated: false)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // 更新標記（不重設 region，讓用戶自由移動）
        let currentIDs = Set(uiView.annotations.compactMap { ($0 as? MKPointAnnotation)?.title })
        let newCoord = selectedCoordinate
        if let coordinate = newCoord {
            let title = "\(coordinate.latitude),\(coordinate.longitude)"
            if !currentIDs.contains(title) {
                uiView.removeAnnotations(uiView.annotations)
                let annotation = MKPointAnnotation()
                annotation.title = title
                annotation.coordinate = coordinate.wgs84ToGCJ02
                uiView.addAnnotation(annotation)
            }
        } else if !uiView.annotations.isEmpty {
            uiView.removeAnnotations(uiView.annotations)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWrapper

        init(_ parent: MapViewWrapper) {
            self.parent = parent
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            if gesture.state == .began {
                let point = gesture.location(in: mapView)
                let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
                DispatchQueue.main.async { [self] in
                    // In mainland China the map's screen→coordinate conversion
                    // yields GCJ-02 (the display frame of the AutoNavi tiles).
                    // Convert back to WGS-84 before storing (no-op outside China).
                    parent.selectedCoordinate = coordinate.gcj02ToWGS84
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // region 由 initialCenter 決定，不再回寫
        }
    }
}

// 目的地名称和颜色设置视图
struct DestinationNameEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var destinationManager: DestinationManager
    @EnvironmentObject private var locationManager: LocationManager
    
    let coordinate: CLLocationCoordinate2D
    var existingDestination: Destination?
    
    @State private var name = ""
    @State private var selectedColor: Color = .red
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Destination name", text: $name)
                }
                
                Section("Color") {
                    ColorPicker("選擇顏色", selection: $selectedColor, supportsOpacity: false)
                }
            }
            .navigationTitle(existingDestination == nil ? "新增目的地" : "編輯目的地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveDestination()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let existing = existingDestination {
                    name = existing.name
                    selectedColor = Color(hex: existing.colorHex) ?? .red
                }
            }
        }
    }
    
    private func saveDestination() {
        let hex = colorToHex(selectedColor)
        
        if let existing = existingDestination {
            // 编辑已有目的地
            var updated = existing
            updated.name = name
            updated.colorHex = hex
            destinationManager.updateDestination(updated)
            dismiss()
        } else {
            // 新增目的地
            let destination = Destination(
                name: name,
                coordinate: coordinate,
                colorHex: hex
            )
            
            if let currentLocation = locationManager.manager.location?.coordinate {
                destinationManager.calculateRoute(from: currentLocation, to: coordinate) { distance, time in
                    var updatedDestination = destination
                    updatedDestination.drivingDistance = distance
                    updatedDestination.drivingTime = time
                    destinationManager.addDestination(updatedDestination)
                    dismiss()
                }
            } else {
                destinationManager.addDestination(destination)
                dismiss()
            }
        }
    }
    
    private func colorToHex(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(r * 255)
        let gi = Int(g * 255)
        let bi = Int(b * 255)
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}

// MARK: - 地點管理（統一改名 + 路線學習記錄）
struct PlaceManagementView: View {
    @ObservedObject private var predictor = TripPredictor.shared
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    @State private var renamingKey: String?        // placeCatalog key or "lot:\(lotID)"
    @State private var renamingText: String = ""
    @State private var showRenameAlert = false
    @State private var placeSearchText = ""
    @State private var mapPreviewCoordinate: CLLocationCoordinate2D?
    @State private var mapPreviewName: String = ""
    @State private var trashSelection: TrashSelection?

    var body: some View {
        List {
            // ── Section 1：停車場（有揸車到達記錄嘅 lot；混合 lot 都歸入呢度）──
            Section {
                let automotiveLots = parkingFloorStore.lots.filter { lot in
                    lot.points.contains { $0.isAutomotive } && lotMatches(placeSearchText, lot)
                }
                if automotiveLots.isEmpty {
                    Text("暫無停車場數據。")
                        .foregroundStyle(.secondary)
                }
                ForEach(automotiveLots) { lot in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lot.preferredDisplayName ?? "未命名")
                                .font(.subheadline.weight(.semibold))
                            Text(lotPointSummary(lot) + "  ·  " + String(format: "%.5f, %.5f", lot.centerLatitude, lot.centerLongitude))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            renamingKey = "lot:\(lot.id.uuidString)"
                            renamingText = lot.preferredDisplayName ?? ""
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        mapPreviewName = lot.preferredDisplayName ?? "未命名停車場"
                        mapPreviewCoordinate = CLLocationCoordinate2D(latitude: lot.centerLatitude, longitude: lot.centerLongitude)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        NavigationLink {
                            ParkingLotPointsView(lot: lot)
                        } label: {
                            Label("詳情", systemImage: "info.circle")
                        }
                        .tint(.blue)
                        Button(role: .destructive) {
                            // 刪除停車場
                            parkingFloorStore.deleteLot(lotID: lot.id)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("停車場", systemImage: "parkingsign.circle.fill")
            } footer: {
                Text("揸車到達嘅記錄點會聚合成停車場。同一個地點如果你又揸車去過又行路去過，兩種記錄會歸入同一個停車場（顯示做「N 停車點 · M 逗留點」）。改名會同步到地圖標點、學習地點同搜尋選單。")
            }

            // ── Section 1.5：逗留點（全部點都係行路／跑步／踩單車到達）──
            Section {
                let stayLots = parkingFloorStore.lots.filter { lot in
                    !lot.points.contains { $0.isAutomotive } && lotMatches(placeSearchText, lot)
                }
                if stayLots.isEmpty {
                    Text("暫無逗留點數據。")
                        .foregroundStyle(.secondary)
                }
                ForEach(stayLots) { lot in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lot.preferredDisplayName ?? "未命名")
                                .font(.subheadline.weight(.semibold))
                            Text("\(lot.points.count) 逗留點  ·  " + String(format: "%.5f, %.5f", lot.centerLatitude, lot.centerLongitude))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            renamingKey = "lot:\(lot.id.uuidString)"
                            renamingText = lot.preferredDisplayName ?? ""
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        mapPreviewName = lot.preferredDisplayName ?? "未命名逗留點"
                        mapPreviewCoordinate = CLLocationCoordinate2D(latitude: lot.centerLatitude, longitude: lot.centerLongitude)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        NavigationLink {
                            ParkingLotPointsView(lot: lot)
                        } label: {
                            Label("詳情", systemImage: "info.circle")
                        }
                        .tint(.blue)
                        Button(role: .destructive) {
                            parkingFloorStore.deleteLot(lotID: lot.id)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("逗留點", systemImage: "figure.walk")
            } footer: {
                Text("行路／跑步／踩單車到達嘅停留記錄，管理方式同停車場一樣：成個地點改名、睇詳情、刪除。地圖嘅停車／逗留點彈窗入面都可以即時改名。")
            }

            // ── Section 2：學習地點（placeCatalog 中的 .addressCluster，舊名「地址叢集」）──
            let clusters = predictor.placeCatalog.values
                .filter { $0.kind == .addressCluster && placeMatches(placeSearchText, $0) }
                .sorted { $0.updatedAt > $1.updatedAt }
            Section {
                if clusters.isEmpty {
                    Text("暫無學習地點。")
                        .foregroundStyle(.secondary)
                }
                ForEach(clusters) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(String(format: "%.5f, %.5f", p.latitude, p.longitude))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(p.updatedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            renamingKey = p.key
                            renamingText = p.displayName
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        mapPreviewName = p.displayName
                        mapPreviewCoordinate = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            // 刪除學習地點（soft delete：入「最近刪除」，7 日內可還原）
                            parkingFloorStore.deletePlace(p)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("學習地點", systemImage: "mappin.and.ellipse")
            } footer: {
                Text("系統由你嘅到訪記錄自動學識嘅地方（以前叫「地址叢集」），用嚟預測下一站去邊。改名會同步到附近同位置嘅停車場。")
            }

            // ── Section 3：最近刪除（回收桶，7 日保留）──
            Section {
                let pointBatches = Dictionary(grouping: parkingFloorStore.deletedPoints, by: { $0.batchID })
                    .map { (batchID: $0.key, entries: $0.value) }
                    .sorted { ($0.entries.first?.deletedAt ?? .distantPast) > ($1.entries.first?.deletedAt ?? .distantPast) }
                let placeEntries = parkingFloorStore.deletedPlaces.sorted { $0.deletedAt > $1.deletedAt }
                if pointBatches.isEmpty && placeEntries.isEmpty {
                    Text("暫無最近刪除嘅項目。")
                        .foregroundStyle(.secondary)
                }
                ForEach(pointBatches, id: \.batchID) { batch in
                    let entries = batch.entries
                    Button {
                        trashSelection = .pointBatch(batchID: batch.batchID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entries.first?.lotName ?? "未命名")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text((entries.count > 1 ? "\(entries.count) 個點 · " : (entries.first?.point.isAutomotive == true ? "停車點 · " : "逗留點 · ")) + (entries.first?.deletedAt.formatted(.dateTime.year().month().day().hour().minute()) ?? ""))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
                ForEach(placeEntries) { entry in
                    Button {
                        trashSelection = .place(entryID: entry.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.place.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("學習地點 · " + entry.deletedAt.formatted(.dateTime.year().month().day().hour().minute()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            } header: {
                Label("最近刪除", systemImage: "trash")
            } footer: {
                Text("刪除嘅停車點／逗留點同學習地點會保留 7 日，期間可以還原；7 日後自動清理。成個停車場刪除嘅點會一齊保留，可以成批還原。")
            }

            // ── 總覽 ──
            Section("總覽") {
                HStack {
                    Text("已學習地點")
                    Spacer()
                    Text("\(predictor.placeCatalog.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Pattern 規則數")
                    Spacer()
                    Text("\(predictor.patterns.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("最近到訪 place")
                    Spacer()
                    Text("\(predictor.recentPlaceHistory.count)")
                        .foregroundStyle(.secondary)
                }
                if let summary = predictor.lastPredictionSummary {
                    HStack(alignment: .top) {
                        Text("最近一次預測")
                        Spacer()
                        Text(summary)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            // ── Pattern 規則（只讀）──
            Section("排程規劃") {
                if predictor.patterns.isEmpty {
                    Text("暫無 pattern，需要至少 2 次真實到訪 + 離開先會有第一條。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(predictor.patterns.values.sorted(by: { $0.updatedAt > $1.updatedAt }))) { rec in
                    VStack(alignment: .leading, spacing: 10) {
                        // 路線標題：星期 + 時段
                        HStack {
                            let weekdayNames = ["", "日", "一", "二", "三", "四", "五", "六"]
                            let wd = (1...7).contains(rec.key.weekday) ? weekdayNames[rec.key.weekday] : "?"
                            Text("星期\(wd) \(rec.key.timeSlot.description)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            let prefix = rec.key.twoGramFromFromKey != nil ? "3-gram" : "2-gram"
                            Text(prefix)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }

                        // 路線流程
                        let fromName = rec.key.fromKey.flatMap { predictor.placeCatalog[$0]?.displayName } ?? "（首次出發）"
                        let extraName = rec.key.twoGramFromFromKey.flatMap { predictor.placeCatalog[$0]?.displayName }
                        HStack(spacing: 6) {
                            if let extra = extraName {
                                Text(extra)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(fromName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("下一站")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        // 候選目的地
                        let scored = rec.candidates.values
                            .map { (c: TripNextCandidate) -> (String, Int, Double, Double) in
                                let score = c.effectiveScore
                                let conf = rec.confidence(for: c)
                                return (c.toPlaceKey, c.hitCount, conf, score)
                            }
                            .sorted { $0.2 > $1.2 }

                        VStack(spacing: 6) {
                            ForEach(Array(scored.enumerated()), id: \.offset) { _, item in
                                let (key, hits, conf, score) = item
                                let place = predictor.placeCatalog[key]
                                HStack {
                                    // 目的地名稱
                                    Text(place?.displayName ?? key)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    // 統計信息
                                    HStack(spacing: 12) {
                                        Text("Score \(Int(score.rounded())) (\(hits)次)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)

                                        Text("\(Int(conf*100))%")
                                            .font(.subheadline.monospacedDigit().weight(.bold))
                                            .foregroundStyle(
                                                conf >= 0.85 ? .green :
                                                    conf >= 0.6 ? .orange : .secondary
                                            )
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                            }
                        }

                        // 否認記錄
                        if let deny = rec.candidates.values.first(where: { $0.denyCount > 0 }) {
                            HStack {
                                Image(systemName: "hand.thumbsdown.fill")
                                    .foregroundStyle(.red)
                                Text("用戶否認過 \(deny.denyCount) 次")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            // ── 最近到訪歷史 ──
            Section("最近到訪歷史（用於2-gram/3-gram連續站預測）") {
                if predictor.recentPlaceHistory.isEmpty {
                    Text("尚未有到訪記錄。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(predictor.recentPlaceHistory.enumerated()), id: \.offset) { i, p in
                    HStack {
                        Text("#\(predictor.recentPlaceHistory.count - i)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.displayName)
                                .font(.footnote.weight(.semibold))
                            Text(p.updatedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
            }

            // ── Reset ──
            Section("手動 Reset 數據") {
                Button(role: .destructive) {
                    let ud = UserDefaults.standard
                    ud.removeObject(forKey: "trip_predict_place_catalog_v1")
                    ud.removeObject(forKey: "trip_predict_patterns_v1")
                    ud.removeObject(forKey: "trip_predict_recent_history_v1")
                    predictor.placeCatalog = [:]
                    predictor.patterns = [:]
                    predictor.recentPlaceHistory = []
                } label: {
                    Label("Reset 所有學習數據", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("地點管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $placeSearchText, prompt: "搜尋地點")
        .alert("地點改名", isPresented: $showRenameAlert) {
            TextField("名稱", text: $renamingText)
            Button("取消", role: .cancel) { renamingKey = nil }
            Button("確定") {
                guard let key = renamingKey else { return }
                let newName = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !newName.isEmpty else { return }
                if key.hasPrefix("lot:") {
                    // 停車場改名：更新 ParkingLotRecord + placeCatalog
                    let lotIDStr = String(key.dropFirst(4))
                    if let lotID = UUID(uuidString: lotIDStr) {
                        parkingFloorStore.setLotName(lotID: lotID, name: newName)
                    }
                } else {
                    // 學習地點改名：更新 placeCatalog + 同步對應停車場名
                    predictor.renamePlace(key: key, newName: newName)
                }
                renamingKey = nil
            }
        }
        .sheet(item: Binding<MapPinItem?>(
            get: {
                guard let coord = mapPreviewCoordinate else { return nil }
                return MapPinItem(name: mapPreviewName, coordinate: coord)
            },
            set: { _ in mapPreviewCoordinate = nil }
        )) { item in
            PlaceMapPreviewSheet(name: item.name, coordinate: item.coordinate)
        }
        .sheet(item: $trashSelection) { selection in
            TrashDetailSheet(selection: selection)
        }
    }

    /// 點數摘要：混合 lot（同時有停車點同逗留點）顯示兩種數量
    private func lotPointSummary(_ lot: ParkingLotRecord) -> String {
        let stay = lot.points.filter { !$0.isAutomotive }.count
        let auto = lot.points.count - stay
        return stay > 0 ? "\(auto) 停車點 · \(stay) 逗留點" : "\(auto) 停車點"
    }

    private func lotMatches(_ query: String, _ lot: ParkingLotRecord) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if (lot.preferredDisplayName ?? "").localizedCaseInsensitiveContains(q) { return true }
        if String(format: "%.5f, %.5f", lot.centerLatitude, lot.centerLongitude).contains(q) { return true }
        return lot.points.contains { $0.address.localizedCaseInsensitiveContains(q) }
    }

    private func placeMatches(_ query: String, _ place: PlaceInfo) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return place.displayName.localizedCaseInsensitiveContains(q)
    }
}

// MARK: - 停車場停車點列表（可刪除）
struct ParkingLotPointsView: View {
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    let lot: ParkingLotRecord
    @Environment(\.dismiss) private var dismiss
    @State private var pointToDelete: ParkingPointRecord?
    @State private var showDeleteAlert = false
    @State private var renamingFloor: Int?
    @State private var floorName = ""
    @State private var showFloorNameAlert = false

    private var currentLot: ParkingLotRecord? { parkingFloorStore.lots.first { $0.id == lot.id } }
    private var floors: [Int] {
        Set(currentLot?.points.compactMap { $0.manualFloorIndex ?? $0.predictedFloorIndex } ?? []).sorted(by: >)
    }

    var body: some View {
        List {
            if let currentLot {
                if parkingFloorStore.floorMode == .perVisit {
                    ForEach(floors, id: \.self) { floor in
                        Section {
                            ForEach(currentLot.points.filter { ($0.manualFloorIndex ?? $0.predictedFloorIndex) == floor }
                                .sorted { $0.createdAt > $1.createdAt }) { point in pointRow(point) }
                        } header: {
                            HStack {
                                Text(currentLot.floorNames?[String(floor)]
                                     ?? ParkingFloorStore.formatFloor(floor, coordinate: currentLot.centerCoordinate))
                                Spacer()
                                Button {
                                    renamingFloor = floor
                                    floorName = currentLot.floorNames?[String(floor)] ?? ""
                                    showFloorNameAlert = true
                                } label: { Image(systemName: "pencil") }
                                .accessibilityLabel(String(localized: "命名此樓層"))
                            }
                        }
                    }
                    Section(String(localized: "樓層未確認")) {
                        ForEach(currentLot.points.filter { $0.manualFloorIndex == nil && $0.predictedFloorIndex == nil }) {
                            pointRow($0)
                        }
                    }
                } else {
                    ForEach(currentLot.points.sorted { $0.createdAt > $1.createdAt }) { point in pointRow(point) }
                }
            } else {
                Text(String(localized: "停車場已被刪除")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(currentLot?.preferredDisplayName ?? String(localized: "停車點管理"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ParkingLotDetailView(lot: lot) } label: { Image(systemName: "info.circle") }
            }
        }
        .alert(String(localized: "命名此樓層"), isPresented: $showFloorNameAlert) {
            TextField(String(localized: "名稱"), text: $floorName)
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "確定")) {
                guard let floor = renamingFloor else { return }
                parkingFloorStore.setFloorName(lotID: lot.id, floor: floor, name: floorName)
            }
        }
        .alert(String(localized: "確認刪除"), isPresented: $showDeleteAlert) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "刪除"), role: .destructive) {
                if let point = pointToDelete {
                    parkingFloorStore.deletePoint(pointID: point.id)
                    if currentLot == nil { dismiss() }
                }
            }
        } message: {
            Text(String(localized: "確定要刪除此停車點嗎？刪除後會放入「最近刪除」，7 日內可以還原。"))
        }
    }

    private func pointRow(_ point: ParkingPointRecord) -> some View {
        NavigationLink { ParkingPointDiagnosticsView(pointID: point.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentLot?.displayName(for: point, mode: parkingFloorStore.floorMode)
                     ?? (point.address.isEmpty ? String(localized: "未命名停車場") : point.address))
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Text(point.createdAt, format: .dateTime.year().month().day().hour().minute())
                    Spacer()
                    if let floor = point.displayFloor { Text(floor).monospacedDigit() }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button(role: .destructive) { pointToDelete = point; showDeleteAlert = true } label: {
                Label(String(localized: "刪除"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Map Pin Item（for sheet binding）
private struct MapPinItem: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Place Map Preview Sheet
private struct PlaceMapPreviewSheet: View {
    let name: String
    let coordinate: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        self.coordinate = coordinate
        // 地圖中心用 GCJ02（中國地圖磚偏移），確保標記和中心對齊
        let gcj = coordinate.wgs84ToGCJ02
        _region = State(initialValue: MKCoordinateRegion(
            center: gcj,
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        ))
    }

    var body: some View {
        NavigationStack {
            Map(position: .constant(.region(region))) {
                Marker(name, coordinate: coordinate.wgs84ToGCJ02)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

// MARK: - 最近刪除（回收桶）詳情 Sheet
private enum TrashSelection: Identifiable {
    /// 單一停車點／逗留點，或者成個停車場刪除嗰批（同一 batchID）
    case pointBatch(batchID: UUID)
    case place(entryID: String)

    var id: String {
        switch self {
        case .pointBatch(let batchID): return "batch-\(batchID.uuidString)"
        case .place(let entryID): return "place-\(entryID)"
        }
    }
}

private struct TrashDetailSheet: View {
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    @Environment(\.dismiss) private var dismiss
    let selection: TrashSelection

    @State private var showPurgeAlert = false

    private var pointEntries: [DeletedPointEntry] {
        switch selection {
        case .pointBatch(let batchID):
            return parkingFloorStore.deletedPoints
                .filter { $0.batchID == batchID }
                .sorted { $0.point.createdAt > $1.point.createdAt }
        case .place:
            return []
        }
    }

    private var placeEntry: DeletedPlaceEntry? {
        if case .place(let entryID) = selection {
            return parkingFloorStore.deletedPlaces.first { $0.id == entryID }
        }
        return nil
    }

    private var title: String {
        if let placeEntry { return placeEntry.place.displayName }
        return pointEntries.first?.lotName ?? "最近刪除"
    }

    private var kindText: String {
        if placeEntry != nil { return "學習地點" }
        guard let first = pointEntries.first else { return "—" }
        return first.point.isAutomotive ? "停車點" : "逗留點"
    }

    private var coordinate: CLLocationCoordinate2D? {
        if let placeEntry {
            return CLLocationCoordinate2D(latitude: placeEntry.place.latitude, longitude: placeEntry.place.longitude)
        }
        guard let first = pointEntries.first else { return nil }
        return first.point.coordinate
    }

    private var deletedAt: Date? {
        placeEntry?.deletedAt ?? pointEntries.first?.deletedAt
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let coordinate {
                        // 地圖中心用 GCJ02（中國地圖磚偏移），確保標記和中心對齊
                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: coordinate.wgs84ToGCJ02,
                            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                        )))) {
                            Marker(title, coordinate: coordinate.wgs84ToGCJ02)
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(spacing: 0) {
                        TrashInfoRow(label: "原先名字", value: title)
                        TrashInfoRow(label: "類型", value: kindText)
                        if let placeEntry {
                            TrashInfoRow(label: "記錄時間", value: placeEntry.place.updatedAt.formatted(.dateTime.year().month().day().hour().minute()))
                        }
                        if let deletedAt {
                            TrashInfoRow(label: "刪除時間", value: deletedAt.formatted(.dateTime.year().month().day().hour().minute()))
                        }
                        if let coordinate {
                            TrashInfoRow(label: "坐標", value: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        }
                    }
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

                    // 咪錶標注（如果當初係停喺咪錶旁）
                    if let meterTag = pointEntries.first?.point.meterTag {
                        HStack(spacing: 6) {
                            Image(systemName: "parkingsign.circle.fill")
                                .foregroundStyle(.orange)
                            Text(meterTag)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // 成批刪除（成個停車場）時顯示入面每個點
                    if pointEntries.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("入面 \(pointEntries.count) 個點")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(pointEntries) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.point.createdAt.formatted(.dateTime.year().month().day().hour().minute()))
                                        .font(.caption)
                                    Text(String(format: "%.5f, %.5f", entry.point.latitude, entry.point.longitude))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    Button {
                        restore()
                        dismiss()
                    } label: {
                        Label("還原", systemImage: "arrow.uturn.backward.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        showPurgeAlert = true
                    } label: {
                        Label("永久刪除", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(16)
            }
            .navigationTitle("最近刪除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("永久刪除", isPresented: $showPurgeAlert) {
            Button("取消", role: .cancel) {}
            Button("永久刪除", role: .destructive) {
                purge()
                dismiss()
            }
        } message: {
            Text("永久刪除後無法復原。確定要刪除嗎？")
        }
    }

    private func restore() {
        switch selection {
        case .pointBatch(let batchID):
            parkingFloorStore.restoreBatch(batchID: batchID)
        case .place(let entryID):
            parkingFloorStore.restorePlace(entryID: entryID)
        }
    }

    private func purge() {
        switch selection {
        case .pointBatch(let batchID):
            for entry in parkingFloorStore.deletedPoints.filter({ $0.batchID == batchID }) {
                parkingFloorStore.permanentlyDeletePoint(entryID: entry.id)
            }
        case .place(let entryID):
            parkingFloorStore.permanentlyDeletePlace(entryID: entryID)
        }
    }
}

private struct TrashInfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Parking Memory Photo Test View
struct ParkingMemoryPhotoTestView: View {
    @StateObject private var animationClock = AnimationClock()

    // Test photo model — mirrors ParkingPhoto's per-photo random rotation/offsets
    struct TestPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let rotation: Double   // -10...10 (same as ParkingPhoto.savePhoto)
        let offsetX: Double    // -6...6
        let offsetY: Double    // -4...4
    }

    // Sample photos
    @State private var photos: [TestPhoto] = []

    // UI state
    @State private var showingExpanded = false
    @State private var selectedIndex: Int? = nil
    @State private var showDeleteButton = false
    @State private var isCapturePressed = false

    // TILT animation state (per photo)
    @State private var tiltAngleX: [Int: Double] = [:]   // photo index → X rotation
    @State private var tiltAngleY: [Int: Double] = [:]   // photo index → Y rotation

    // Delete animation state — the photo is tracked by ID (not index), so the
    // index shift after removal can't wrongly hide the next photo
    @State private var deletingPhoto: TestPhoto? = nil
    @State private var deletingIndex: Int? = nil  // original index — tilt values lookup only
    @State private var deleteBlur: CGFloat = 0
    @State private var deleteOpacity: Double = 1.0
    @State private var deleteOffsetY: CGFloat = 0

    static func makeSamplePhotos() -> [TestPhoto] {
        let colors: [(UIColor, UIColor)] = [
            (UIColor(hex: "FF6B6B"), UIColor(hex: "FF8E53")),
            (UIColor(hex: "4ECDC4"), UIColor(hex: "556270")),
            (UIColor(hex: "667EEA"), UIColor(hex: "764BA2")),
        ]
        return (0..<3).map { i in
            TestPhoto(
                image: makeGradientImage(text: "Photo \(i + 1)", c1: colors[i].0, c2: colors[i].1),
                rotation: Double.random(in: -10...10),
                offsetX: Double.random(in: -6...6),
                offsetY: Double.random(in: -4...4)
            )
        }
    }

    static func makeGradientImage(text: String, c1: UIColor, c2: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400))
        return renderer.image { ctx in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [c1.cgColor, c2.cgColor] as CFArray,
                                      locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient,
                                             start: .zero,
                                             end: CGPoint(x: 600, y: 400),
                                             options: [])
            let label = text as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: (600 - size.width) / 2, y: (400 - size.height) / 2),
                       withAttributes: attrs)
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("泊車記憶拍照效果測試")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Description
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("照片瀏覽動畫 — 3D TILT", systemImage: "rotate.3d")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "4ECDC4"))
                        Text("點擊照片瀏覽時，3D 透視扭曲效果，中間先放大，四邊跟上")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Label("刪除效果 — Smoky Dissolve", systemImage: "smoke.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "FF6B6B"))
                            .padding(.top, 4)
                        Text("照片溶解伴隨高斯模糊，化為煙霧散去")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Camera section (identical layout to main page)
                cameraTestSection
                    .padding(.top, 10)

                Spacer()

                // Reset button
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        photos = Self.makeSamplePhotos()
                        showingExpanded = false
                        selectedIndex = nil
                        showDeleteButton = false
                        tiltAngleX = [:]
                        tiltAngleY = [:]
                        deletingPhoto = nil
                        deletingIndex = nil
                    }
                } label: {
                    Text("重置照片")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            animationClock.start()
            if photos.isEmpty {
                photos = Self.makeSamplePhotos()
            }
        }
        .onDisappear {
            animationClock.stop()
        }
        // Delete button timing — identical to main page
        .onChange(of: selectedIndex) { _, newIndex in
            if newIndex != nil {
                showDeleteButton = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showDeleteButton = true
                    }
                }
            } else {
                showDeleteButton = false
            }
        }
    }

    // MARK: - Camera Section (identical layout to main page)
    private var cameraTestSection: some View {
        ZStack(alignment: .topLeading) {
            // Simulated camera preview (gradient background)
            RoundedRectangle(cornerRadius: 37)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 338, height: 190)
                .overlay(
                    RoundedRectangle(cornerRadius: 37)
                        .stroke(Color.white.opacity(0.8), lineWidth: 4)
                )
                .overlay {
                    if !showingExpanded {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.15))
                    }
                }

            dimTestOverlay
            photoTestStack

            // Camera capture button (right side)
            cameraTestButton

            // Delete button on selected photo (positioned at photo's top-left corner)
            if let idx = selectedIndex, idx < photos.count, showDeleteButton, deletingPhoto == nil {
                Button {
                    triggerSmokyDissolve(index: idx)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: .circle)
                        .glassEffect(.regular, in: .circle)
                }
                .position(x: 72, y: 34)
                .transition(.opacity)
            }

            // Thumbnail-only tap area for expanding (top-left, matching thumb position)
            if !showingExpanded {
                Color.clear
                    .frame(width: 80, height: 70)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showingExpanded = true
                            selectedIndex = nil
                        }
                    }
            }
        }
        .frame(width: 338, height: 190)
    }

    // MARK: - Dim Overlay (always rendered — smooth fades like main page)
    private var dimTestOverlay: some View {
        let dimOpacity: Double = showingExpanded ? (selectedIndex != nil ? 0.65 : 0.45) : 0
        return Color.black.opacity(dimOpacity)
            .frame(width: 338, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 37))
            .animation(.easeInOut(duration: 0.3), value: selectedIndex)
            .animation(.easeInOut(duration: 0.3), value: showingExpanded)
            .contentShape(Rectangle())
            .onTapGesture {
                guard showingExpanded else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    if let idx = selectedIndex {
                        resetTilt(index: idx)
                        selectedIndex = nil
                    } else {
                        showingExpanded = false
                        selectedIndex = nil
                    }
                    tiltAngleX = [:]
                    tiltAngleY = [:]
                }
            }
    }

    // MARK: - Photo Stack
    private var photoTestStack: some View {
        let count = photos.count
        return ZStack {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                // Skip by ID — an index-based check would wrongly hide the next
                // photo when indices shift after the deleted one is removed
                if photo.id != deletingPhoto?.id {
                    photoTestItem(photo: photo, index: index, totalCount: count,
                                  isExpanded: showingExpanded,
                                  isSelected: selectedIndex == index)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                if showingExpanded {
                                    let wasSelected = selectedIndex == index
                                    if wasSelected {
                                        // Deselect — reset tilt
                                        resetTilt(index: index)
                                        selectedIndex = nil
                                    } else {
                                        // Select new — reset old, trigger TILT on new
                                        if let oldIdx = selectedIndex {
                                            resetTilt(index: oldIdx)
                                        }
                                        selectedIndex = index
                                        triggerTiltEffect(index: index)
                                    }
                                }
                            }
                        }
                }
            }

            // Deleting photo overlay (smoky dissolve — matches the selected photo
            // exactly, including any in-flight TILT, so the handoff never flashes)
            if let delPhoto = deletingPhoto {
                let delTiltX = tiltAngleX[deletingIndex ?? -1] ?? 0
                let delTiltY = tiltAngleY[deletingIndex ?? -1] ?? 0
                let selectedScale: CGFloat = (190 - 24) / (32 * 3.8)
                let delTiltScale: CGFloat = 1.0 + abs(delTiltX) * 0.003
                let delTiltShadow: CGFloat = abs(delTiltX) * 0.5
                let delTiltLiftY: CGFloat = -abs(delTiltX) * 0.3
                Image(uiImage: delPhoto.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46 * 3.8, height: 32 * 3.8)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(1.0), lineWidth: 2.0 / selectedScale)
                    )
                    .shadow(color: .black.opacity(0.4), radius: delTiltShadow, y: delTiltShadow * 0.5)
                    .scaleEffect(delTiltScale)
                    .offset(y: delTiltLiftY)
                    .rotation3DEffect(.degrees(delTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                    .rotation3DEffect(.degrees(delTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .scaleEffect(selectedScale)
                    .blur(radius: deleteBlur)
                    .opacity(deleteOpacity)
                    .offset(y: deleteOffsetY)
                    .zIndex(200)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 338, height: 190, alignment: .center)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard showingExpanded, photos.count > 1 else { return }
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        // Reset tilt on old photo
                        if let cur = selectedIndex {
                            resetTilt(index: cur)
                        }
                        if horizontal < 0 {
                            if let cur = selectedIndex {
                                selectedIndex = (cur + 1) % photos.count
                            } else {
                                selectedIndex = 0
                            }
                        } else {
                            if let cur = selectedIndex {
                                selectedIndex = (cur - 1 + photos.count) % photos.count
                            } else {
                                selectedIndex = photos.count - 1
                            }
                        }
                        // Trigger TILT on new photo
                        if let newIdx = selectedIndex {
                            triggerTiltEffect(index: newIdx)
                        }
                    }
                }
        )
    }

    // MARK: - Single Photo Item (identical math to main-page CameraPhotoItem, plus TILT)
    @ViewBuilder
    private func photoTestItem(photo: TestPhoto, index: Int, totalCount: Int,
                               isExpanded: Bool, isSelected: Bool) -> some View {
        let baseW: CGFloat = 46
        let baseH: CGFloat = 32
        let expandedW: CGFloat = 46 * 3.8
        let expandedH: CGFloat = 32 * 3.8
        let thumbBaseX: CGFloat = -(338 / 2 - 20 - 46 / 2)
        let thumbBaseY: CGFloat = -(190 / 2 - 18 - 32 / 2)

        let photoW = isExpanded ? expandedW : baseW
        let photoH = isExpanded ? expandedH : baseH
        let selectedScale: CGFloat = (190 - 24) / expandedH
        let photoScale: CGFloat = isSelected ? selectedScale : (isExpanded ? 0.85 : 1.0)

        let finalOffsetX: CGFloat = {
            if isSelected { return 0 }
            if isExpanded {
                let raw = CGFloat(photo.offsetX) * 22
                let maxX: CGFloat = (338 - expandedW) / 2 - 12
                return max(-maxX, min(maxX, raw))
            }
            return thumbBaseX + CGFloat(photo.offsetX)
        }()
        let finalOffsetY: CGFloat = {
            if isSelected { return 0 }
            if isExpanded {
                let raw = CGFloat(photo.offsetY) * 12
                let maxY: CGFloat = (190 - expandedH) / 2 - 5
                return max(-maxY, min(maxY, raw))
            }
            return thumbBaseY + CGFloat(photo.offsetY)
        }()
        let finalRotation: CGFloat = {
            if isSelected { return 0 }
            if isExpanded {
                let normX = max(-1, min(1, CGFloat(photo.offsetX) / 6))
                return normX * 12
            }
            return CGFloat(photo.rotation)
        }()

        let borderW: CGFloat = isSelected ? 2.0 / selectedScale : (isExpanded ? 1.5 : 1.0)
        let borderOpacity: Double = isSelected ? 1.0 : (isExpanded ? 0.6 : 0.8)
        let cr: CGFloat = isSelected ? 12 : (isExpanded ? 5 * 3.8 : 5)
        let zIdx: Double = isSelected ? 100 : Double(totalCount - index)

        // TILT: center-lift helpers
        let tiltX = tiltAngleX[index] ?? 0
        let tiltY = tiltAngleY[index] ?? 0
        let tiltScale: CGFloat = 1.0 + abs(tiltX) * 0.003
        let tiltShadow: CGFloat = abs(tiltX) * 0.5
        let tiltLiftY: CGFloat = -abs(tiltX) * 0.3

        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: photoW, height: photoH)
            .clipShape(RoundedRectangle(cornerRadius: cr))
            .overlay(
                RoundedRectangle(cornerRadius: cr)
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: borderW)
            )
            // Center-lift TILT: shadow grows, scale rises, slight upward offset
            .shadow(color: .black.opacity(0.4), radius: tiltShadow, y: tiltShadow * 0.5)
            .scaleEffect(tiltScale)
            .offset(y: tiltLiftY)
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            // Main-page transforms (same order as CameraPhotoItem)
            .rotationEffect(.degrees(finalRotation))
            .offset(x: finalOffsetX, y: finalOffsetY)
            .scaleEffect(photoScale)
            .zIndex(zIdx)
            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(Double(totalCount - 1 - index) * 0.06), value: isExpanded)
            .animation(.spring(response: 0.4, dampingFraction: 0.82).delay(Double(totalCount - 1 - index) * 0.06), value: isSelected)
    }

    // MARK: - TILT trigger — center picks up first, corners follow
    private func triggerTiltEffect(index: Int) {
        // Phase 1: center lifts sharply — like grabbing the middle of a towel
        // Small rotation just for subtle 3D depth, main effect is the scale + shadow
        withAnimation(.spring(response: 0.28, dampingFraction: 0.4)) {
            tiltAngleX[index] = -18
            tiltAngleY[index] = Double.random(in: -8...8)
        }
        // Phase 2: corners catch up — paper settles flat with a bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                self.tiltAngleX[index] = 0
                self.tiltAngleY[index] = 0
            }
        }
    }

    private func resetTilt(index: Int) {
        tiltAngleX[index] = 0
        tiltAngleY[index] = 0
    }

    // MARK: - Smoky Dissolve Effect — blur + drift down, no scaling
    private func triggerSmokyDissolve(index: Int) {
        guard index < photos.count else { return }
        let targetID = photos[index].id
        deletingPhoto = photos[index]  // snapshot the photo itself — ID-stable
        deletingIndex = index
        showDeleteButton = false

        // Single smooth dissolve: blur grows, opacity fades, drifts down gently
        withAnimation(.easeOut(duration: 0.85)) {
            deleteBlur = 20
            deleteOpacity = 0
            deleteOffsetY = 25
        }

        // Remove after 0.5s — dissolve is 87% done by then (opacity ≈ 0.13)
        // so the next photo zooms up without waiting for the full animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                photos.removeAll { $0.id == targetID }
                // Reset tilt state and re-index
                var newTiltAngleX: [Int: Double] = [:]
                var newTiltAngleY: [Int: Double] = [:]
                for (k, v) in tiltAngleX where k < index {
                    newTiltAngleX[k] = v
                }
                for (k, v) in tiltAngleX where k > index {
                    newTiltAngleX[k - 1] = v
                }
                for (k, v) in tiltAngleY where k < index {
                    newTiltAngleY[k] = v
                }
                for (k, v) in tiltAngleY where k > index {
                    newTiltAngleY[k - 1] = v
                }
                tiltAngleX = newTiltAngleX
                tiltAngleY = newTiltAngleY
                showingExpanded = photos.count > 0
                // Auto-select the next photo so it zooms up for browsing
                // (the photo that shifts into the deleted slot, or the new last one)
                selectedIndex = photos.isEmpty ? nil : min(index, photos.count - 1)
            }
            // TILT flourish on the auto-selected photo (same as tap-selection)
            if !photos.isEmpty {
                triggerTiltEffect(index: min(index, photos.count - 1))
            }
            // Clean up and bring back the delete button for the new selection
            deletingPhoto = nil
            deletingIndex = nil
            deleteBlur = 0
            deleteOpacity = 1.0
            deleteOffsetY = 0
            // Show delete button for the auto-selected photo
            // (mirrors .onChange timing: 0.3s delay + spring)
            if selectedIndex != nil {
                showDeleteButton = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if selectedIndex != nil, deletingPhoto == nil {
                            showDeleteButton = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Camera Button (identical to main page — blur + hide when expanded / full)
    private var cameraTestButton: some View {
        Button(action: {
            // Simulate capture — add a new random gradient photo
            guard photos.count < 3 else { return }
            let hue = Double.random(in: 0...1)
            let c1 = UIColor(hue: CGFloat(hue), saturation: 0.7, brightness: 0.9, alpha: 1)
            let c2 = UIColor(hue: CGFloat(hue + 0.15).truncatingRemainder(dividingBy: 1),
                             saturation: 0.8, brightness: 0.7, alpha: 1)
            let img = Self.makeGradientImage(text: "Photo \(photos.count + 1)", c1: c1, c2: c2)
            let photo = TestPhoto(image: img,
                                  rotation: Double.random(in: -10...10),
                                  offsetX: Double.random(in: -6...6),
                                  offsetY: Double.random(in: -4...4))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                photos.append(photo)
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 25)
                    .frame(width: 65, height: 164)
                    .glassEffect(.regular, in: .rect(cornerRadius: 25))
                    .tint(.clear)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let t = animationClock.elapsed * 0.3
                    ZStack {
                        Circle()
                            .fill(Color(hex: "3497FF").opacity(0.85))
                            .blur(radius: 16)
                            .frame(width: 100, height: 100)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.4 - 50,
                                    y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 50)
                        Circle()
                            .fill(Color(hex: "FFC46D").opacity(0.85))
                            .frame(width: 110, height: 110)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.35 - 55,
                                    y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 55)
                        Circle()
                            .fill(Color(hex: "FF825C").opacity(0.85))
                            .frame(width: 90, height: 90)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.38 - 45,
                                    y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.35 - 45)
                    }
                }
                .frame(width: 57, height: 156)
                .clipShape(.rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white, lineWidth: 1.6))
                Image(systemName: "camera.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isCapturePressed ? 0.88 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCapturePressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isCapturePressed = pressing
        }, perform: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
        .blur(radius: showingExpanded || photos.count >= 3 ? 12 : 0)
        .opacity(showingExpanded || photos.count >= 3 ? 0 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showingExpanded)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: photos.count)
    }
}

// MARK: - Parking Memory Swipe Test View — isolated test for deck-swipe animation

struct ParkingMemorySwipeTestView: View {
    // Test photo model
    struct TestPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let rotation: Double
        let offsetX: Double
        let offsetY: Double
    }

    @State private var photos: [TestPhoto] = []

    // Capsule state
    @State private var isExpanded = false

    // Photo browsing state
    @State private var showingExpandedPhotos = false
    @State private var selectedPhotoIndex: Int? = nil
    @State private var showDeleteButton = false

    // TILT animation state
    @State private var tiltAngleX: [Int: Double] = [:]
    @State private var tiltAngleY: [Int: Double] = [:]

    // Swipe gesture state
    @State private var photoSwipeOffset: CGFloat = 0
    @State private var isPhotoSwiping = false
    @State private var isPhotoAnimatingOut = false
    @State private var photoAnimatingOutIndex: Int? = nil
    @State private var isSwipingPhoto = false        // true during slide-out + return
    @State private var swipePhotoScale: CGFloat = 1  // animated scale during swipe

    // Delete animation state
    @State private var deletingPhoto: TestPhoto? = nil
    @State private var deletingIndex: Int? = nil
    @State private var deleteBlur: CGFloat = 0
    @State private var deleteOpacity: Double = 1.0
    @State private var deleteOffsetY: CGFloat = 0

    static func makeSamplePhotos() -> [TestPhoto] {
        let colors: [(UIColor, UIColor)] = [
            (UIColor(hex: "FF6B6B"), UIColor(hex: "FF8E53")),
            (UIColor(hex: "4ECDC4"), UIColor(hex: "556270")),
            (UIColor(hex: "667EEA"), UIColor(hex: "764BA2")),
        ]
        return (0..<3).map { i in
            TestPhoto(
                image: ParkingMemoryPhotoTestView.makeGradientImage(text: "Photo \(i + 1)", c1: colors[i].0, c2: colors[i].1),
                rotation: Double.random(in: -10...10),
                offsetX: Double.random(in: -6...6),
                offsetY: Double.random(in: -4...4)
            )
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("抽離牌組動畫測試")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Description
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("抽離牌組動畫", systemImage: "rectangle.split.3x1")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "4ECDC4"))
                        Text("左右滑動切換照片，圖片抽離、層級處理、ease-in/out 動畫")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Label("手勢跟手度", systemImage: "hand.draw")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "FF6B6B"))
                            .padding(.top, 4)
                        Text("滑動起始應立即跟手，不應有跳躍感")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Capsule (compact mode replica)
                swipeTestCapsule
                    .padding(.top, 10)

                Spacer()

                // Reset button
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        photos = Self.makeSamplePhotos()
                        isExpanded = false
                        showingExpandedPhotos = false
                        selectedPhotoIndex = nil
                        showDeleteButton = false
                        tiltAngleX = [:]
                        tiltAngleY = [:]
                        deletingPhoto = nil
                        deletingIndex = nil
                        photoSwipeOffset = 0
                        isPhotoSwiping = false
                        isPhotoAnimatingOut = false
                        photoAnimatingOutIndex = nil
                    }
                } label: {
                    Text("重置照片")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if photos.isEmpty {
                photos = Self.makeSamplePhotos()
            }
        }
    }

    // MARK: - Capsule (compact mode replica)
    private var swipeTestCapsule: some View {
        let capsuleHeight: CGFloat = isExpanded ? 495 : 44
        let capsuleWidth: CGFloat = isExpanded ? 370 : 270

        return ZStack {
            if isExpanded {
                // Expanded: camera section with photo stack
                swipeTestExpandedContent
                    .transition(.opacity)
            } else {
                // Compact: capsule text
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("泊車記憶")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(photos.count) 張照片")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(Color.black.opacity(0.55))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .clipShape(.rect(cornerRadius: 34))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isExpanded.toggle()
                if !isExpanded {
                    showingExpandedPhotos = false
                    selectedPhotoIndex = nil
                    tiltAngleX = [:]
                    tiltAngleY = [:]
                }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    // MARK: - Expanded content
    private var swipeTestExpandedContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isExpanded = false
                        showingExpandedPhotos = false
                        selectedPhotoIndex = nil
                        tiltAngleX = [:]
                        tiltAngleY = [:]
                    }
                }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text("泊車記憶")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(photos.count) 張照片")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            // Camera section with photo stack
            swipeTestCameraSection
                .padding(.top, 10)

            Spacer()
        }
    }

    // MARK: - Camera Section
    private var swipeTestCameraSection: some View {
        ZStack(alignment: .topLeading) {
            // Camera preview background
            RoundedRectangle(cornerRadius: 37)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 338, height: 235)
                .overlay(
                    RoundedRectangle(cornerRadius: 37)
                        .stroke(Color.white.opacity(0.8), lineWidth: 4)
                )
                .overlay {
                    if !showingExpandedPhotos {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.15))
                    }
                }

            // Dim overlay
            let dimOpacity: Double = showingExpandedPhotos ? (selectedPhotoIndex != nil ? 0.65 : 0.45) : 0
            Color.black.opacity(dimOpacity)
                .frame(width: 338, height: 235)
                .clipShape(RoundedRectangle(cornerRadius: 37))
                .animation(.easeInOut(duration: 0.3), value: selectedPhotoIndex)
                .animation(.easeInOut(duration: 0.3), value: showingExpandedPhotos)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard showingExpandedPhotos else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        if let idx = selectedPhotoIndex {
                            resetTilt(index: idx)
                            selectedPhotoIndex = nil
                        } else {
                            showingExpandedPhotos = false
                            selectedPhotoIndex = nil
                        }
                        tiltAngleX = [:]
                        tiltAngleY = [:]
                    }
                }

            // Photo stack with full swipe animation
            swipeTestPhotoStack

            // Delete button
            if let idx = selectedPhotoIndex, idx < photos.count, showDeleteButton, deletingPhoto == nil {
                Button {
                    triggerSmokyDissolve(index: idx)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: .circle)
                        .glassEffect(.regular, in: .circle)
                }
                .position(x: 72, y: 34)
                .transition(.opacity)
            }

            // Thumbnail tap area for expanding
            if !showingExpandedPhotos {
                Color.clear
                    .frame(width: 80, height: 70)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showingExpandedPhotos = true
                            selectedPhotoIndex = nil
                        }
                    }
            }
        }
        .frame(width: 338, height: 235)
    }

    // MARK: - Photo Stack with full swipe animation
    private var swipeTestPhotoStack: some View {
        let count = photos.count
        return ZStack {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                if photo.id != deletingPhoto?.id {
                    swipeTestPhotoItem(photo: photo, index: index, totalCount: count)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                if showingExpandedPhotos {
                                    let wasSelected = selectedPhotoIndex == index
                                    if wasSelected {
                                        resetTilt(index: index)
                                        selectedPhotoIndex = nil
                                    } else {
                                        if let oldIdx = selectedPhotoIndex {
                                            resetTilt(index: oldIdx)
                                        }
                                        selectedPhotoIndex = index
                                        triggerTiltEffect(index: index)
                                        showDeleteButton = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                if selectedPhotoIndex == index, deletingPhoto == nil {
                                                    showDeleteButton = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                }
            }

            // Smoky dissolve overlay
            swipeTestDissolveOverlay
        }
        .frame(width: 338, height: 235, alignment: .center)
        .contentShape(Rectangle())
        .mask(
            // Clip photos to preview bounds only in expanded view
            Group {
                if showingExpandedPhotos {
                    RoundedRectangle(cornerRadius: 37)
                } else {
                    Rectangle()
                }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard showingExpandedPhotos, selectedPhotoIndex != nil, photos.count > 1 else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    // Only respond to clear horizontal swipes
                    guard abs(horizontal) > abs(vertical) * 0.5 else { return }

                    let direction: CGFloat = horizontal < 0 ? -1 : 1
                    let nextIndex: Int
                    if horizontal < 0 {
                        nextIndex = ((selectedPhotoIndex ?? 0) + 1) % photos.count
                    } else {
                        nextIndex = ((selectedPhotoIndex ?? 0) - 1 + photos.count) % photos.count
                    }
                    let oldIndex = selectedPhotoIndex ?? 0

                    // Hide delete button immediately
                    withAnimation(.easeOut(duration: 0.15)) {
                        showDeleteButton = false
                    }

                    // ═══════════════════════════════════════════════════════
                    // New photo starts enlarging FIRST
                    // ═══════════════════════════════════════════════════════
                    triggerTiltEffect(index: nextIndex)

                    // ═══════════════════════════════════════════════════════
                    // Phase 1: Slide out + shrink (0.15s after TILT)
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        let fullScale: CGFloat = (235 - 24) / (32 * 3.8)
                        isSwipingPhoto = true
                        swipePhotoScale = fullScale

                        withAnimation(.easeOut(duration: 0.5)) {
                            photoSwipeOffset = direction * 180
                        }
                        withAnimation(.easeOut(duration: 0.8)) {
                            swipePhotoScale = 0.85
                        }
                    }

                    // ═══════════════════════════════════════════════════════
                    // Phase 2: Drop z-index once photo is near the edge
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        photoAnimatingOutIndex = oldIndex
                        isPhotoAnimatingOut = true
                    }

                    // ═══════════════════════════════════════════════════════
                    // Phase 3: Slide back to stack (photo already at stack scale)
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                            photoSwipeOffset = 0
                        }
                        isPhotoSwiping = false
                        isPhotoAnimatingOut = false
                        photoAnimatingOutIndex = nil

                        // Deselect old photo
                        resetTilt(index: oldIndex)
                        selectedPhotoIndex = nextIndex
                        isSwipingPhoto = false
                        swipePhotoScale = 1

                        // Show delete button after settle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if selectedPhotoIndex == nextIndex, deletingPhoto == nil {
                                    showDeleteButton = true
                                }
                            }
                        }
                    }
                }
        )
    }

    // MARK: - Photo Item (matches CameraPhotoItem with swipe support)
    @ViewBuilder
    private func swipeTestPhotoItem(photo: TestPhoto, index: Int, totalCount: Int) -> some View {
        let baseW: CGFloat = 46
        let baseH: CGFloat = 32
        let expandedW: CGFloat = 46 * 3.8
        let expandedH: CGFloat = 32 * 3.8
        let thumbBaseX: CGFloat = -(338 / 2 - 20 - 46 / 2)
        let thumbBaseY: CGFloat = -(235 / 2 - 18 - 32 / 2)
        let isSelected = selectedPhotoIndex == index
        let isAnimOut = photoAnimatingOutIndex == index
        let isThisSwiping = isSelected && isSwipingPhoto

        let photoW = showingExpandedPhotos ? expandedW : baseW
        let photoH = showingExpandedPhotos ? expandedH : baseH
        let selectedScale: CGFloat = (235 - 24) / expandedH
        let photoScale: CGFloat = {
            if isThisSwiping { return swipePhotoScale }
            return isSelected ? selectedScale : (showingExpandedPhotos ? 0.85 : 1.0)
        }()

        let finalOffsetX: CGFloat = {
            if isSelected {
                return photoSwipeOffset
            }
            if showingExpandedPhotos {
                let raw = CGFloat(photo.offsetX) * 22
                let maxX: CGFloat = (338 - expandedW) / 2 - 12
                return max(-maxX, min(maxX, raw))
            }
            return thumbBaseX + CGFloat(photo.offsetX)
        }()
        let finalOffsetY: CGFloat = {
            if isSelected { return 0 }
            if showingExpandedPhotos {
                let raw = CGFloat(photo.offsetY) * 12
                let maxY: CGFloat = (235 - expandedH) / 2 - 5
                return max(-maxY, min(maxY, raw))
            }
            return thumbBaseY + CGFloat(photo.offsetY)
        }()
        let finalRotation: CGFloat = {
            if isSelected { return 0 }
            if showingExpandedPhotos {
                let normX = max(-1, min(1, CGFloat(photo.offsetX) / 6))
                return normX * 12
            }
            return CGFloat(photo.rotation)
        }()

        let borderW: CGFloat = isSelected ? 2.0 / selectedScale : (showingExpandedPhotos ? 1.5 : 1.0)
        let borderOpacity: Double = isSelected ? 1.0 : (showingExpandedPhotos ? 0.6 : 0.8)
        let cr: CGFloat = isSelected ? 12 : (showingExpandedPhotos ? 5 * 3.8 : 5)

        let zIdx: Double = {
            if isAnimOut {
                return 0
            }
            return isSelected ? 100 : Double(index)
        }()

        let tiltX = tiltAngleX[index] ?? 0
        let tiltY = tiltAngleY[index] ?? 0
        let tiltScale: CGFloat = 1.0 + abs(tiltX) * 0.003
        let tiltShadow: CGFloat = abs(tiltX) * 0.5
        let tiltLiftY: CGFloat = -abs(tiltX) * 0.3

        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: photoW, height: photoH)
            .clipShape(RoundedRectangle(cornerRadius: cr))
            .overlay(
                RoundedRectangle(cornerRadius: cr)
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: borderW)
            )
            .shadow(color: .black.opacity(0.4), radius: tiltShadow, y: tiltShadow * 0.5)
            .scaleEffect(tiltScale)
            .offset(y: tiltLiftY)
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .rotationEffect(.degrees(finalRotation))
            .offset(x: finalOffsetX, y: finalOffsetY)
            .scaleEffect(photoScale)
            .zIndex(zIdx)
            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(Double(totalCount - 1 - index) * 0.06), value: showingExpandedPhotos)
            .animation(.spring(response: 0.4, dampingFraction: 0.82).delay(Double(totalCount - 1 - index) * 0.06), value: isSelected)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: photoSwipeOffset)
    }

    // MARK: - Smoky Dissolve Overlay
    private var swipeTestDissolveOverlay: some View {
        Group {
            if let delPhoto = deletingPhoto {
                let delTiltX = tiltAngleX[deletingIndex ?? -1] ?? 0
                let delTiltY = tiltAngleY[deletingIndex ?? -1] ?? 0
                let selectedScale: CGFloat = (235 - 24) / (32 * 3.8)
                let delTiltScale: CGFloat = 1.0 + abs(delTiltX) * 0.003
                let delTiltShadow: CGFloat = abs(delTiltX) * 0.5
                let delTiltLiftY: CGFloat = -abs(delTiltX) * 0.3
                Image(uiImage: delPhoto.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46 * 3.8, height: 32 * 3.8)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(1.0), lineWidth: 2.0 / selectedScale)
                    )
                    .shadow(color: .black.opacity(0.4), radius: delTiltShadow, y: delTiltShadow * 0.5)
                    .scaleEffect(delTiltScale)
                    .offset(y: delTiltLiftY)
                    .rotation3DEffect(.degrees(delTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                    .rotation3DEffect(.degrees(delTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .scaleEffect(selectedScale)
                    .blur(radius: deleteBlur)
                    .opacity(deleteOpacity)
                    .offset(y: deleteOffsetY)
                    .allowsHitTesting(false)
                    .zIndex(200)
            }
        }
    }

    // MARK: - TILT helpers — slower for smooth overlap with slide-out
    private func triggerTiltEffect(index: Int) {
        // Phase 1: gentle lift — slower response so it enlarges gradually
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            tiltAngleX[index] = -18
            tiltAngleY[index] = Double.random(in: -8...8)
        }
        // Phase 2: settle flat — longer response for a leisurely bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                self.tiltAngleX[index] = 0
                self.tiltAngleY[index] = 0
            }
        }
    }

    private func resetTilt(index: Int) {
        tiltAngleX[index] = 0
        tiltAngleY[index] = 0
    }

    // MARK: - Smoky Dissolve
    private func triggerSmokyDissolve(index: Int) {
        guard index < photos.count else { return }
        let targetID = photos[index].id
        deletingPhoto = photos[index]
        deletingIndex = index
        showDeleteButton = false

        withAnimation(.easeOut(duration: 0.85)) {
            deleteBlur = 20
            deleteOpacity = 0
            deleteOffsetY = 25
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                photos.removeAll { $0.id == targetID }
                var newTiltX: [Int: Double] = [:]
                var newTiltY: [Int: Double] = [:]
                for (k, v) in tiltAngleX where k < index { newTiltX[k] = v }
                for (k, v) in tiltAngleX where k > index { newTiltX[k - 1] = v }
                for (k, v) in tiltAngleY where k < index { newTiltY[k] = v }
                for (k, v) in tiltAngleY where k > index { newTiltY[k - 1] = v }
                tiltAngleX = newTiltX
                tiltAngleY = newTiltY
                showingExpandedPhotos = photos.count > 0
                let nextIdx = min(index, photos.count - 1)
                if nextIdx >= 0 {
                    selectedPhotoIndex = nextIdx
                    triggerTiltEffect(index: nextIdx)
                    showDeleteButton = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if selectedPhotoIndex == nextIdx {
                                showDeleteButton = true
                            }
                        }
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            deletingPhoto = nil
            deletingIndex = nil
            deleteBlur = 0
            deleteOpacity = 1.0
            deleteOffsetY = 0
        }
    }
}

// MARK: - Parking Recognition Test View

struct ParkingRecognitionTestView: View {
    @StateObject private var animationClock = AnimationClock()
    @StateObject private var photoStorage = PhotoStorage()

    // UI state
    @State private var showingExpanded = false
    @State private var selectedIndex: Int? = nil
    @State private var showDeleteButton = false
    @State private var isCapturePressed = false
    @State private var isCapturing = false

    // TILT animation state
    @State private var tiltAngleX: [Int: Double] = [:]
    @State private var tiltAngleY: [Int: Double] = [:]

    // Delete animation state
    @State private var deletingPhotoID: UUID? = nil
    @State private var deletingIndex: Int? = nil
    @State private var deletingImage: UIImage? = nil
    @State private var deleteBlur: CGFloat = 0
    @State private var deleteOpacity: Double = 1.0
    @State private var deleteOffsetY: CGFloat = 0

    // Capture animation
    @State private var animatingPhotoID: UUID? = nil
    @State private var animatingPhotoImage: UIImage? = nil
    @State private var animatingPhotoPhase: Int = 0
    @State private var animatingPhotoOffsetX: CGFloat = 0
    @State private var animatingPhotoOffsetY: CGFloat = 0

    // OCR Recognition state
    @State private var isRecognizing = false
    @State private var showFloorConfirm = false
    @State private var recognizedFloorToConfirm: Int? = nil
    @State private var recognizedFloorText: String? = nil
    @State private var hasConfirmedFloorThisSession = false

    // Debug panel
    @State private var showDebugPanel = false
    @State private var lastRecognizedInfo: ParkingRecognizedInfo? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("泊車辨識測試")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // Description labels
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("OCR 文字識別", systemImage: "text.viewfinder")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "46ADB8"))
                            Text("拍照後自動識別車位號、樓層、區域代碼")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                            Label("樓層確認彈窗", systemImage: "building.2")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "FF6B6B"))
                                .padding(.top, 4)
                            Text("識別出樓層時彈出確認視窗")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Camera section with recognition
                    cameraRecognitionSection
                        .padding(.bottom, 16)

                    // Status bar
                    HStack(spacing: 12) {
                        // Photo count
                        HStack(spacing: 6) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 12))
                            Text("\(photoStorage.photos.count)/3")
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.7))

                        // Recognition status
                        if isRecognizing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                                Text("識別中...")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        } else if let info = lastRecognizedInfo {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                Text("已識別")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        // Debug toggle
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showDebugPanel.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showDebugPanel ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                Text("詳情")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // Debug panel
                    if showDebugPanel {
                        debugPanel
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        // Clear all button
                        Button {
                            photoStorage.deleteAll()
                            lastRecognizedInfo = nil
                            hasConfirmedFloorThisSession = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                Text("清除照片")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: "D2251F").opacity(0.8))
                            )
                        }

                        // Re-recognize last photo
                        Button {
                            if let lastPhoto = photoStorage.photos.last, let img = lastPhoto.image {
                                isRecognizing = true
                                Task.detached {
                                    let info = await ParkingSpotRecognizer.recognize(from: img)
                                    await MainActor.run {
                                        self.photoStorage.updateRecognizedInfo(for: lastPhoto.id, info: info)
                                        self.lastRecognizedInfo = info
                                        self.isRecognizing = false
                                        if let floor = info.floorIndex, !self.hasConfirmedFloorThisSession {
                                            self.recognizedFloorToConfirm = floor
                                            self.recognizedFloorText = info.floorText
                                            self.showFloorConfirm = true
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                Text("重新識別")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: "46ADB8").opacity(0.8))
                            )
                        }
                        .disabled(photoStorage.photos.isEmpty || isRecognizing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .parkingPhotoCaptured)) { notification in
            if let image = notification.object as? UIImage {
                startCaptureAnimation(photo: image)
            }
        }
        // Floor confirmation overlay
        .overlay {
            if showFloorConfirm, let floor = recognizedFloorToConfirm {
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.18)) {
                                showFloorConfirm = false
                                hasConfirmedFloorThisSession = true
                            }
                        }

                    floorConfirmTestCard(floorIndex: floor, floorText: recognizedFloorText ?? "\(floor) 樓")
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 22)
                }
            }
        }
    }

    // MARK: - Camera Section with Recognition
    private var cameraRecognitionSection: some View {
        let camW: CGFloat = 338
        let camH: CGFloat = 235
        let camCR: CGFloat = 37
        return ZStack(alignment: .topLeading) {
            CameraPreviewView(isLandscape: false)
                .frame(width: camW, height: camH)
                .clipShape(RoundedRectangle(cornerRadius: camCR))
                .overlay(
                    RoundedRectangle(cornerRadius: camCR)
                        .stroke(Color.white.opacity(0.8), lineWidth: 4)
                )

            // Dim overlay
            let dimOpacity = showingExpanded ? (selectedIndex != nil ? 0.65 : 0.45) : 0
            Color.black.opacity(dimOpacity)
                .frame(width: camW, height: camH)
                .clipShape(RoundedRectangle(cornerRadius: camCR))
                .animation(.easeInOut(duration: 0.3), value: selectedIndex)
                .animation(.easeInOut(duration: 0.3), value: showingExpanded)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard showingExpanded else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        if let idx = selectedIndex {
                            resetTilt(index: idx)
                            selectedIndex = nil
                        } else {
                            showingExpanded = false
                            selectedIndex = nil
                        }
                        tiltAngleX = [:]
                        tiltAngleY = [:]
                    }
                }

            // Photo stack
            photoTestStack

            // Capture animation overlay
            captureTestAnimationOverlay

            // Camera button
            cameraTestCaptureButton

            // Delete button
            if let idx = selectedIndex, idx < photoStorage.photos.count,
               showDeleteButton, deletingPhotoID == nil {
                Button {
                    triggerSmokyDissolve(index: idx)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: .circle)
                        .glassEffect(.regular, in: .circle)
                }
                .position(x: 40, y: 34)
                .transition(.opacity)
            }

            // Thumbnail tap area
            if !showingExpanded {
                Color.clear
                    .frame(width: 80, height: 70)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showingExpanded = true
                            selectedIndex = nil
                        }
                    }
            }

            // Recognized info overlay
            if let idx = selectedIndex, idx < photoStorage.photos.count,
               showingExpanded {
                let photo = photoStorage.photos[idx]
                if let info = photo.recognizedInfo {
                    recognizedInfoTestOverlay(info: info)
                        .position(x: camW / 2, y: camH / 2 + 20)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            // Recognizing indicator
            if isRecognizing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                    Text("識別中...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                )
                .position(x: camW - 50, y: 24)
                .transition(.opacity)
            }
        }
        .frame(width: camW, height: camH)
    }

    // MARK: - Photo Stack
    private var photoTestStack: some View {
        let photos = photoStorage.photos
        let count = photos.count
        return ZStack {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                if photo.id != deletingPhotoID {
                    CameraPhotoItem(
                        photo: photo,
                        index: index,
                        totalCount: count,
                        isExpanded: showingExpanded,
                        isSelected: selectedIndex == index,
                        tiltX: tiltAngleX[index] ?? 0,
                        tiltY: tiltAngleY[index] ?? 0,
                        isLandscape: false
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            if showingExpanded {
                                let wasSelected = selectedIndex == index
                                if wasSelected {
                                    resetTilt(index: index)
                                    selectedIndex = nil
                                } else {
                                    if let oldIdx = selectedIndex {
                                        resetTilt(index: oldIdx)
                                    }
                                    selectedIndex = index
                                    triggerTiltEffect(index: index)
                                    showDeleteButton = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            if selectedIndex == index, deletingPhotoID == nil {
                                                showDeleteButton = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Smoky dissolve overlay
            cameraTestDissolveOverlay
        }
        .frame(width: 338, height: 235, alignment: .center)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard showingExpanded, photos.count > 1 else { return }
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        if let cur = selectedIndex {
                            resetTilt(index: cur)
                        }
                        if horizontal < 0 {
                            if let cur = selectedIndex {
                                selectedIndex = (cur + 1) % photos.count
                            } else {
                                selectedIndex = 0
                            }
                        } else {
                            if let cur = selectedIndex {
                                selectedIndex = (cur - 1 + photos.count) % photos.count
                            } else {
                                selectedIndex = photos.count - 1
                            }
                        }
                        if let newIdx = selectedIndex {
                            triggerTiltEffect(index: newIdx)
                            showDeleteButton = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if selectedIndex == newIdx, deletingPhotoID == nil {
                                        showDeleteButton = true
                                    }
                                }
                            }
                        }
                    }
                }
        )
    }

    // MARK: - Smoky Dissolve Overlay
    private var cameraTestDissolveOverlay: some View {
        Group {
            if deletingPhotoID != nil, let img = deletingImage {
                let expandedH: CGFloat = 32 * 3.8
                let selectedScale: CGFloat = (235 - 24) / expandedH
                let delTiltX = tiltAngleX[deletingIndex ?? -1] ?? 0
                let delTiltY = tiltAngleY[deletingIndex ?? -1] ?? 0
                let delTiltScale: CGFloat = 1.0 + abs(delTiltX) * 0.003
                let delTiltShadow: CGFloat = abs(delTiltX) * 0.5
                let delTiltLiftY: CGFloat = -abs(delTiltX) * 0.3
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46 * 3.8, height: expandedH)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(1.0), lineWidth: 2.0 / selectedScale)
                    )
                    .shadow(color: .black.opacity(0.4), radius: delTiltShadow, y: delTiltShadow * 0.5)
                    .scaleEffect(delTiltScale)
                    .offset(y: delTiltLiftY)
                    .rotation3DEffect(.degrees(delTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                    .rotation3DEffect(.degrees(delTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .scaleEffect(selectedScale)
                    .blur(radius: deleteBlur)
                    .opacity(deleteOpacity)
                    .offset(y: deleteOffsetY)
                    .allowsHitTesting(false)
                    .zIndex(200)
            }
        }
    }

    // MARK: - Capture Animation Overlay
    private var captureTestAnimationOverlay: some View {
        let camW: CGFloat = 338
        let camH: CGFloat = 235
        return Group {
            if animatingPhotoID != nil, let img = animatingPhotoImage {
                let isShrunk = animatingPhotoPhase == 1
                let cr: CGFloat = isShrunk ? 5 : 37
                let sc: CGFloat = isShrunk ? 46.0 / camW : 1.0
                let lw: CGFloat = isShrunk ? 1.0 / (46.0 / camW) : 4
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: camW, height: camH)
                    .clipShape(RoundedRectangle(cornerRadius: cr))
                    .overlay(
                        RoundedRectangle(cornerRadius: cr)
                            .stroke(Color.white.opacity(0.8), lineWidth: lw)
                    )
                    .scaleEffect(sc)
                    .offset(x: animatingPhotoOffsetX, y: animatingPhotoOffsetY)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
    }

    // MARK: - Camera Capture Button
    private var cameraTestCaptureButton: some View {
        Button(action: {
            guard !isCapturing else { return }
            isCapturing = true
            NotificationCenter.default.post(name: .captureParkingPhoto, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isCapturing = false
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .frame(width: 59, height: 148)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .tint(.clear)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let t = animationClock.elapsed * 0.3
                    ZStack {
                        Circle()
                            .fill(Color(hex: "3497FF").opacity(0.85))
                            .blur(radius: 16)
                            .frame(width: 100, height: 100)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.4 - 50,
                                    y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 50)
                        Circle()
                            .fill(Color(hex: "FFC46D").opacity(0.85))
                            .frame(width: 110, height: 110)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.35 - 55,
                                    y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 55)
                        Circle()
                            .fill(Color(hex: "FF825C").opacity(0.85))
                            .frame(width: 90, height: 90)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.38 - 45,
                                    y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.35 - 45)
                    }
                }
                .frame(width: 51, height: 140)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white, lineWidth: 1.6))
                Image(systemName: "camera.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isCapturePressed ? 0.88 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCapturePressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isCapturePressed = pressing
        }, perform: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
        .blur(radius: showingExpanded || photoStorage.photos.count >= 3 ? 12 : 0)
        .opacity(showingExpanded || photoStorage.photos.count >= 3 ? 0 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showingExpanded)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: photoStorage.photos.count)
    }

    // MARK: - Recognized Info Overlay
    private func recognizedInfoTestOverlay(info: ParkingRecognizedInfo) -> some View {
        let items = info.relevantItems
        let hasContent = !items.isEmpty || info.floorText != nil
        return Group {
            if hasContent {
                VStack(spacing: 4) {
                    ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            if Self.isFloorText(item) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 10))
                            } else if Self.isSpotNumberText(item) {
                                Image(systemName: "car.fill")
                                    .font(.system(size: 10))
                            } else {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 10))
                            }
                            Text(item)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.55))
                )
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
        }
    }

    private static func isFloorText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("b") || lower.hasPrefix("lg") || lower.hasPrefix("ug") ||
               lower.contains("樓") || lower.contains("層") || lower.contains("地下")
    }

    private static func isSpotNumberText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: "^\\d{1,5}$"),
           regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            return true
        }
        return false
    }

    // MARK: - Floor Confirmation Card (Test)
    private func floorConfirmTestCard(floorIndex: Int, floorText: String) -> some View {
        let tintColor = Color(hex: "46ADB8") ?? .teal
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("樓層識別")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("照片中偵測到樓層資訊")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.top, 2)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(tintColor)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(floorText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        FloorConventionBadge(onDark: true)
                    }
                    Text("樓層指數：\(floorIndex)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.06))
            )

            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeIn(duration: 0.18)) {
                        showFloorConfirm = false
                        hasConfirmedFloorThisSession = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("是，調整為「\(floorText)」")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.black)
                    .background(
                        Capsule()
                            .fill(Color.white)
                    )
                    .glassEffect(.regular, in: .capsule)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeIn(duration: 0.18)) {
                        showFloorConfirm = false
                        hasConfirmedFloorThisSession = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle")
                        Text("否，維持現狀")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .glassEffect(.regular, in: .capsule)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.black.opacity(0.58))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .clipShape(.rect(cornerRadius: 30))
        .borderBeam(
            size: .large,
            palette: .senshackDark,
            cornerRadius: 30,
            enableRotate: false,
            enablePulse: true
        )
    }

    // MARK: - Debug Panel
    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("識別結果詳情")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            if let info = lastRecognizedInfo {
                VStack(alignment: .leading, spacing: 8) {
                    debugRow(label: "相關項目", value: info.relevantItems.isEmpty ? "無" : info.relevantItems.joined(separator: ", "))
                    debugRow(label: "樓層", value: info.floorText ?? "未識別")
                    debugRow(label: "樓層指數", value: info.floorIndex != nil ? "\(info.floorIndex!)" : "N/A")

                    Divider()
                        .background(.white.opacity(0.2))

                    Text("OCR 原始文字")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    if info.rawTexts.isEmpty {
                        Text("（無）")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        ForEach(Array(info.rawTexts.enumerated()), id: \.offset) { idx, text in
                            HStack(spacing: 8) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(width: 20, alignment: .trailing)
                                Text(text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }

                    if let time = info.recognizedAt {
                        debugRow(label: "識別時間", value: formatDate(time))
                    }
                }
            } else {
                Text("尚未進行識別")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func debugRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    // MARK: - Capture Animation
    private func startCaptureAnimation(photo: UIImage) {
        guard let saved = photoStorage.savePhoto(photo) else { return }
        let tempID = saved.id
        animatingPhotoID = tempID
        animatingPhotoImage = photo
        animatingPhotoPhase = 0
        let thumbOX: CGFloat = -(338.0 / 2 - 20 - 46.0 / 2) + CGFloat(saved.offsetX)
        let thumbOY: CGFloat = -(235.0 / 2 - 18 - 32.0 / 2) + CGFloat(saved.offsetY)
        animatingPhotoOffsetX = 0
        animatingPhotoOffsetY = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.45)) {
                animatingPhotoPhase = 1
                animatingPhotoOffsetX = thumbOX
                animatingPhotoOffsetY = thumbOY
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            animatingPhotoID = nil
            animatingPhotoImage = nil
            animatingPhotoPhase = 0
            animatingPhotoOffsetX = 0
            animatingPhotoOffsetY = 0
        }

        // Trigger OCR
        isRecognizing = true
        Task.detached {
            let info = await ParkingSpotRecognizer.recognize(from: photo)
            await MainActor.run {
                self.photoStorage.updateRecognizedInfo(for: tempID, info: info)
                self.lastRecognizedInfo = info
                self.isRecognizing = false
                if let floor = info.floorIndex, !self.hasConfirmedFloorThisSession {
                    self.recognizedFloorToConfirm = floor
                    self.recognizedFloorText = info.floorText
                    self.showFloorConfirm = true
                }
            }
        }
    }

    // MARK: - TILT Effect
    private func triggerTiltEffect(index: Int) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.4)) {
            tiltAngleX[index] = -18
            tiltAngleY[index] = Double.random(in: -8...8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                self.tiltAngleX[index] = 0
                self.tiltAngleY[index] = 0
            }
        }
    }

    private func resetTilt(index: Int) {
        tiltAngleX[index] = 0
        tiltAngleY[index] = 0
    }

    // MARK: - Smoky Dissolve
    private func triggerSmokyDissolve(index: Int) {
        guard index < photoStorage.photos.count else { return }
        let photo = photoStorage.photos[index]
        let targetID = photo.id
        deletingImage = photo.image
        deletingPhotoID = targetID
        deletingIndex = index
        showDeleteButton = false

        withAnimation(.easeOut(duration: 0.85)) {
            deleteBlur = 20
            deleteOpacity = 0
            deleteOffsetY = 25
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                photoStorage.deletePhoto(photo)
                let idx = index
                var newTiltAngleX: [Int: Double] = [:]
                var newTiltAngleY: [Int: Double] = [:]
                for (k, v) in tiltAngleX where k < idx {
                    newTiltAngleX[k] = v
                }
                for (k, v) in tiltAngleX where k > idx {
                    newTiltAngleX[k - 1] = v
                }
                for (k, v) in tiltAngleY where k < idx {
                    newTiltAngleY[k] = v
                }
                for (k, v) in tiltAngleY where k > idx {
                    newTiltAngleY[k - 1] = v
                }
                tiltAngleX = newTiltAngleX
                tiltAngleY = newTiltAngleY
                if photoStorage.photos.isEmpty {
                    selectedIndex = nil
                    showingExpanded = false
                } else {
                    selectedIndex = min(idx, photoStorage.photos.count - 1)
                }
            }
            if !photoStorage.photos.isEmpty {
                let newIdx = min(index, photoStorage.photos.count - 1)
                triggerTiltEffect(index: newIdx)
                showDeleteButton = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if selectedIndex != nil, deletingPhotoID == nil {
                            showDeleteButton = true
                        }
                    }
                }
            }
            deletingPhotoID = nil
            deletingIndex = nil
            deletingImage = nil
            deleteBlur = 0
            deleteOpacity = 1.0
            deleteOffsetY = 0
        }
    }
}

// MARK: - Parking LLM Recognition Test View

struct ParkingLLMRecognitionTestView: View {
    @StateObject private var animationClock = AnimationClock()
    @StateObject private var photoStorage = PhotoStorage()

    // UI state
    @State private var showingExpanded = false
    @State private var selectedIndex: Int? = nil
    @State private var showDeleteButton = false
    @State private var isCapturePressed = false
    @State private var isCapturing = false

    // TILT animation state
    @State private var tiltAngleX: [Int: Double] = [:]
    @State private var tiltAngleY: [Int: Double] = [:]

    // Delete animation state
    @State private var deletingPhotoID: UUID? = nil
    @State private var deletingIndex: Int? = nil
    @State private var deletingImage: UIImage? = nil
    @State private var deleteBlur: CGFloat = 0
    @State private var deleteOpacity: Double = 1.0
    @State private var deleteOffsetY: CGFloat = 0

    // Capture animation
    @State private var animatingPhotoID: UUID? = nil
    @State private var animatingPhotoImage: UIImage? = nil
    @State private var animatingPhotoPhase: Int = 0
    @State private var animatingPhotoOffsetX: CGFloat = 0
    @State private var animatingPhotoOffsetY: CGFloat = 0

    // LLM Recognition state
    @State private var isRecognizing = false
    @State private var llmResult: String? = nil
    @State private var llmError: String? = nil
    @State private var recognizedFloorText: String? = nil
    @State private var recognizedFloorIndex: Int? = nil
    @State private var showFloorConfirm = false
    @State private var hasConfirmedFloorThisSession = false
    @State private var modelStatus: String = "快捷指令模式"
    @State private var showActionPrompt = false

    // Shortcut config
    @State private var shortcutName: String = UserDefaults.standard.string(forKey: "llm_shortcut_name") ?? "泊車辨識"
    @State private var showShortcutSettings = false
    @State private var pollTimer: Timer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("泊車辨識測試 (LLM)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // Description + Shortcut Settings
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("快捷指令 + Apple Intelligence", systemImage: "shortcuts")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(hex: "BCBA1E"))
                                Text("傳圖片給快捷指令，用 Cloud 模型辨識")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 8, height: 8)
                                    Text("快捷指令：\(shortcutName)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            Spacer()
                            Button {
                                showShortcutSettings.toggle()
                            } label: {
                                Image(systemName: "gear")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }

                        if showShortcutSettings {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("快捷指令名稱")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.5))
                                    TextField("泊車辨識", text: $shortcutName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13))
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("快捷指令設定步驟：")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.5))
                                    Group {
                                        Text("1. 不要選「接收輸入」，直接開始")
                                        Text("2. 「從剪貼簿取得圖片」")
                                        Text("3. 「製作圖像描述」→ 選 Cloud 模型 + 提示詞")
                                        Text("4. 「拷貝至剪貼簿」→ 選「圖像描述」結果")
                                        Text("5. 「結束並返回」→ 選「圖像描述」結果")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                                    Text("App 會把圖片放剪貼簿 → 快捷指令讀取 → 結果回傳剪貼簿")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.35))
                                    Text("💡 拍照後按 Action Button 執行快捷指令")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color(hex: "BCBA1E"))
                                    Text("💡 或講「Hey Siri，泊車辨識」")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(hex: "BCBA1E").opacity(0.7))
                                }
                                Button {
                                    generateAndShareShortcut()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("一鍵生成快捷指令")
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(Color(hex: "BCBA1E") ?? .yellow))
                                }

                                Button {
                                    UserDefaults.standard.set(shortcutName, forKey: "llm_shortcut_name")
                                    showShortcutSettings = false
                                } label: {
                                    Text("儲存")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(.white))
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Camera section
                    cameraLLMSection
                        .padding(.bottom, 16)

                    // Status bar
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 12))
                            Text("\(photoStorage.photos.count)/3")
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.7))

                        if isRecognizing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                                Text("LLM 識別中...")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        } else if llmResult != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                Text("已完成")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        // Clear button
                        Button {
                            photoStorage.deleteAll()
                            llmResult = nil
                            llmError = nil
                            recognizedFloorText = nil
                            recognizedFloorIndex = nil
                            hasConfirmedFloorThisSession = false
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("清除")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // LLM Result panel
                    llmResultPanel
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            prepareModel()
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .parkingPhotoCaptured)) { notification in
            if let image = notification.object as? UIImage {
                startCaptureAnimation(photo: image)
                recognizeWithLLM(image: image)
            }
        }
        // Action Button prompt
        .modifier(VLMActionPrompt(isPresented: $showActionPrompt, shortcutName: shortcutName,
            onReady: { startPollingAfterAction() }, onCancel: {}))
        // Floor confirmation overlay
        .overlay {
            if showFloorConfirm, let floor = recognizedFloorIndex {
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.18)) {
                                showFloorConfirm = false
                                hasConfirmedFloorThisSession = true
                            }
                        }

                    floorConfirmLLMCard(floorIndex: floor, floorText: recognizedFloorText ?? "\(floor) 樓")
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 22)
                }
            }
        }
        // Copied toast
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("快捷指令描述已複製，貼給 Siri 即可生成")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                )
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCopiedToast)
            }
        }
    }

    // MARK: - Generate Shortcut Helper
    @State private var showCopiedToast = false

    private func generateAndShareShortcut() {
        let description = """
        請幫我建立一個快捷指令，名稱叫「泊車辨識」。步驟如下：

        第一步，「從剪貼簿取得圖片」。

        第二步，「製作圖像描述」。模型選擇「Cloud」。提示詞用：「请识别这张照片中的车位号、区域号和楼层。一般区域号会出现在柱子且格式不会与楼层冲突，部分场景可能以颜色代替，如为颜色请输出颜色。如地面喷涂也有类似区域号，以柱子上的为准。重点区分：电梯厅墙面发光数字、大堂门口数字，属于楼宇座数/电梯出口编号，不是停车场楼层，绝对不能当成车库楼层识别。楼层若为地下一般会以B为开头，请留意部分会以B开头加数字作为区域号，请留意是否有区域字样提示，一般不会与区域号冲突或重复，不要推断楼层。如未识别出请与对应项显示"-"，最后给出识别逻辑。」

        第三步，「拷贝至剪贴簿」，內容選「图像描述的結果」。

        第四步，「結束並返回」，選「图像描述的結果」。
        """

        // Copy description to clipboard
        UIPasteboard.general.string = description

        // Open Shortcuts app
        if let url = URL(string: "shortcuts://create-shortcut") {
            UIApplication.shared.open(url)
        }

        // Show toast
        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showCopiedToast = false
        }
    }

    // MARK: - Prepare Model
    private func prepareModel() {
        modelStatus = "快捷指令：\(shortcutName)"
    }

    // MARK: - LLM Recognition via Shortcut (clipboard-based)
    private func recognizeWithLLM(image: UIImage) {
        // Copy image to clipboard
        UIPasteboard.general.image = image

        // Reset state
        llmResult = nil
        llmError = nil
        recognizedFloorText = nil
        recognizedFloorIndex = nil

        // Show prompt to press Action Button
        showActionPrompt = true
    }

    // MARK: - Start Polling (called when user taps "已準備好")
    private func startPollingAfterAction() {
        isRecognizing = true
        showActionPrompt = false
        startPollingClipboardForResult()
    }

    // MARK: - Poll Clipboard for Shortcut Result
    private func startPollingClipboardForResult() {
        pollTimer?.invalidate()
        var attempts = 0
        let maxAttempts = 120 // 2 minutes max (1s interval)
        let initialChangeCount = UIPasteboard.general.changeCount

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            attempts += 1

            let currentChangeCount = UIPasteboard.general.changeCount
            if currentChangeCount != initialChangeCount,
               let text = UIPasteboard.general.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                timer.invalidate()
                self.pollTimer = nil

                DispatchQueue.main.async {
                    self.llmResult = text
                    self.isRecognizing = false
                    self.parseFloorFromLLMResponse(text)
                }
            } else if attempts >= maxAttempts {
                timer.invalidate()
                self.pollTimer = nil

                DispatchQueue.main.async {
                    if self.isRecognizing {
                        self.llmError = "等待超時（2分鐘）。請確認快捷指令「\(self.shortcutName)」已正確設定。"
                        self.isRecognizing = false
                    }
                }
            }
        }
    }

    // MARK: - Parse Floor from LLM Response
    private func parseFloorFromLLMResponse(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Look for "樓層：B2" or "樓層: -2樓"
            if trimmed.contains("樓層") {
                let components = trimmed.components(separatedBy: "：")
                let floorStr = components.count > 1 ? components.last?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                if let floorStr = floorStr, !floorStr.isEmpty {
                    recognizedFloorText = floorStr
                    // Try to parse floor index
                    if let index = Self.parseFloorIndex(floorStr) {
                        recognizedFloorIndex = index
                        if !hasConfirmedFloorThisSession {
                            showFloorConfirm = true
                        }
                    }
                }
            }
        }
    }

    private static func parseFloorIndex(_ text: String) -> Int? {
        // 統一交俾 ParkingFloorStore：牌面樓層文字按當前樓層慣例（香港/內地）換算成內部指數
        ParkingFloorStore.parseFloorIndex(text)
    }

    // MARK: - Camera Section
    private var cameraLLMSection: some View {
        let camW: CGFloat = 338
        let camH: CGFloat = 235
        let camCR: CGFloat = 37
        return ZStack(alignment: .topLeading) {
            CameraPreviewView(isLandscape: false)
                .frame(width: camW, height: camH)
                .clipShape(RoundedRectangle(cornerRadius: camCR))
                .overlay(
                    RoundedRectangle(cornerRadius: camCR)
                        .stroke(Color.white.opacity(0.8), lineWidth: 4)
                )

            // Dim overlay
            let dimOpacity = showingExpanded ? (selectedIndex != nil ? 0.65 : 0.45) : 0
            Color.black.opacity(dimOpacity)
                .frame(width: camW, height: camH)
                .clipShape(RoundedRectangle(cornerRadius: camCR))
                .animation(.easeInOut(duration: 0.3), value: selectedIndex)
                .animation(.easeInOut(duration: 0.3), value: showingExpanded)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard showingExpanded else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        if let idx = selectedIndex {
                            resetTilt(index: idx)
                            selectedIndex = nil
                        } else {
                            showingExpanded = false
                            selectedIndex = nil
                        }
                        tiltAngleX = [:]
                        tiltAngleY = [:]
                    }
                }

            // Photo stack
            photoLLMStack

            // Capture animation overlay
            captureLLMAnimationOverlay

            // Camera button
            cameraLLMCaptureButton

            // Delete button
            if let idx = selectedIndex, idx < photoStorage.photos.count,
               showDeleteButton, deletingPhotoID == nil {
                Button {
                    triggerSmokyDissolve(index: idx)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: .circle)
                        .glassEffect(.regular, in: .circle)
                }
                .position(x: 40, y: 34)
                .transition(.opacity)
            }

            // Thumbnail tap area
            if !showingExpanded {
                Color.clear
                    .frame(width: 80, height: 70)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showingExpanded = true
                            selectedIndex = nil
                        }
                    }
            }

            // Recognizing indicator
            if isRecognizing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                    Text("LLM 處理中...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                )
                .position(x: camW - 60, y: 24)
                .transition(.opacity)
            }
        }
        .frame(width: camW, height: camH)
    }

    // MARK: - Photo Stack
    private var photoLLMStack: some View {
        let photos = photoStorage.photos
        let count = photos.count
        return ZStack {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                if photo.id != deletingPhotoID {
                    CameraPhotoItem(
                        photo: photo,
                        index: index,
                        totalCount: count,
                        isExpanded: showingExpanded,
                        isSelected: selectedIndex == index,
                        tiltX: tiltAngleX[index] ?? 0,
                        tiltY: tiltAngleY[index] ?? 0,
                        isLandscape: false
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            if showingExpanded {
                                let wasSelected = selectedIndex == index
                                if wasSelected {
                                    resetTilt(index: index)
                                    selectedIndex = nil
                                } else {
                                    if let oldIdx = selectedIndex {
                                        resetTilt(index: oldIdx)
                                    }
                                    selectedIndex = index
                                    triggerTiltEffect(index: index)
                                    showDeleteButton = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            if selectedIndex == index, deletingPhotoID == nil {
                                                showDeleteButton = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            cameraLLMDissolveOverlay
        }
        .frame(width: 338, height: 235, alignment: .center)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard showingExpanded, photos.count > 1 else { return }
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        if let cur = selectedIndex {
                            resetTilt(index: cur)
                        }
                        if horizontal < 0 {
                            if let cur = selectedIndex {
                                selectedIndex = (cur + 1) % photos.count
                            } else {
                                selectedIndex = 0
                            }
                        } else {
                            if let cur = selectedIndex {
                                selectedIndex = (cur - 1 + photos.count) % photos.count
                            } else {
                                selectedIndex = photos.count - 1
                            }
                        }
                        if let newIdx = selectedIndex {
                            triggerTiltEffect(index: newIdx)
                            showDeleteButton = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if selectedIndex == newIdx, deletingPhotoID == nil {
                                        showDeleteButton = true
                                    }
                                }
                            }
                        }
                    }
                }
        )
    }

    // MARK: - Dissolve Overlay
    private var cameraLLMDissolveOverlay: some View {
        Group {
            if deletingPhotoID != nil, let img = deletingImage {
                let expandedH: CGFloat = 32 * 3.8
                let selectedScale: CGFloat = (235 - 24) / expandedH
                let delTiltX = tiltAngleX[deletingIndex ?? -1] ?? 0
                let delTiltY = tiltAngleY[deletingIndex ?? -1] ?? 0
                let delTiltScale: CGFloat = 1.0 + abs(delTiltX) * 0.003
                let delTiltShadow: CGFloat = abs(delTiltX) * 0.5
                let delTiltLiftY: CGFloat = -abs(delTiltX) * 0.3
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46 * 3.8, height: expandedH)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(1.0), lineWidth: 2.0 / selectedScale)
                    )
                    .shadow(color: .black.opacity(0.4), radius: delTiltShadow, y: delTiltShadow * 0.5)
                    .scaleEffect(delTiltScale)
                    .offset(y: delTiltLiftY)
                    .rotation3DEffect(.degrees(delTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                    .rotation3DEffect(.degrees(delTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .scaleEffect(selectedScale)
                    .blur(radius: deleteBlur)
                    .opacity(deleteOpacity)
                    .offset(y: deleteOffsetY)
                    .allowsHitTesting(false)
                    .zIndex(200)
            }
        }
    }

    // MARK: - Capture Animation Overlay
    private var captureLLMAnimationOverlay: some View {
        let camW: CGFloat = 338
        let camH: CGFloat = 235
        return Group {
            if animatingPhotoID != nil, let img = animatingPhotoImage {
                let isShrunk = animatingPhotoPhase == 1
                let cr: CGFloat = isShrunk ? 5 : 37
                let sc: CGFloat = isShrunk ? 46.0 / camW : 1.0
                let lw: CGFloat = isShrunk ? 1.0 / (46.0 / camW) : 4
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: camW, height: camH)
                    .clipShape(RoundedRectangle(cornerRadius: cr))
                    .overlay(
                        RoundedRectangle(cornerRadius: cr)
                            .stroke(Color.white.opacity(0.8), lineWidth: lw)
                    )
                    .scaleEffect(sc)
                    .offset(x: animatingPhotoOffsetX, y: animatingPhotoOffsetY)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
    }

    // MARK: - Camera Capture Button
    private var cameraLLMCaptureButton: some View {
        Button(action: {
            guard !isCapturing else { return }
            isCapturing = true
            NotificationCenter.default.post(name: .captureParkingPhoto, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isCapturing = false
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .frame(width: 59, height: 148)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .tint(.clear)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let t = animationClock.elapsed * 0.3
                    ZStack {
                        Circle()
                            .fill(Color(hex: "BCBA1E").opacity(0.85))
                            .blur(radius: 16)
                            .frame(width: 100, height: 100)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.4 - 50,
                                    y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 50)
                        Circle()
                            .fill(Color(hex: "9B59B6").opacity(0.85))
                            .frame(width: 110, height: 110)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.35 - 55,
                                    y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 55)
                        Circle()
                            .fill(Color(hex: "3498DB").opacity(0.85))
                            .frame(width: 90, height: 90)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.38 - 45,
                                    y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.35 - 45)
                    }
                }
                .frame(width: 51, height: 140)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white, lineWidth: 1.6))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isCapturePressed ? 0.88 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCapturePressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isCapturePressed = pressing
        }, perform: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
        .blur(radius: showingExpanded || photoStorage.photos.count >= 3 ? 12 : 0)
        .opacity(showingExpanded || photoStorage.photos.count >= 3 ? 0 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showingExpanded)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: photoStorage.photos.count)
    }

    // MARK: - LLM Result Panel
    private var llmResultPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LLM 識別結果")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if let floor = recognizedFloorText {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 11))
                        Text("樓層：\(floor)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "46ADB8"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(hex: "46ADB8").opacity(0.15))
                    )
                }
            }

            if isRecognizing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                    Text("正在使用 Apple Intelligence 識別...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else if let error = llmError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("錯誤")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else if let result = llmResult {
                ScrollView {
                    Text(result)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 300)
            } else {
                Text("拍照後自動使用 LLM 識別")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Floor Confirmation Card (LLM)
    private func floorConfirmLLMCard(floorIndex: Int, floorText: String) -> some View {
        let tintColor = Color(hex: "BCBA1E") ?? .yellow
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("樓層識別")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("3B 模型分析偵測到樓層資訊")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.top, 2)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(tintColor)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(floorText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        FloorConventionBadge(onDark: true)
                    }
                    Text("樓層指數：\(floorIndex)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.06))
            )

            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeIn(duration: 0.18)) {
                        showFloorConfirm = false
                        hasConfirmedFloorThisSession = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("是，調整為「\(floorText)」")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.black)
                    .background(
                        Capsule()
                            .fill(Color.white)
                    )
                    .glassEffect(.regular, in: .capsule)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeIn(duration: 0.18)) {
                        showFloorConfirm = false
                        hasConfirmedFloorThisSession = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle")
                        Text("否，維持現狀")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .glassEffect(.regular, in: .capsule)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.black.opacity(0.58))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .clipShape(.rect(cornerRadius: 30))
        .borderBeam(
            size: .large,
            palette: .senshackDark,
            cornerRadius: 30,
            enableRotate: false,
            enablePulse: true
        )
    }

    // MARK: - Capture Animation
    private func startCaptureAnimation(photo: UIImage) {
        guard let saved = photoStorage.savePhoto(photo) else { return }
        let tempID = saved.id
        animatingPhotoID = tempID
        animatingPhotoImage = photo
        animatingPhotoPhase = 0
        let thumbOX: CGFloat = -(338.0 / 2 - 20 - 46.0 / 2) + CGFloat(saved.offsetX)
        let thumbOY: CGFloat = -(235.0 / 2 - 18 - 32.0 / 2) + CGFloat(saved.offsetY)
        animatingPhotoOffsetX = 0
        animatingPhotoOffsetY = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.45)) {
                animatingPhotoPhase = 1
                animatingPhotoOffsetX = thumbOX
                animatingPhotoOffsetY = thumbOY
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            animatingPhotoID = nil
            animatingPhotoImage = nil
            animatingPhotoPhase = 0
            animatingPhotoOffsetX = 0
            animatingPhotoOffsetY = 0
        }
    }

    // MARK: - TILT Effect
    private func triggerTiltEffect(index: Int) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.4)) {
            tiltAngleX[index] = -18
            tiltAngleY[index] = Double.random(in: -8...8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                self.tiltAngleX[index] = 0
                self.tiltAngleY[index] = 0
            }
        }
    }

    private func resetTilt(index: Int) {
        tiltAngleX[index] = 0
        tiltAngleY[index] = 0
    }

    // MARK: - Smoky Dissolve
    private func triggerSmokyDissolve(index: Int) {
        guard index < photoStorage.photos.count else { return }
        let photo = photoStorage.photos[index]
        let targetID = photo.id
        deletingImage = photo.image
        deletingPhotoID = targetID
        deletingIndex = index
        showDeleteButton = false

        withAnimation(.easeOut(duration: 0.85)) {
            deleteBlur = 20
            deleteOpacity = 0
            deleteOffsetY = 25
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                photoStorage.deletePhoto(photo)
                let idx = index
                var newTiltAngleX: [Int: Double] = [:]
                var newTiltAngleY: [Int: Double] = [:]
                for (k, v) in tiltAngleX where k < idx {
                    newTiltAngleX[k] = v
                }
                for (k, v) in tiltAngleX where k > idx {
                    newTiltAngleX[k - 1] = v
                }
                for (k, v) in tiltAngleY where k < idx {
                    newTiltAngleY[k] = v
                }
                for (k, v) in tiltAngleY where k > idx {
                    newTiltAngleY[k - 1] = v
                }
                tiltAngleX = newTiltAngleX
                tiltAngleY = newTiltAngleY
                if photoStorage.photos.isEmpty {
                    selectedIndex = nil
                    showingExpanded = false
                } else {
                    selectedIndex = min(idx, photoStorage.photos.count - 1)
                }
            }
            if !photoStorage.photos.isEmpty {
                let newIdx = min(index, photoStorage.photos.count - 1)
                triggerTiltEffect(index: newIdx)
                showDeleteButton = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if selectedIndex != nil, deletingPhotoID == nil {
                            showDeleteButton = true
                        }
                    }
                }
            }
            deletingPhotoID = nil
            deletingIndex = nil
            deletingImage = nil
            deleteBlur = 0
            deleteOpacity = 1.0
            deleteOffsetY = 0
        }
    }
}


// MARK: - Kalman Filter Test View
struct KalmanFilterTestView: View {
    @State private var simulatedSpeed: Double = 0
    @State private var defaultDisplaySpeed: Double = 0
    @State private var rollingDisplaySpeed: Double = 0
    @State private var kalmanDisplaySpeed: Double = 0
    @State private var rollingTargetSpeed: Double = 0
    @State private var kalmanFilter = KalmanFilter(processNoise: 0.5, measurementNoise: 0.3)
    @State private var isAnimating = false
    @State private var gpsTimer: Timer?
    @State private var displayTimer: Timer?
    @State private var speedHistory: [(default: Double, rolling: Double, kalman: Double)] = []
    @State private var targetSpeed: Double = 0
    @State private var gpsUpdateCount: Int = 0

    // Simulated "GPS noise" - random jitter
    private func addNoise(_ value: Double) -> Double {
        let noise = Double.random(in: -3...3)
        return max(0, value + noise)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Title
                Text("卡爾曼濾波對比測試")
                    .font(.title2.bold())

                // Speed comparison - 3 columns
                HStack(spacing: 20) {
                    // Default (raw) - jumps
                    VStack(spacing: 6) {
                        Text("默認")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("\(Int(defaultDisplaySpeed))")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(.red)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.05), value: Int(defaultDisplaySpeed))
                        Text("km/h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("直接跳")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }

                    // Default + Rolling - smooth rolling
                    VStack(spacing: 6) {
                        Text("默認+滾動")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("\(Int(rollingDisplaySpeed))")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(.blue)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.05), value: Int(rollingDisplaySpeed))
                        Text("km/h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("平滑滾動")
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.7))
                    }

                    // Kalman - smoothed
                    VStack(spacing: 6) {
                        Text("卡爾曼")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("\(Int(kalmanDisplaySpeed))")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.05), value: Int(kalmanDisplaySpeed))
                        Text("km/h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("預測修正")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
                .padding(.vertical)

                // Target speed indicator
                VStack(spacing: 4) {
                    Text("目標時速")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(targetSpeed)) km/h")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                }

                // GPS update counter
                Text("GPS 更新次數: \(gpsUpdateCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Control buttons
                VStack(spacing: 12) {
                    Text("模擬場景")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button("靜止 → 30") {
                            startSimulation(target: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        Button("靜止 → 60") {
                            startSimulation(target: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)

                        Button("靜止 → 100") {
                            startSimulation(target: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    HStack(spacing: 12) {
                        Button("30 → 0") {
                            startSimulation(target: 0)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button("60 → 30") {
                            startSimulation(target: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)

                        Button("重置") {
                            resetSimulation()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()

                // History chart
                if !speedHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("更新歷史")
                            .font(.headline)

                        // Legend
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text("默認").font(.caption2)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(.blue).frame(width: 8, height: 8)
                                Text("默認+滾動").font(.caption2)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Text("卡爾曼").font(.caption2)
                            }
                        }

                        // History list
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 2) {
                                ForEach(speedHistory.indices, id: \.self) { index in
                                    let entry = speedHistory[index]
                                    VStack(spacing: 1) {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(.red.opacity(0.7))
                                            .frame(width: 3, height: CGFloat(entry.default) * 1.2)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(.blue.opacity(0.7))
                                            .frame(width: 3, height: CGFloat(entry.rolling) * 1.2)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(.green.opacity(0.7))
                                            .frame(width: 3, height: CGFloat(entry.kalman) * 1.2)
                                    }
                                }
                            }
                            .frame(height: 130)
                        }

                        // Stats
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("默認跳動")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "±%.1f", calculateVariance(speedHistory.map { $0.default })))
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            }
                            VStack(alignment: .leading) {
                                Text("滾動跳動")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "±%.1f", calculateVariance(speedHistory.map { $0.rolling })))
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading) {
                                Text("卡爾曼跳動")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "±%.1f", calculateVariance(speedHistory.map { $0.kalman })))
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // Explanation
                VStack(alignment: .leading, spacing: 6) {
                    Text("三種模式對比")
                        .font(.headline)
                    Text("• 默認：GPS 每秒更新，數字直接跳到新值")
                    Text("• 默認+滾動：GPS 每秒更新，數字平滑滾動過去")
                    Text("• 卡爾曼：GPS 每秒更新，預測+修正，數字平滑滾動")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("卡爾曼濾波測試")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startSimulation(target: Double) {
        targetSpeed = target
        isAnimating = true
        speedHistory = []
        kalmanFilter.reset()
        gpsUpdateCount = 0

        // GPS timer: updates every 1 second (realistic GPS rate)
        var gpsStep = 0
        let totalSteps = 10
        let startSpeed = simulatedSpeed

        gpsTimer?.invalidate()
        gpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            gpsStep += 1
            gpsUpdateCount = gpsStep
            if gpsStep > totalSteps {
                timer.invalidate()
                isAnimating = false
                displayTimer?.invalidate()
                return
            }

            // Linear interpolation with noise (simulates GPS update)
            let progress = Double(gpsStep) / Double(totalSteps)
            let rawTarget = startSpeed + (target - startSpeed) * progress
            let noisySpeed = addNoise(rawTarget)

            simulatedSpeed = noisySpeed

            // Default: jump directly to new value
            defaultDisplaySpeed = noisySpeed

            // Rolling: set target for smooth rolling
            rollingTargetSpeed = noisySpeed

            // Kalman: update filter (it will predict between updates)
            _ = kalmanFilter.update(measurement: noisySpeed)

            speedHistory.append((default: defaultDisplaySpeed, rolling: rollingTargetSpeed, kalman: kalmanFilter.predictedPosition))
        }

        // Display timer: updates 20 times per second for smooth animation
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Rolling: smoothly interpolate toward GPS target
            let rollingSmoothingFactor = 0.3
            rollingDisplaySpeed += (rollingTargetSpeed - rollingDisplaySpeed) * rollingSmoothingFactor

            // Kalman: smoothly interpolate toward prediction (ensures first jump is also smooth)
            let kalmanTarget = kalmanFilter.predict(at: Date())
            let kalmanSmoothingFactor = 0.3
            kalmanDisplaySpeed += (kalmanTarget - kalmanDisplaySpeed) * kalmanSmoothingFactor
        }
    }

    private func resetSimulation() {
        gpsTimer?.invalidate()
        displayTimer?.invalidate()
        isAnimating = false
        simulatedSpeed = 0
        defaultDisplaySpeed = 0
        rollingDisplaySpeed = 0
        kalmanDisplaySpeed = 0
        rollingTargetSpeed = 0
        targetSpeed = 0
        speedHistory = []
        kalmanFilter.reset()
        gpsUpdateCount = 0
    }

    private func calculateVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }
}

// MARK: - 嵌入曲線內容

struct InlineCurveContent: View {
    let history: [CGFloat]
    var horizontalPositions: [CGFloat]? = nil
    let w: CGFloat
    let h: CGFloat
    let accentColor: Color
    let carIconName: String
    var floorHeights: [(floor: Int, height: CGFloat)] = []
    var referenceFloor: Int = 0

    /// 左側樓層標籤寬度
    private let labelWidth: CGFloat = 28
    /// 右邊車 icon 空間
    private let carPadding: CGFloat = 22
    /// 基礎點距
    private let baseSpacing: CGFloat = 4
    /// 一層樓高度
    private let oneFloorMeters: CGFloat = 3.0

    /// 曲線可用寬度
    private var curveAreaWidth: CGFloat { w - labelWidth - carPadding }

    /// 壓縮 + 降採樣後嘅點
    private func compressedPoints() -> [CGFloat] {
        let count = history.count
        guard count > 1 else { return history }
        let needed = CGFloat(count - 1) * baseSpacing
        if needed <= curveAreaWidth { return history }
        let spacing = curveAreaWidth / CGFloat(count - 1)
        if spacing >= 1.0 { return history }
        let target = Int(curveAreaWidth)
        let step = max(1, count / target)
        var pts: [CGFloat] = []
        for i in stride(from: 0, to: count - 1, by: step) { pts.append(history[i]) }
        if pts.last != history.last { pts.append(history.last!) }
        return pts
    }

    private func plottedPoints() -> [(alt: CGFloat, x: CGFloat)] {
        if let positions = horizontalPositions, positions.count == history.count, let end = positions.last {
            let origin = max(0, end - curveAreaWidth)
            let firstVisible = max(0, (positions.firstIndex(where: { $0 >= origin }) ?? 0) - 1)
            return (firstVisible..<history.count).map { (history[$0], positions[$0] - origin) }
        }
        let points = compressedPoints()
        let count = points.count
        let usedWidth = min(CGFloat(max(0, count - 1)) * baseSpacing, curveAreaWidth)
        return points.enumerated().map { index, alt in
            (alt, count > 1 ? usedWidth * CGFloat(index) / CGFloat(count - 1) : 0)
        }
    }

    /// Y 映射
    private func yFor(_ alt: CGFloat, mid: CGFloat, range: CGFloat) -> CGFloat {
        let paddingTop: CGFloat = h * 0.12
        let paddingBottom: CGFloat = h * 0.14
        let usableTop = h / 2 - paddingTop
        let usableBottom = h / 2 - paddingBottom
        let t = (alt - mid) / range
        if t >= 0 {
            return h / 2 - usableTop * t
        } else {
            return h / 2 - usableBottom * t
        }
    }

    /// 可見範圍內嘅樓層標籤
    private func visibleFloors(mid: CGFloat, range: CGFloat) -> [(floor: Int, label: String, alt: CGFloat)] {
        let padding: CGFloat = h * 0.12
        let paddingBottom: CGFloat = h * 0.14
        let topAlt = mid + range
        let bottomAlt = mid - range

        if !floorHeights.isEmpty {
            var calibrated = floorHeights
            if !calibrated.contains(where: { $0.floor == referenceFloor }) {
                calibrated.append((floor: referenceFloor, height: 0))
            }
            return calibrated.filter { $0.height >= bottomAlt - 0.5 && $0.height <= topAlt + 0.5 }
                .map { ($0.floor, ParkingFloorStore.formatFloor($0.floor), $0.height) }
        }

        var floors: [(Int, String, CGFloat)] = []
        let floorMin = Int(floor(bottomAlt / oneFloorMeters))
        let floorMax = Int(ceil(topAlt / oneFloorMeters))
        for f in floorMin...floorMax {
            let alt = CGFloat(f) * oneFloorMeters
            if alt >= bottomAlt - 0.5 && alt <= topAlt + 0.5 {
                floors.append((f, String(format: "%.0fm", Double(alt)), alt))
            }
        }
        return floors
    }

    var body: some View {
        let plotted = plottedPoints()
        let pts = plotted.map(\.alt)
        let count = pts.count
        let minAlt = pts.min()!
        let maxAlt = pts.max()!
        let mid = (minAlt + maxAlt) / 2
        let halfRange = max((maxAlt - minAlt) / 2, oneFloorMeters / 2)

        let floors = visibleFloors(mid: mid, range: halfRange)

        HStack(spacing: 0) {
            // 左側樓層標籤
            ZStack(alignment: .trailing) {
                ForEach(floors, id: \.0) { floor, label, alt in
                    let y = yFor(alt, mid: mid, range: halfRange)
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .trailing)
                        .padding(.trailing, 4)
                        .position(x: labelWidth / 2, y: y)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .frame(width: labelWidth, height: h)

            // 右側曲線區域
            ZStack {
                // 填充（帶右側漸變淡化）
                Path { p in
                    p.move(to: CGPoint(x: plotted[0].x, y: h))
                    p.addLine(to: CGPoint(x: plotted[0].x, y: yFor(pts[0], mid: mid, range: halfRange)))
                    for i in 0..<count {
                        p.addLine(to: CGPoint(x: plotted[i].x, y: yFor(pts[i], mid: mid, range: halfRange)))
                    }
                    let lastX = plotted.last!.x
                    p.addLine(to: CGPoint(x: lastX, y: yFor(pts.last!, mid: mid, range: halfRange)))
                    p.addLine(to: CGPoint(x: lastX, y: h))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.10), accentColor.opacity(0.03)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                // 線條
                Path { p in
                    p.move(to: CGPoint(x: plotted[0].x, y: yFor(pts[0], mid: mid, range: halfRange)))
                    for i in 1..<count {
                        p.addLine(to: CGPoint(x: plotted[i].x, y: yFor(pts[i], mid: mid, range: halfRange)))
                    }
                }
                .stroke(accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // 車喺最新點
                let lastX = plotted.last!.x
                let lastY = yFor(pts.last!, mid: mid, range: halfRange)
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: carIconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .scaleEffect(x: -1)
                }
                .position(x: lastX, y: lastY)
            }
            .frame(width: curveAreaWidth, height: h)
        }
    }
}

// MARK: - 樓層曲線懸浮窗測試

struct FloorCurveTestView: View {
    @State private var showPopup = false
    @State private var viewMode: ViewMode = .popup
    @State private var animationDirection: FloorCurveDirection = .down
    @State private var targetFloor: Int = -1
    @State private var currentDisplayFloor: Int = 0
    @State private var carProgress: CGFloat = 0
    @State private var isAnimating = false
    @State private var animationTimer: Timer?
    @AppStorage("floorCurveCarIcon") private var carIcon: String = "car.side.fill"

    // 嵌入模式：拖動高度
    @State private var dragAltitude: CGFloat = 0          // 模擬海拔變化（米）
    @State private var altitudeHistory: [CGFloat] = []     // 歷史海拔點
    @State private var sampleTimer: Timer?
    @State private var currentDirection: FloorCurveDirection = .down

    // 膠囊模式：可拖動切換狀態
    enum CapsuleState { case compact, expanded, floorCurve }
    @State private var capsuleState: CapsuleState = .compact
    @State private var capsuleDragOffset: CGFloat = 0
    @State private var isCapsuleDragging: Bool = false

    enum FloorCurveDirection { case up, down }
    enum ViewMode: String, CaseIterable { case popup = "彈窗", inline = "嵌入", capsule = "膠囊" }

    private var carIconName: String { carIcon }

    // 拖動模式下嘅樓層
    private var dragFloor: Int {
        let mpF: Double = 3.0
        return Int((dragAltitude / mpF).rounded(.toNearestOrAwayFromZero))
    }

    // 動態曲線高度：根據海拔範圍自動調整
    private var dynamicCurveHeight: CGFloat {
        guard altitudeHistory.count > 1 else { return 90 }
        let minAlt = altitudeHistory.min()!
        let maxAlt = altitudeHistory.max()!
        let range = maxAlt - minAlt
        let floors = range / 3.0  // 幾層樓
        // 一層 90pt，最少 90pt
        return max(90, floors * 90)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 模式切換
                    Picker("顯示模式", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // 嵌入模式
                    if viewMode == .inline {
                        inlineCard
                            .padding(.horizontal)

                        // 拖動高度控制
                        VStack(spacing: 12) {
                            Text("拖動模擬高度")
                                .font(.headline)
                            HStack(spacing: 16) {
                                Image(systemName: "arrow.down.to.line")
                                    .foregroundStyle(.blue)
                                Slider(value: $dragAltitude, in: -20...20, step: 0.1) { editing in
                                    if editing {
                                        startSampling()
                                    } else {
                                        stopSampling()
                                    }
                                }
                                .tint(.blue)
                                Image(systemName: "arrow.up.to.line")
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 4)

                            HStack {
                                Text(ParkingFloorStore.formatFloor(dragFloor))
                                    .monospacedDigit().foregroundStyle(.blue)
                                Spacer()
                                Text(String(format: "%+.1f m", dragAltitude))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.system(size: 15, weight: .medium))
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // 膠囊模式預覽
                    if viewMode == .capsule {
                        VStack(spacing: 16) {
                            Text("膠囊互動測試")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.top, 8)

                            Text("向上拖動展開，繼續拖動切換到樓層探測")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))

                            // 互動膠囊
                            interactiveCapsule
                                .padding(.vertical, 20)

                            // 當前狀態顯示
                            HStack {
                                Text("當前狀態：")
                                    .foregroundStyle(.white.opacity(0.7))
                                Spacer()
                                Text(capsuleStateLabel)
                                    .font(.body.bold())
                                    .foregroundStyle(.white)
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)

                            // 手動切換按鈕
                            HStack(spacing: 12) {
                                Button("緊湊態") {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        capsuleState = .compact
                                    }
                                }
                                .font(.caption)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(capsuleState == .compact ? Color.teal : Color.white.opacity(0.15))
                                .foregroundStyle(capsuleState == .compact ? .white : .white.opacity(0.8))
                                .cornerRadius(16)

                                Button("擴展態") {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        capsuleState = .expanded
                                    }
                                }
                                .font(.caption)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(capsuleState == .expanded ? Color.teal : Color.white.opacity(0.15))
                                .foregroundStyle(capsuleState == .expanded ? .white : .white.opacity(0.8))
                                .cornerRadius(16)

                                Button("樓層探測") {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        capsuleState = .floorCurve
                                    }
                                }
                                .font(.caption)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(capsuleState == .floorCurve ? Color.teal : Color.white.opacity(0.15))
                                .foregroundStyle(capsuleState == .floorCurve ? .white : .white.opacity(0.8))
                                .cornerRadius(16)
                            }
                        }
                        .padding()
                        .background(
                            ZStack {
                                // 深色背景
                                Color.black.opacity(0.92)

                                // 光球效果
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    let h = geo.size.height

                                    ZStack {
                                        // 藍色光球
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [Color(hex: "0098FF").opacity(0.3), Color.clear],
                                                    center: .center,
                                                    startRadius: 0,
                                                    endRadius: w * 0.4
                                                )
                                            )
                                            .frame(width: w * 0.8, height: w * 0.8)
                                            .offset(x: -w * 0.2, y: -h * 0.1)

                                        // 青色光球
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [Color(hex: "5CAEB7").opacity(0.25), Color.clear],
                                                    center: .center,
                                                    startRadius: 0,
                                                    endRadius: w * 0.35
                                                )
                                            )
                                            .frame(width: w * 0.7, height: w * 0.7)
                                            .offset(x: w * 0.2, y: h * 0.1)

                                        // 黃色光球
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [Color(hex: "BEBC3F").opacity(0.2), Color.clear],
                                                    center: .center,
                                                    startRadius: 0,
                                                    endRadius: w * 0.3
                                                )
                                            )
                                            .frame(width: w * 0.6, height: w * 0.6)
                                            .offset(x: w * 0.1, y: -h * 0.2)
                                    }
                                }
                            }
                        )
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // 彈窗模式嘅控制
                    if viewMode == .popup {
                        VStack(spacing: 14) {
                            Text("模擬場景").font(.headline)
                            VStack(spacing: 8) {
                                Text("去到...").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    floorButton("B4", floor: -4)
                                    floorButton("B3", floor: -3)
                                    floorButton("B2", floor: -2)
                                    floorButton("B1", floor: -1)
                                }
                                HStack(spacing: 12) {
                                    floorButton("G", floor: 0)
                                    floorButton("1F", floor: 1)
                                    floorButton("2F", floor: 2)
                                    floorButton("3F", floor: 3)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        // 當前狀態
                        HStack {
                            Text("當前樓層").foregroundStyle(.secondary)
                            Spacer()
                            Text(ParkingFloorStore.formatFloor(currentDisplayFloor))
                                .monospacedDigit().foregroundStyle(.blue)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // 車 Icon 選擇
                    VStack(spacing: 10) {
                        Text("車輛 Icon").font(.headline)
                        HStack(spacing: 16) {
                            iconChoiceButton("car.side.fill", label: "轎車")
                            iconChoiceButton("suv.side.fill", label: "SUV")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }

            // 彈窗模式
            if showPopup && viewMode == .popup {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissPopup() }

                popupCard
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 340)
                    .transition(.blurReplace)
            }
        }
        .navigationTitle("樓層曲線測試")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 互動膠囊

    private var capsuleStateLabel: String {
        switch capsuleState {
        case .compact: return "緊湊態"
        case .expanded: return "擴展態"
        case .floorCurve: return "樓層探測態"
        }
    }

    private var interactiveCapsuleHeight: CGFloat {
        switch capsuleState {
        case .compact: return 44
        case .expanded: return 182
        case .floorCurve: return 240
        }
    }

    private var interactiveCapsuleWidth: CGFloat {
        switch capsuleState {
        case .compact: return 270
        case .expanded, .floorCurve: return 370
        }
    }

    private var interactiveCapsule: some View {
        let accentColor: Color = currentDirection == .down ? .blue : .green

        return ZStack {
            if capsuleState == .floorCurve {
                // 樓層探測態內容
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(accentColor.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: carIconName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(accentColor)
                                .scaleEffect(x: -1)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("樓層探測")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(ParkingFloorStore.formatFloor(dragFloor))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: dragFloor)
                        }

                        Spacer()

                        Image(systemName: currentDirection == .down ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(accentColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    inlineCurveArea(accentColor: accentColor, direction: currentDirection)
                        .frame(height: 80)
                        .padding(.horizontal, 8)
                        .background(accentColor.opacity(0.04))
                        .cornerRadius(12)
                        .padding(.horizontal, 12)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.teal)
                        Text("已鎖定樓層")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                }
            } else if capsuleState == .expanded {
                // 擴展態內容
                VStack(spacing: 8) {
                    HStack {
                        Text("已停留")
                            .font(.body.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("00:05:23")
                            .font(.body.bold())
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.teal)
                        Text("我的位置地址")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Button("泊車記憶") {}
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.teal.opacity(0.15))
                            .cornerRadius(16)
                        Button("最優路線") {}
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(16)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            } else {
                // 緊湊態內容
                HStack {
                    RoseFourView(loop: 1.0, opacity: 1.0, blurRadius: 0)
                        .frame(width: 50, height: 50)
                        .padding(.horizontal, 6)
                    Text("我的位置")
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: interactiveCapsuleWidth, height: interactiveCapsuleHeight)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(Color(.secondarySystemBackground))
        )
        .cornerRadius(34)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isCapsuleDragging = true
                    capsuleDragOffset = value.translation.height
                }
                .onEnded { value in
                    isCapsuleDragging = false
                    let dy = value.translation.height

                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if dy < -50 {
                            // 向上拖動
                            switch capsuleState {
                            case .compact:
                                capsuleState = .expanded
                            case .expanded:
                                capsuleState = .floorCurve
                            case .floorCurve:
                                break
                            }
                        } else if dy > 50 {
                            // 向下拖動
                            switch capsuleState {
                            case .floorCurve:
                                capsuleState = .expanded
                            case .expanded:
                                capsuleState = .compact
                            case .compact:
                                break
                            }
                        }
                    }
                    capsuleDragOffset = 0
                }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: capsuleState)
    }

    // MARK: - 膠囊預覽

    /// 緊湊態膠囊預覽
    private var compactCapsulePreview: some View {
        HStack {
            RoseFourView(loop: 1.0, opacity: 1.0, blurRadius: 0)
                .frame(width: 50, height: 50)
                .padding(.horizontal, 6)
            Text("我的位置")
                .font(.body.bold())
                .foregroundStyle(.primary)
            Spacer()
        }
        .frame(width: 270, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(Color(.secondarySystemBackground))
        )
        .cornerRadius(34)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    /// 擴展態膠囊預覽
    private var expandedCapsulePreview: some View {
        VStack(spacing: 8) {
            HStack {
                Text("已停留")
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text("00:05:23")
                    .font(.body.bold())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.teal)
                Text("我的位置地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button("泊車記憶") {}
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.teal.opacity(0.15))
                    .cornerRadius(16)
                Button("最優路線") {}
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(16)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 370, height: 182)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(Color(.secondarySystemBackground))
        )
        .cornerRadius(34)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    /// 樓層探測態膠囊預覽
    private var floorCurveCapsulePreview: some View {
        let accentColor: Color = currentDirection == .down ? .blue : .green

        return VStack(spacing: 8) {
            // 頂部：車 icon + 樓層 + 方向
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: carIconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(accentColor)
                        .scaleEffect(x: -1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("樓層探測")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(ParkingFloorStore.formatFloor(dragFloor))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: dragFloor)
                }

                Spacer()

                Image(systemName: currentDirection == .down ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // 曲線區域
            inlineCurveArea(accentColor: accentColor, direction: currentDirection)
                .frame(height: 80)
                .padding(.horizontal, 8)
                .background(accentColor.opacity(0.04))
                .cornerRadius(12)
                .padding(.horizontal, 12)

            // 鎖定後顯示確認訊息
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.teal)
                Text("已鎖定樓層")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 370, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(Color(.secondarySystemBackground))
        )
        .cornerRadius(34)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    // MARK: - 嵌入模式卡片

    private var inlineCard: some View {
        let accentColor: Color = currentDirection == .down ? .blue : .green
        let direction = currentDirection

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: carIconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accentColor)
                        .scaleEffect(x: -1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("樓層探測")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(ParkingFloorStore.formatFloor(dragFloor))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: dragFloor)
                }

                Spacer()

                Image(systemName: direction == .down ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            inlineCurveArea(accentColor: accentColor, direction: direction)
                .frame(height: 100)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.04))
                .cornerRadius(14)
                .padding(.horizontal, 14)

            // 鎖定狀態預覽
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.teal)
                Text("已鎖定樓層")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemBackground))
        )
        .cornerRadius(28)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - 嵌入曲線區域

    private func inlineCurveArea(accentColor: Color, direction: FloorCurveDirection) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                if altitudeHistory.count <= 1 {
                    // 未開始拖動或只有一個初始點：只顯示車喺左邊，冇橫線
                    carIconView(color: accentColor)
                        .position(x: 20, y: h / 2)
                } else {
                    InlineCurveContent(
                        history: altitudeHistory,
                        w: w, h: h,
                        accentColor: accentColor,
                        carIconName: carIconName
                    )
                }
            }
        }
    }

    // MARK: - 彈窗模式卡片

    private var popupCard: some View {
        let accentColor: Color = animationDirection == .down ? .blue : .green

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: carIconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accentColor)
                        .scaleEffect(x: -1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("樓層探測")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(ParkingFloorStore.formatFloor(isAnimating ? interpolatedFloor : targetFloor))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.5), value: interpolatedFloor)
                }

                Spacer()

                Image(systemName: animationDirection == .down ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accentColor)
                    .symbolEffect(.pulse, isActive: isAnimating)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            popupCurveArea(accentColor: accentColor)
                .frame(height: 100)
                .padding(.horizontal, 10)
                .background(accentColor.opacity(0.04))
                .cornerRadius(14)
                .padding(.horizontal, 14)

            Spacer().frame(height: 4)
        }
    }

    // MARK: - 彈窗曲線區域

    private func popupCurveArea(accentColor: Color) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let startY = animationDirection == .down ? h * 0.25 : h * 0.75
            let endY = animationDirection == .down ? h * 0.75 : h * 0.25

            ZStack {
                curveFillPath(w: w, h: h, startY: startY, endY: endY)
                    .fill(accentColor.opacity(0.08))
                curveLinePath(w: w, h: h, startY: startY, endY: endY)
                    .stroke(accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                let t = carProgress
                let x = w * t
                let y = curveY(t: t, height: h, startY: startY, endY: endY)
                carIconView(color: accentColor)
                    .position(x: min(x, w - 16), y: y)
            }
        }
    }

    // MARK: - 車 Icon

    private func carIconView(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: carIconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .scaleEffect(x: -1)
        }
    }

    // MARK: - 拖動高度處理

    // MARK: - 拖動取樣

    private func startSampling() {
        withAnimation(.easeInOut(duration: 0.3)) {
            altitudeHistory = [0]
            currentDirection = .down
        }

        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                let prev = altitudeHistory.last ?? 0
                let now = dragAltitude
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentDirection = now >= prev ? .up : .down
                    altitudeHistory.append(now)
                }
            }
        }
    }

    private func stopSampling() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        let prev = altitudeHistory.last ?? 0
        let now = dragAltitude
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDirection = now >= prev ? .up : .down
            altitudeHistory.append(now)
        }

        // 如果回到 0 附近，重置曲線
        if abs(dragAltitude) < 0.2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    altitudeHistory = []
                    currentDirection = .down
                }
            }
        }
    }

    // MARK: - 按鈕

    private func floorButton(_ label: String, floor: Int) -> some View {
        Button {
            triggerAnimation(to: floor)
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 60, height: 44)
                .background(floor < currentDisplayFloor ? Color.blue : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }

    private func iconChoiceButton(_ icon: String, label: String) -> some View {
        Button {
            carIcon = icon
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(carIcon == icon ? .blue : .secondary)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(carIcon == icon ? .blue : .secondary)
            }
            .frame(width: 80, height: 60)
            .background(carIcon == icon ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(carIcon == icon ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }

    // MARK: - 彈窗動畫

    private func triggerAnimation(to floor: Int) {
        targetFloor = floor
        animationDirection = floor < currentDisplayFloor ? .down : .up
        carProgress = 0
        isAnimating = true

        withAnimation(.easeInOut(duration: 0.4)) { showPopup = true }

        let floorCount = abs(floor - currentDisplayFloor)
        guard floorCount > 0 else { return }
        let duration = Double(floorCount) * 3.0
        let steps = Int(duration / 0.03)
        let increment = 1.0 / CGFloat(steps)

        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            carProgress += increment
            if carProgress >= 1.0 {
                timer.invalidate()
                isAnimating = false
                currentDisplayFloor = targetFloor
                carProgress = 1.0
            }
        }
    }

    private func dismissPopup() {
        animationTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.4)) { showPopup = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            carProgress = 0
            isAnimating = false
        }
    }

    // MARK: - 插值樓層

    private var interpolatedFloor: Int {
        let diff = Double(targetFloor - currentDisplayFloor)
        let current = Double(currentDisplayFloor) + diff * Double(carProgress)
        return Int(current.rounded())
    }

    // MARK: - 彈窗曲線計算

    private func curveY(t: CGFloat, height: CGFloat, startY: CGFloat, endY: CGFloat) -> CGFloat {
        let base = startY + (endY - startY) * t
        let noise1 = sin(t * 28) * height * 0.015
        let noise2 = sin(t * 47 + 1.3) * height * 0.01
        let noise3 = sin(t * 73 + 2.7) * height * 0.008
        let floorCount = abs(targetFloor - currentDisplayFloor)
        let stepNoise: CGFloat = floorCount > 0 ? sin(t * CGFloat(floorCount) * .pi) * height * 0.04 : 0
        return base + noise1 + noise2 + noise3 + stepNoise
    }

    private func curveLinePath(w: CGFloat, h: CGFloat, startY: CGFloat, endY: CGFloat) -> Path {
        var path = Path()
        let steps = 60
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = w * t
            let y = curveY(t: t, height: h, startY: startY, endY: endY)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    private func curveFillPath(w: CGFloat, h: CGFloat, startY: CGFloat, endY: CGFloat) -> Path {
        var path = Path()
        let steps = 60
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: startY))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = w * t
            let y = curveY(t: t, height: h, startY: startY, endY: endY)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: endY))
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }
}
