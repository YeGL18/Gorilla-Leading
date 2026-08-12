import SwiftUI
import CoreLocation
import CoreMotion
import MapKit

struct SettingsView: View {
    @State private var simSpeed: Double = 0
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("highFrequencyTracking") var highFrequencyTracking: Bool = true
    @AppStorage("mapTrackingAnimation") var mapTrackingAnimation: Int = 0
    @AppStorage("sfxAccelerationEnabled") private var sfxAccelerationEnabled: Bool = true
    @AppStorage("orbMasterEnabled") var orbMasterEnabled: Bool = true
    @AppStorage("orbCapsule") var orbCapsule: Bool = true
    @AppStorage("orbExpanded") var orbExpanded: Bool = true
    @AppStorage("orbParkingMemory") var orbParkingMemory: Bool = true
    @AppStorage("orbBackgroundHome") var orbBackgroundHome: Bool = true
    @AppStorage("orbBackgroundSpeed") var orbBackgroundSpeed: Bool = true
    @AppStorage("useTimeBasedOrb") var useTimeBasedOrb: Bool = false
    @AppStorage("mapStyleIndex") private var mapStyleIndex: Int = 0
    @AppStorage("vlmRecognitionEnabled") private var vlmRecognitionEnabled: Bool = true
    @State private var timePreviewHour: Double = Double(Calendar.current.component(.hour, from: Date()))
    @State private var isAutoPlaying = false
    @State private var autoPlayTimer: Timer?
    @StateObject private var previewClock = AnimationClock()
    @StateObject private var previewPhaseManager = TimePhaseManager()
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var destinationManager: DestinationManager
    
    @State private var showingDestinationPicker = false
    @State private var showingAddDestination = false
    @State private var showingEditDestination = false
    @State private var editingDestination: Destination?

