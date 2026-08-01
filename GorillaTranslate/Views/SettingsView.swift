import SwiftUI
import CoreLocation
import MapKit

struct SettingsView: View {
    @State private var simSpeed: Double = 0
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("highFrequencyTracking") var highFrequencyTracking: Bool = true
    @AppStorage("mapTrackingAnimation") var mapTrackingAnimation: Int = 0
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

                // Visit Events Section
                Section {
                    if locationManager.visits.isEmpty {
                        Text("No visits recorded yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(locationManager.visits.enumerated()), id: \.element.id) { index, visit in
                            VStack(spacing: 0) {
                                // Visit card
                                HStack(alignment: .top, spacing: 12) {
                                    // Transport icon circle
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.1))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: transportIcon(visit.transportType))
                                            .font(.system(size: 18))
                                            .foregroundStyle(.orange)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        // Address with orange dot
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(.orange)
                                                .frame(width: 8, height: 8)
                                            Text(visit.address)
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundStyle(.white)
                                        }

                                        // Time range
                                        HStack(spacing: 4) {
                                            Text(visit.arrivalDate, format: .dateTime.hour().minute())
                                                .font(.system(size: 15))
                                                .foregroundStyle(.white.opacity(0.6))
                                            Text("→")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.white.opacity(0.4))
                                            if visit.departureDate != nil {
                                                Text(visit.departureDate!, format: .dateTime.hour().minute())
                                                    .font(.system(size: 15))
                                                    .foregroundStyle(.white.opacity(0.6))
                                            } else {
                                                Text("Now")
                                                    .font(.system(size: 15))
                                                    .foregroundStyle(.white.opacity(0.6))
                                            }
                                        }
                                    }

                                    Spacer()

                                    // Duration badge
                                    Text(visit.duration)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(visit.departureDate == nil ? Color.white.opacity(0.3) : Color.clear, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                )

                                // Connector between visits
                                if index < locationManager.visits.count - 1 {
                                    visitConnector(from: locationManager.visits[index + 1], to: locationManager.visits[index])
                                }
                            }
                        }
                    }
                } header: {
                    Label("Visit Events", systemImage: "mappin.and.ellipse")
                } footer: {
                    if !locationManager.visits.isEmpty {
                        Button(role: .destructive) {
                            locationManager.clearVisits()
                        } label: {
                            Label("清除所有到訪記錄", systemImage: "trash")
                        }
                    }
                }

                // Speed Simulation Section
                Section {
                    DotMatrixView(speed: $simSpeed)
                        .frame(minHeight: 400)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Label("Speed Simulation", systemImage: "speedometer")
                }
            }
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 36)
            .listRowSpacing(0)
            .navigationTitle("Settings")
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

#Preview {
    SettingsView()
}
