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
                    Toggle(isOn: $sfxAccelerationEnabled) {
                        Label("加速音效", systemImage: "speaker.wave.2")
                    }
                    Text("關閉後，時速頁嘅「加速」提示聲會停用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Sound", systemImage: "speaker")
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
    @StateObject private var model = AltimeterModel()
    
    var body: some View {
        List {
            Section {
                Toggle("開始採集", isOn: $model.running)
                    .tint(.orange)
                
                HStack {
                    Text("採樣點數")
                    Spacer()
                    Text("\(model.samples.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("支援狀態")
                    Spacer()
                    Text(model.isAvailable ? "可用" : "裝置不支援")
                        .foregroundStyle(model.isAvailable ? .green : .red)
                }
                
                if !model.authStatus.isEmpty {
                    HStack {
                        Text("權限")
                        Spacer()
                        Text(model.authStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("採集控制", systemImage: "barometer")
            }
            
            Section {
                if let last = model.samples.last {
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
                            Text(last.pressure.map { String(format: "%.2f kPa", $0) } ?? "—")
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                        }
                        HStack {
                            Text("估計樓層變化")
                            Spacer()
                            Text(last.floorDelta.map { String(format: "%.1f 層", $0) } ?? "—")
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
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
                if model.samples.count >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("高度曲線")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(String(format: "min %.1f  max %.1f", model.altitudeMin, model.altitudeMax))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        AltitudeChartView(samples: model.samples,
                                         altitudeMin: model.altitudeMin,
                                         altitudeMax: model.altitudeMax)
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
                    model.clear()
                } label: {
                    Label("清除數據", systemImage: "trash")
                }
                .disabled(model.samples.isEmpty)
            }
        }
        .navigationTitle("氣壓計曲線測試")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            model.stop()
        }
    }
}

private struct AltitudeChartView: View {
    let samples: [AltimeterSample]
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

private struct AltimeterSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let relativeAltitude: Double
    let pressure: Double?
    let floorDelta: Double?
}

private final class AltimeterModel: ObservableObject {
    @Published var running = false {
        didSet {
            if running { start() } else { stop() }
        }
    }
    @Published private(set) var samples: [AltimeterSample] = []
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var authStatus: String = ""
    
    private let altimeter = CMAltimeter()
    private var isUpdating = false
    private var baseAltitude: Double?
    private static let metersPerFloorEstimate: Double = 3.0
    
    var altitudeMin: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map { $0.relativeAltitude }.min() ?? 0
    }
    
    var altitudeMax: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map { $0.relativeAltitude }.max() ?? 0
    }
    
    init() {
        isAvailable = CMAltimeter.isRelativeAltitudeAvailable()
        let status = CMAltimeter.authorizationStatus()
        switch status {
        case .notDetermined: authStatus = "未決定"
        case .restricted: authStatus = "限制"
        case .denied: authStatus = "拒絕"
        case .authorized: authStatus = "已授權"
        @unknown default: authStatus = "未知"
        }
    }
    
    func clear() {
        samples.removeAll()
        baseAltitude = nil
    }
    
    func start() {
        guard isAvailable else {
            running = false
            return
        }
        guard CMAltimeter.authorizationStatus() == .authorized else {
            running = false
            return
        }
        guard !isUpdating else { return }
        baseAltitude = nil
        isUpdating = true
        let opQueue = OperationQueue.main
        altimeter.startRelativeAltitudeUpdates(to: opQueue) { [weak self] data, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.authStatus = "錯誤: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data else { return }
            DispatchQueue.main.async {
                let rel = data.relativeAltitude.doubleValue
                let pressure = data.pressure.doubleValue
                var floorDelta: Double? = nil
                if let base = self.baseAltitude {
                    floorDelta = (rel - base) / Self.metersPerFloorEstimate
                } else {
                    self.baseAltitude = rel
                }
                let sample = AltimeterSample(timestamp: Date(),
                                            relativeAltitude: rel,
                                            pressure: pressure,
                                            floorDelta: floorDelta)
                self.samples.append(sample)
                if self.samples.count > 1200 { self.samples.removeFirst(self.samples.count - 1200) }
            }
        }
    }
    
    func stop() {
        if isUpdating {
            altimeter.stopRelativeAltitudeUpdates()
            isUpdating = false
        }
    }
    
    deinit {
        if isUpdating {
            altimeter.stopRelativeAltitudeUpdates()
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
                                    .glassEffect(.regular.tint(Color(hex: "46ADB8")), in: .capsule)
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