    var body: some View {
        NavigationStack {
            List {
                // Destination Section
                Section {
                    if destinationManager.destinations.isEmpty {
                        Text("No saved destinations yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(destinationManager.destinations) { destination in
                            HStack {
                                Circle()
                                    .fill(destination.color)
                                    .frame(width: 12, height: 12)
                                Text(destination.name)
                                Spacer()
                                if destinationManager.selectedDestination?.id == destination.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                                if let distance = destination.formattedDistance,
                                   let time = destination.formattedTime {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(distance)
                                            .font(.caption)
                                        Text(time)
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                destinationManager.selectDestination(destination)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    destinationManager.deleteDestination(destination)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                
                                Button {
                                    editingDestination = destination
                                    showingEditDestination = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Label("Destinations", systemImage: "mappin.circle")
                        Spacer()
                        Button {
                            showingAddDestination = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }

                // Appearance Section
                Section {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag(0)
                        Text("Dark").tag(1)
                        Text("Light").tag(2)
                    }

                    Picker("Color Scheme", selection: $colorSchemeIndex) {
                        Text("Default").tag(0)
                        Text("27").tag(1)
                    }
                } header: {
                    Label("Appearance", systemImage: "paintpalette")
                }

                // Map Tracking Section
                Section {
                    Toggle(isOn: $highFrequencyTracking) {
                        Label("高頻率地圖追蹤", systemImage: "location.fill")
                    }
                    Text("開啟後地圖視角更新更流暢，但會增加耗電。關閉後更新頻率降低，延長電池壽命。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("追蹤動畫", selection: $mapTrackingAnimation) {
                        Text("標準").tag(0)
                        Text("柔軟").tag(1)
                    }
                } header: {
                    Label("Map Tracking", systemImage: "map")
                }

                Section {
                    Picker("地圖風格", selection: $mapStyleIndex) {
                        Text("默認").tag(0)
                        Text("我的世界").tag(1)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Map Style", systemImage: "paintbrush")
                }

                Section {
                    Toggle(isOn: $sfxAccelerationEnabled) {
                        Label("加速音效", systemImage: "speaker.wave.2")
                    }
                    Text("關閉後，時速頁嘅「加速」提示聲會停用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Sound", systemImage: "speaker")
                }

                Section {
                    Toggle(isOn: $vlmRecognitionEnabled) {
                        Label("VLM 車位識別", systemImage: "brain.head.profile")
                    }
                    Text("拍照後自動使用 VLM 識別車位號、樓層、區域代碼。關閉後拍照唔會觸發識別。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Parking Recognition", systemImage: "car")
                }

                // Orb Effects Section
                Section {
                    Toggle(isOn: $orbMasterEnabled) {
                        Label("光球效果總開關", systemImage: "sparkles")
                    }

                    if orbMasterEnabled {
                        Picker("背景效果", selection: $useTimeBasedOrb) {
                            Text("光球").tag(false)
                            Text("時程").tag(true)
                        }
                        
                        Toggle("緊湊膠囊", isOn: $orbCapsule)
                        Toggle("擴展膠囊", isOn: $orbExpanded)
                        Toggle("泊車記憶", isOn: $orbParkingMemory)
                        Toggle("主頁背景", isOn: $orbBackgroundHome)
                        Toggle("時速頁背景", isOn: $orbBackgroundSpeed)
                        
                        if useTimeBasedOrb {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("預覽時間")
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
                                    Text("0:00")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("6:00")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("12:00")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("18:00")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("24:00")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                // 时程光球预览
                                GeometryReader { geo in
                                    let phoneHeight = geo.size.width * (19.5 / 9.0)
                                    TimeBasedOrbView(phaseManager: previewPhaseManager, clock: previewClock, orbEnabled: true)
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
                } header: {
                    Label("光球效果", systemImage: "sparkles")
                }

            }
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 36)
            .listRowSpacing(0)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ParkingFloorTestView()
                    } label: {
                        Text("測試")
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
                // 通知 TimePhaseManager 预览时间
                NotificationCenter.default.post(
                    name: .timePhasePreviewChanged,
                    object: nil,
                    userInfo: ["hour": newValue]
                )
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

struct ParkingFloorTestView: View {
    var body: some View {
        List {
            NavigationLink {
                ParkingFlowTestView()
            } label: {
                Label("停車流程測試", systemImage: "parkingsign.circle.fill")
            }
            
            NavigationLink {
                TimeOrbAnimationTestView()
            } label: {
                Label("時程光球動畫測試", systemImage: "sparkles")
            }
            
            NavigationLink {
                VisitRecordsTestView()
            } label: {
                Label("到訪記錄測試", systemImage: "mappin.and.ellipse")
            }
            
            NavigationLink {
                SpeedAnimationTestView()
            } label: {
                Label("模擬動畫時速動畫測試", systemImage: "speedometer")
            }
            
            NavigationLink {
                AltimeterTestView()
            } label: {
                Label("氣壓計曲線測試", systemImage: "barometer")
            }
            
            NavigationLink {
                AddressCapsuleBeamTestView()
            } label: {
                Label("地址膠囊 BorderBeam 測試", systemImage: "dot.squareshape.split.2x2")
            }

            NavigationLink {
                TripPatternDebugView()
            } label: {
                Label("路線學習記錄（目的地預測）", systemImage: "brain.head.profile")
            }

            NavigationLink {
                ParkingMemoryPhotoTestView()
            } label: {
                Label("泊車記憶拍照效果測試", systemImage: "camera.on.rectangle")
            }

            NavigationLink {
                ParkingMemorySwipeTestView()
            } label: {
                Label("抽離牌組動畫測試", systemImage: "rectangle.split.3x1")
            }

            NavigationLink {
                ParkingRecognitionTestView()
            } label: {
                Label("泊車辨識測試 (OCR)", systemImage: "text.viewfinder")
            }

            NavigationLink {
                ParkingLLMRecognitionTestView()
            } label: {
                Label("泊車辨識測試 (LLM)", systemImage: "brain.head.profile")
            }
        }
        .navigationTitle("測試")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ParkingFlowTestView: View {
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    
    @State private var expandedLotIDs: Set<UUID> = []
    @State private var renamingLotID: UUID?
    @State private var renamingText: String = ""
    @State private var showRenameAlert = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("停車場數")
                    Spacer()
                    Text("\(parkingFloorStore.lots.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                HStack {
                    Text("停車點數")
                    Spacer()
                    Text("\(parkingFloorStore.allPoints.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            
            if parkingFloorStore.lots.isEmpty {
                Section {
                    Text("未有任何停車點記錄")
                        .foregroundStyle(.secondary)
                } header: {
                    Label("停車場 / 停車點", systemImage: "parkingsign.circle.fill")
                }
            } else {
                ForEach(parkingFloorStore.lots) { lot in
                    Section {
                        if expandedLotIDs.contains(lot.id) {
                            ForEach(lot.points) { point in
                                pointRow(point)
                            }
                        } else {
                            if let first = lot.points.first {
                                pointRow(first)
                            }
                        }
                    } header: {
                        lotHeader(lot)
                    }
                }
            }
            
            Section {
                Button(role: .destructive) {
                    parkingFloorStore.clearAll()
                } label: {
                    Label("清除全部停車點數據", systemImage: "trash")
                }
            }
        }
        .navigationTitle("停車流程測試")
        .navigationBarTitleDisplayMode(.inline)
        .alert("停車場改名", isPresented: $showRenameAlert) {
            TextField("名稱", text: $renamingText)
            Button("取消", role: .cancel) {}
            Button("確定") {
                guard let id = renamingLotID else { return }
                parkingFloorStore.setLotName(lotID: id, name: renamingText)
                renamingLotID = nil
            }
        }
    }
    
    private func lotHeader(_ lot: ParkingLotRecord) -> some View {
        let isExpanded = expandedLotIDs.contains(lot.id)
        let title = lot.name ?? "停車場"
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedLotIDs.remove(lot.id)
                        } else {
                            expandedLotIDs.insert(lot.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(lot.points.count) 點")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                NavigationLink {
                    ParkingLotDetailView(lot: lot)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    renamingLotID = lot.id
                    renamingText = lot.name ?? ""
                    showRenameAlert = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                keyValue("中心", String(format: "%.6f, %.6f", lot.centerLatitude, lot.centerLongitude))
                keyValue("半徑", "\(Int(lot.radiusMeters))m")
                keyValue("更新", lot.updatedAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                if let m = lot.learnedMetersPerFloor {
                    keyValue("每層高度", String(format: "%.2fm", m))
                }
                if let c = lot.learnedConfidence {
                    keyValue("信心度", String(format: "%.2f", c))
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func pointRow(_ point: ParkingPointRecord) -> some View {
        let floor = point.displayFloor ?? "未知"
        let conf: String = {
            if let c = point.confidence { return String(format: "%.2f", c) }
            return "—"
        }()
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "parkingsign.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.address.isEmpty ? "Unknown" : point.address)
                        .font(.system(size: 16, weight: .semibold))
                    Text(point.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(floor)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                    Text("信心 \(conf)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            
            HStack(spacing: 12) {
                Text(String(format: "%.6f, %.6f", point.latitude, point.longitude))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                floorAdjuster(point)
            }
        }
        .padding(.vertical, 6)
    }
    
    private func floorAdjuster(_ point: ParkingPointRecord) -> some View {
        let current = point.manualFloorIndex ?? point.predictedFloorIndex
        return HStack(spacing: 10) {
            Button {
                let next = (current ?? 0) - 1
                parkingFloorStore.setManualFloor(pointID: point.id, floorIndex: next)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            Text(ParkingFloorStore.formatFloor(current ?? 0))
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 26)
                .monospacedDigit()
            
            Button {
                let next = (current ?? 0) + 1
                parkingFloorStore.setManualFloor(pointID: point.id, floorIndex: next)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            Button {
                parkingFloorStore.setManualFloor(pointID: point.id, floorIndex: nil)
            } label: {
                Text("清除")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
    
    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 13))
    }
}

struct ParkingLotDetailView: View {
    let lot: ParkingLotRecord
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    @State private var renamingText: String = ""
    @State private var showRenameAlert = false
    
    var body: some View {
        let liveLot = parkingFloorStore.lots.first(where: { $0.id == lot.id }) ?? lot
        let barometer = parkingFloorStore.barometer
        List {
            Section {
                keyValue("名稱", liveLot.name ?? "（未命名）")
                keyValue("停車點數", "\(liveLot.points.count)")
                keyValue("中心", String(format: "%.6f, %.6f", liveLot.centerLatitude, liveLot.centerLongitude))
                keyValue("半徑", "\(Int(liveLot.radiusMeters))m")
                keyValue("建立", liveLot.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                keyValue("更新", liveLot.updatedAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                keyValue("每層高度", liveLot.learnedMetersPerFloor.map { String(format: "%.2fm", $0) } ?? "未學習")
                keyValue("高度偏移", liveLot.learnedOffsetMeters.map { String(format: "%.2fm", $0) } ?? "未學習")
                keyValue("學習信心度", liveLot.learnedConfidence.map { String(format: "%.3f", $0) } ?? "未學習")
                keyValue("學習記錄數", "\((liveLot.floorLearningHistory ?? []).count)")
                keyValue("氣壓計支援", barometer.isAvailable ? "支援" : "不支援")
                keyValue("已緩存樣本", "\(barometer.samples.count)")
                
                Button {
                    renamingText = liveLot.name ?? ""
                    showRenameAlert = true
                } label: {
                    Label("改名停車場", systemImage: "pencil")
                }
            } header: {
                Label("停車場資訊", systemImage: "building.2.fill")
            }
            
            Section {
                if (liveLot.floorLearningHistory ?? []).isEmpty {
                    Text("未有樓層學習記錄：當你手動幫停車點改樓層時，系統就會用氣壓高度差去學習每層高度。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array((liveLot.floorLearningHistory ?? []).sorted(by: { $0.createdAt > $1.createdAt }).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("樓層 \(ParkingFloorStore.formatFloor(item.manualFloorIndex))")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            HStack(spacing: 16) {
                                keyValue("高度差", String(format: "%.2fm", item.altitudeDeltaMeters))
                                keyValue("每層高度", String(format: "%.2fm", item.metersPerFloor))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Label("樓層學習記錄", systemImage: "book.closed.fill")
            }
            
            Section {
                ForEach(liveLot.points.sorted(by: { $0.createdAt > $1.createdAt })) { point in
                    pointDetailRow(point)
                }
            } header: {
                Label("所有停車點（含氣壓與預判）", systemImage: "parkingsign.circle.fill")
            }
        }
        .navigationTitle(liveLot.name ?? "停車場詳情")
        .navigationBarTitleDisplayMode(.inline)
        .alert("停車場改名", isPresented: $showRenameAlert) {
            TextField("名稱", text: $renamingText)
            Button("取消", role: .cancel) {}
            Button("確定") {
                parkingFloorStore.setLotName(lotID: liveLot.id, name: renamingText)
            }
        }
    }
    
    @ViewBuilder
    private func pointDetailRow(_ point: ParkingPointRecord) -> some View {
        let floorSource: String = {
            if point.manualFloorIndex != nil { return "手動" }
            if point.predictedFloorIndex != nil {
                if point.predictedFromLotLearned == true { return "預判(已學習)" }
                return "預判(預設)"
            }
            return "未知"
        }()
        let confText = point.confidence.map { String(format: "%.3f", $0) } ?? "—"
        let confProgress: Double = point.confidence ?? 0
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "parkingsign.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.address.isEmpty ? "Unknown" : point.address)
                        .font(.system(size: 15, weight: .semibold))
                    Text(point.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(point.displayFloor ?? "未知")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                    Text(floorSource)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                Label(String(format: "%.6f, %.6f", point.latitude, point.longitude), systemImage: "location.fill")
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                keyValue("手動樓層", point.manualFloorIndex.map { ParkingFloorStore.formatFloor($0) } ?? "—")
                keyValue("預判樓層", point.predictedFloorIndex.map { ParkingFloorStore.formatFloor($0) } ?? "—")
                keyValue("信心度", confText)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: confProgress)
                    .tint(Color.orange)
                HStack(spacing: 16) {
                    keyValue("氣壓高度差", point.barometerAltitudeDeltaMeters.map { String(format: "%.2fm", $0) } ?? "—")
                    keyValue("氣壓樣本", point.barometerSampleCount.map { "\($0)" } ?? "—")
                    keyValue("參考高度", point.barometerReferenceAltitude.map { String(format: "%.2fm", $0) } ?? "—")
                }
                HStack(spacing: 16) {
                    keyValue("最終高度", point.barometerFinalAltitude.map { String(format: "%.2fm", $0) } ?? "—")
                    keyValue("氣壓值", point.barometerPressureKPa.map { String(format: "%.2f kPa", $0) } ?? "—")
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    private func keyValue(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
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
    @State private var baseAltitude: Double?

    private var altitudeMin: Double {
        guard !barometer.samples.isEmpty else { return 0 }
        return barometer.samples.map { $0.relativeAltitude }.min() ?? 0
    }
    private var altitudeMax: Double {
        guard !barometer.samples.isEmpty else { return 0 }
        return barometer.samples.map { $0.relativeAltitude }.max() ?? 0
    }

    var body: some View {
        List {
            Section {
                Toggle("主 APP 氣壓計", isOn: Binding(
                    get: { barometer.isUpdating },
                    set: { _ in
                        if barometer.isUpdating { barometer.stop() } else { barometer.startIfAuthorized() }
                    }
                ))
                .tint(.orange)

                HStack {
                    Text("採樣點數")
                    Spacer()
                    Text("\(barometer.samples.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("支援狀態")
                    Spacer()
                    Text(barometer.isAvailable ? "可用" : "裝置不支援")
                        .foregroundStyle(barometer.isAvailable ? .green : .red)
                }

                HStack {
                    Text("權限")
                    Spacer()
                    Text(barometer.authorizationLabel)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("主 APP 氣壓計狀態", systemImage: "barometer")
            }

            Section {
                if let last = barometer.samples.last {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("相對高度")
                            Spacer()
                            Text(String(format: "%.2f m", last.relativeAltitude))
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                        }
                        HStack {
                            Text("氣壓")
                            Spacer()
                            Text(String(format: "%.2f kPa", last.pressure))
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                        }
                        HStack {
                            Text("估計樓層變化")
                            Spacer()
                            if let base = baseAltitude {
                                let delta = (last.relativeAltitude - base) / 3.0
                                Text(String(format: "%.1f 層", delta))
                                    .font(.system(size: 17, weight: .semibold))
                                    .monospacedDigit()
                            } else {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("尚未有採樣數據")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } header: {
                Label("最新讀數", systemImage: "gauge.medium")
            }

            Section {
                if barometer.samples.count >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("高度曲線")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(String(format: "min %.1f  max %.1f", altitudeMin, altitudeMax))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        AltitudeChartView2(samples: barometer.samples,
                                           altitudeMin: altitudeMin,
                                           altitudeMax: altitudeMax)
                            .frame(height: 180)
                            .padding(.vertical, 6)

                        Text("每層高度按 3m 估算；曲線縱軸為採樣開始起計嘅相對高度（米）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("累積 2 點以上先會顯示曲線")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } header: {
                Label("高度曲線", systemImage: "chart.xyaxis.line")
            }

            Section {
                Button(role: .destructive) {
                    barometer.clearSamples()
                    baseAltitude = nil
                } label: {
                    Label("清除數據", systemImage: "trash")
                }
                .disabled(barometer.samples.isEmpty)
            }
        }
        .navigationTitle("氣壓計曲線測試")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: barometer.samples.count) { _, newCount in
            if baseAltitude == nil, let first = barometer.samples.first {
                baseAltitude = first.relativeAltitude
            }
        }
    }
}

private struct AltitudeChartView2: View {
    let samples: [BarometerSample]
    let altitudeMin: Double
    let altitudeMax: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padH: CGFloat = 14
            let n = samples.count
            let xStep = n <= 1 ? w : w / CGFloat(n - 1)
            let span = max(0.01, altitudeMax - altitudeMin)

            ZStack(alignment: .topLeading) {
                Path { p in
                    for i in 0..<5 {
                        let y = padH + (h - 2 * padH) * CGFloat(i) / 4.0
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 0.5))

                if n >= 2 {
                    Path { p in
                        for (i, s) in samples.enumerated() {
                            let x = CGFloat(i) * xStep
                            let t = (s.relativeAltitude - altitudeMin) / span
                            let y = padH + (h - 2 * padH) * CGFloat(1.0 - t)
                            let pt = CGPoint(x: x, y: y)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    Path { p in
                        for (i, s) in samples.enumerated() {
                            let x = CGFloat(i) * xStep
                            let t = (s.relativeAltitude - altitudeMin) / span
                            let y = padH + (h - 2 * padH) * CGFloat(1.0 - t)
                            let pt = CGPoint(x: x, y: y)
                            if i == 0 {
                                p.move(to: CGPoint(x: pt.x, y: h - padH))
                                p.addLine(to: pt)
                            } else {
                                p.addLine(to: pt)
                            }
                        }
                        if let lastX = samples.indices.last.map({ CGFloat($0) * xStep }) {
                            p.addLine(to: CGPoint(x: lastX, y: h - padH))
                            p.closeSubpath()
                        }
                    }
                    .fill(LinearGradient(colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.03)],
                                         startPoint: .top, endPoint: .bottom))
                }
            }
        }
    }
}

struct VisitRecordsTestView: View {
    @EnvironmentObject private var locationManager: LocationManager
    
    var body: some View {
        List {
            Section {
                if locationManager.visits.isEmpty {
                    Text("未有到訪記錄")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(locationManager.visits.enumerated()), id: \.element.id) { _, visit in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(.secondary.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: transportIcon(visit.transportType))
                                    .font(.system(size: 18))
                                    .foregroundStyle(.orange)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 8, height: 8)
                                    Text(visit.address)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(.primary)
                                }
                                
                                HStack(spacing: 4) {
                                    Text(visit.arrivalDate, format: .dateTime.hour().minute())
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                    Text("→")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary.opacity(0.7))
                                    if let dep = visit.departureDate {
                                        Text(dep, format: .dateTime.hour().minute())
                                            .font(.system(size: 15))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Now")
                                            .font(.system(size: 15))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Text(visit.duration)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Label("到訪記錄", systemImage: "mappin.and.ellipse")
            } footer: {
                if !locationManager.visits.isEmpty {
                    Button(role: .destructive) {
                        locationManager.clearVisits()
                    } label: {
                        Label("清除所有到訪記錄", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("到訪記錄測試")
        .navigationBarTitleDisplayMode(.inline)
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

struct TimeOrbAnimationTestView: View {
    @State private var timePreviewHour: Double = Double(Calendar.current.component(.hour, from: Date()))
    @State private var isAutoPlaying = false
    @State private var autoPlayTimer: Timer?
    @StateObject private var previewClock = AnimationClock()
    @StateObject private var previewPhaseManager = TimePhaseManager()
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Text("預覽時間")
                        Spacer()
                        Text("\(Int(timePreviewHour)):00")
                            .foregroundStyle(isAutoPlaying ? .orange : .secondary)
                            .monospacedDigit()
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
    @AppStorage("sfxAccelerationEnabled") private var sfxAccelerationEnabled: Bool = true
    @State private var accelArmedFromStop: Bool = true
    @State private var lastSpeedSample: Double = 0
    @State private var lastSpeedSampleAt: Date = Date()
    @State private var accelerationCooldownUntil: Date = .distantPast
    
    var body: some View {
        List {
            Section {
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
                DotMatrixView(speed: $simSpeed)
                    .frame(minHeight: 360)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
                    selectedCoordinate = item.placemark.coordinate
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
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @EnvironmentObject private var locationManager: LocationManager
    
    var body: some View {
        MapViewWrapper(region: $region, selectedCoordinate: $selectedCoordinate)
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
            .onAppear {
                if let location = locationManager.manager.location {
                    region = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                }
            }
    }
}

// 地图包装器
struct MapViewWrapper: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.region = region
        mapView.delegate = context.coordinator
        
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.region = region
        
        uiView.removeAnnotations(uiView.annotations)
        if let coordinate = selectedCoordinate {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            uiView.addAnnotation(annotation)
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
                    parent.selectedCoordinate = coordinate
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async { [self] in
                parent.region = mapView.region
            }
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

// MARK: - 路線學習記錄 Debug 頁（透明度：俾用戶睇晒所有 pattern 學習結果）
struct TripPatternDebugView: View {
    @ObservedObject private var predictor = TripPredictor.shared
    @State private var showSimulateSheet = false
    @State private var simulateFrom = ""
    @State private var simulateTo = ""
    @State private var simulateWeekday: Int = 2
    @State private var simulateSlot: TripTimeSlot = .evening

    var body: some View {
        List {
            Section("總覽") {
                HStack {
                    Text("已學習地點（Place Catalog）")
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
                    Text("最近 10 個到訪 place")
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

            Section("已學習地點") {
                if predictor.placeCatalog.isEmpty {
                    Text("暫無數據，用幾次後會自動學習。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(predictor.placeCatalog.values.sorted(by: { $0.updatedAt > $1.updatedAt }))) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(p.kind == .namedLot ? "🏷️ 已命名 Lot" : "📍 地址叢集")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(p.kind == .namedLot ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                                )
                            Spacer()
                            Text(p.updatedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(p.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(String(format: "%.5f, %.5f  ·  key: %@",
                                    p.latitude, p.longitude,
                                    p.key.count > 40 ? String(p.key.suffix(40)) : p.key))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("Pattern 規則（從 place 出發 → 下一站分布）") {
                if predictor.patterns.isEmpty {
                    Text("暫無 pattern，需要至少 2 次真實到訪 + 離開先會有第一條。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(predictor.patterns.values.sorted(by: { $0.updatedAt > $1.updatedAt }))) { rec in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(headerLabel(for: rec.key))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(rec.updatedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        let total = rec.candidates.values.reduce(0) { $0 + $1.hitCount }
                        let scored = rec.candidates.values
                            .map { (c: TripNextCandidate) -> (String, Int, Double, Double) in
                                let score = c.effectiveScore
                                let conf = total > 0 ? Double(c.hitCount) / Double(total) : 0
                                return (c.toPlaceKey, c.hitCount, conf, score)
                            }
                            .sorted { $0.2 > $1.2 }
                        ForEach(Array(scored.enumerated()), id: \.offset) { _, item in
                            let (key, hits, conf, score) = item
                            let place = predictor.placeCatalog[key]
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place?.displayName ?? key)
                                        .font(.subheadline.weight(.semibold))
                                    if let p = place {
                                        Text(p.kind == .namedLot ? "Lot: \(p.lotID?.uuidString.suffix(6) ?? "?")" : String(format: "%.4f,%.4f", p.latitude, p.longitude))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack(spacing: 10) {
                                        Text("\(hits) 次")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Text("score \(Int(score.rounded()))")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                        Text("\(Int(conf*100))%")
                                            .font(.callout.monospacedDigit().weight(.bold))
                                            .foregroundStyle(
                                                conf >= 0.85 ? .green :
                                                    conf >= 0.6 ? .orange : .secondary
                                            )
                                    }
                                    ProgressView(value: conf)
                                        .progressViewStyle(.linear)
                                        .tint(
                                            conf >= 0.85 ? .green :
                                                conf >= 0.6 ? .orange : .gray
                                        )
                                        .frame(width: 120)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        if let deny = rec.candidates.values.first(where: { $0.denyCount > 0 }) {
                            HStack {
                                Image(systemName: "hand.thumbsdown.fill")
                                    .foregroundStyle(.red)
                                Text("用戶否認過 \(deny.denyCount) 次（該候選嘅 penalty 已生效）")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("最近到訪歷史（2-gram / 3-gram 用）") {
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
        .navigationTitle("路線學習記錄")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headerLabel(for k: TripPatternKey) -> String {
        let weekdayNames = ["", "日", "一", "二", "三", "四", "五", "六"]
        let wd = (1...7).contains(k.weekday) ? weekdayNames[k.weekday] : "?"
        let fromName = k.fromKey.flatMap { predictor.placeCatalog[$0]?.displayName } ?? "（首次出發）"
        let prefix = k.twoGramFromFromKey != nil ? "3-gram: " : "2-gram: "
        let extra = k.twoGramFromFromKey.flatMap { predictor.placeCatalog[$0]?.displayName }
        if let extra = extra {
            return "\(prefix)\(extra) → \(fromName)  ·  星期\(wd)  \(k.timeSlot.description)"
        }
        return "\(prefix)from: \(fromName)  ·  星期\(wd)  \(k.timeSlot.description)"
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
                    // Phase 1: Slide out — easeOut deceleration → stop at 180px
                    // Starts fast, decelerates smoothly to a stop
                    // ═══════════════════════════════════════════════════════
                    withAnimation(.easeOut(duration: 0.5)) {
                        photoSwipeOffset = direction * 180
                    }

                    // ═══════════════════════════════════════════════════════
                    // Phase 2: Drop z-index once photo is near the edge
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        photoAnimatingOutIndex = oldIndex
                        isPhotoAnimatingOut = true
                    }

                    // ═══════════════════════════════════════════════════════
                    // At 2/3 of slide-out (~0.33s), start the next photo's TILT
                    // so it begins rising while the old photo is still sliding out
                    // ═══════════════════════════════════════════════════════
                    triggerTiltEffect(index: nextIndex)

                    // ═══════════════════════════════════════════════════════
                    // Phase 3: Slide back to stack
                    // spring = slow start → fast middle → slow landing
                    // Photo shrinks as it returns (deselection triggers scale)
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        // Reset swipe state — slower spring for a more leisurely return
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                            photoSwipeOffset = 0
                        }
                        isPhotoSwiping = false
                        isPhotoAnimatingOut = false
                        photoAnimatingOutIndex = nil

                        // Deselect old → springs to expanded stack position (shrinks)
                        resetTilt(index: oldIndex)
                        selectedPhotoIndex = nextIndex

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

        let photoW = showingExpandedPhotos ? expandedW : baseW
        let photoH = showingExpandedPhotos ? expandedH : baseH
        let selectedScale: CGFloat = (235 - 24) / expandedH
        let photoScale: CGFloat = isSelected ? selectedScale : (showingExpandedPhotos ? 0.85 : 1.0)

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

    // MARK: - TILT helpers
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
                    Text(floorText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
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
        .alert("請啟動動作按鈕", isPresented: $showActionPrompt) {
            Button("已準備好") {
                // Start polling immediately — result will be detected when shortcut finishes
                startPollingAfterAction()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("圖片已複製到剪貼簿。\n請按動作按鈕執行「\(shortcutName)」快捷指令。")
        }
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "B2" → -2
        if let regex = try? NSRegularExpression(pattern: "^[Bb](\\d+)$", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let range = Range(match.range(at: 1), in: trimmed),
           let num = Int(trimmed[range]) {
            return -num
        }
        // "-2樓" or "2樓"
        if let regex = try? NSRegularExpression(pattern: "^(-?)(\\d+)\\s*樓$", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let numRange = Range(match.range(at: 2), in: trimmed),
           let num = Int(trimmed[numRange]) {
            let hasMinus = match.range(at: 1).length > 0
            return hasMinus ? -num : num
        }
        // "地下2層"
        if let regex = try? NSRegularExpression(pattern: "地下(\\d+)層", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let range = Range(match.range(at: 1), in: trimmed),
           let num = Int(trimmed[range]) {
            return -num
        }
        return nil
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
                    Text(floorText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
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
