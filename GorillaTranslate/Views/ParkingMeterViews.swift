import SwiftUI
import MapKit

extension MeterDisplayState {
    var uiColor: UIColor {
        switch self {
        case .vacant: return .systemGreen
        case .incompatible: return .systemYellow
        case .occupied: return .systemRed
        case .unknown: return .systemGray
        }
    }
    var color: Color { Color(uiColor: uiColor) }
}

final class MeterAnnotation: NSObject, MKAnnotation {
    let meter: ParkingMeter
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { "\(meter.street) \(meter.id)" }
    init(_ meter: ParkingMeter) {
        self.meter = meter
        coordinate = meter.coordinate.wgs84ToGCJ02
        super.init()
    }
}

final class MeterAnnotationView: MKAnnotationView {
    private let symbol = UIImageView()
    private let countLabel = UILabel()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 66, height: 36)
        layer.cornerRadius = 8
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        symbol.frame = CGRect(x: 7, y: 8, width: 22, height: 20)
        symbol.contentMode = .scaleAspectFit
        symbol.tintColor = .black
        countLabel.frame = CGRect(x: 31, y: 5, width: 29, height: 26)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        countLabel.textAlignment = .center
        countLabel.textColor = .black
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.6
        addSubview(symbol); addSubview(countLabel)
        canShowCallout = false
        collisionMode = .rectangle
        displayPriority = .defaultHigh
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @MainActor
    func configure(_ meters: [ParkingMeter], manager: ParkingMeterManager) {
        let state = MeterDisplayState.cluster(meters.map { manager.state($0) })
        backgroundColor = state.uiColor
        symbol.image = UIImage(systemName: meters.first?.bayType.symbol ?? "parkingsign")
        countLabel.text = "\(meters.count)"
        clusteringIdentifier = meters.first.map { "meter-\($0.bayType.rawValue)" }
        accessibilityLabel = "\(meters.first?.bayType.title ?? "咪錶")，\(meters.count) 個泊位，\(state.title)"
    }
}

@MainActor
final class MeterMapLayer {
    private var annotations: [String: MeterAnnotation] = [:]
    private var lastRevision = -1
    static func members(_ annotation: MKAnnotation?) -> [ParkingMeter] {
        if let meter = annotation as? MeterAnnotation { return [meter.meter] }
        if let cluster = annotation as? MKClusterAnnotation {
            return cluster.memberAnnotations.compactMap { ($0 as? MeterAnnotation)?.meter }
        }
        return []
    }
    func sync(map: MKMapView, meters: [ParkingMeter], manager: ParkingMeterManager) {
        let wanted = Dictionary(uniqueKeysWithValues: meters.map { ($0.id, $0) })
        let removed = annotations.values.filter { wanted[$0.meter.id] != $0.meter }
        map.removeAnnotations(removed)
        for item in removed { annotations.removeValue(forKey: item.meter.id) }
        let added = meters.filter { annotations[$0.id] == nil }.map(MeterAnnotation.init)
        for item in added { annotations[item.meter.id] = item }
        map.addAnnotations(added)
        if lastRevision != manager.revision || !removed.isEmpty || !added.isEmpty {
            for annotation in map.annotations {
                if let view = map.view(for: annotation) as? MeterAnnotationView {
                    view.configure(Self.members(annotation), manager: manager)
                }
            }
            lastRevision = manager.revision
        }
    }
    static func view(map: MKMapView, annotation: MKAnnotation, manager: ParkingMeterManager) -> MKAnnotationView? {
        let meters = members(annotation)
        guard !meters.isEmpty else { return nil }
        let view = (map.dequeueReusableAnnotationView(withIdentifier: "Meter") as? MeterAnnotationView)
            ?? MeterAnnotationView(annotation: annotation, reuseIdentifier: "Meter")
        view.annotation = annotation
        view.configure(meters, manager: manager)
        return view
    }
}

struct MeterSettingsSection: View {
    @AppStorage("meterDetectionEnabled") private var enabled = true
    @AppStorage("meterVehicle") private var vehicle = MeterVehicle.unset.rawValue
    @AppStorage("meterMapRadius") private var radius = 500.0
    @AppStorage("meterDestinationRadius") private var destinationRadius = 500.0
    @AppStorage("meterNearbyRadius") private var nearbyRadius = 100.0
    var body: some View {
        Section {
            Toggle("咪錶探測", isOn: $enabled)
            Picker("我駕駛的車型", selection: $vehicle) {
                ForEach(MeterVehicle.allCases) { Text($0.title).tag($0.rawValue) }
            }
            distanceSlider("地圖搜尋半徑", value: $radius, range: 100...800)
            LabeledContent("同街延伸上限", value: "\(Int(radius * 2)) 米")
            distanceSlider("目的地提示範圍", value: $destinationRadius, range: 50...800)
            distanceSlider("接近咪錶提示距離", value: $nearbyRadius, range: 10...200)
            NavigationLink("全港咪錶測試", destination: ParkingMeterTestView())
        } header: {
            Label("咪錶", systemImage: "parkingsign.circle")
        }
    }
    private func distanceSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: "\(Int(value.wrappedValue)) 米")
            Slider(value: value, in: range, step: 10).accessibilityLabel(title)
        }
    }
}

struct MeterVehiclePicker: View {
    @AppStorage("meterVehicle") private var vehicle = MeterVehicle.unset.rawValue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(MeterVehicle.allCases.filter { $0 != .unset }) { item in
                Button {
                    vehicle = item.rawValue
                    dismiss()
                } label: {
                    HStack {
                        Text(item.title)
                        Spacer()
                        if vehicle == item.rawValue { Image(systemName: "checkmark") }
                    }
                }
            }
            .navigationTitle("我駕駛的車型")
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

struct MeterDetailCapsule: View {
    let meter: ParkingMeter
    @ObservedObject var manager: ParkingMeterManager
    let onClose: () -> Void
    let onNavigate: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(meter.street) · \(meter.id)").font(.headline)
                Spacer(minLength: 8)
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityLabel("關閉").frame(width: 32, height: 32)
            }
            Text(manager.state(meter).title)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(manager.state(meter).color)
                .multilineTextAlignment(.center)
            if manager.vehicle != .unset && !meter.bayType.accepts(manager.vehicle), manager.state(meter) != .incompatible {
                Text(meter.bayType == .unknown ? "適用車型未知" : "不適用所選車型")
                    .foregroundStyle(.yellow).font(.subheadline.bold())
            }
            Label(meter.bayType.title, systemImage: meter.bayType.symbol).font(.subheadline.bold())
            if meter.bayType == .general {
                Text(meter.bayType.detail).font(.caption).foregroundStyle(.secondary)
            }
            Text(meter.feeText).font(.headline)
            Text(meter.limitText).font(.subheadline)
            Text(meter.hoursText).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("車型及泊車限制以現場標誌為準").font(.caption2).foregroundStyle(.secondary)
            if let fetched = manager.lastStatusFetch {
                Text("更新於 \(fetched.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button(action: onNavigate) {
                    Label("導航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.glass)
                Button { MeterPayment.open(manager: manager) } label: {
                    Label("前往繳費", systemImage: "creditcard.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(Color(red: 33 / 255, green: 92 / 255, blue: 112 / 255))
            }
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
    }
}

struct MeterNoticeCapsule: View {
    let notice: MeterNotice
    let onCancel: () -> Void
    let onAction: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text(notice.title).font(.headline).multilineTextAlignment(.center)
            Text("\(notice.meter.street) · \(notice.meter.id)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("取消", action: onCancel).frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.glass)
                Button(action: onAction) {
                    Label(notice.kind == .destination ? "前往咪錶位" : "前往繳費",
                          systemImage: notice.kind == .destination ? "arrow.triangle.turn.up.right.diamond.fill" : "creditcard.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(Color(red: 33 / 255, green: 92 / 255, blue: 112 / 255))
            }
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: 420).padding(.horizontal, 24)
    }
}

@MainActor
enum MeterPayment {
    static let storeURL = URL(string: "https://apps.apple.com/hk/app/id1508101096")!
    static func open(manager: ParkingMeterManager) {
        manager.dismissNotice()
        // Configure only a verified public launch URL. Do not guess a private payment scheme.
        guard let value = Bundle.main.object(forInfoDictionaryKey: "HKeMeterLaunchURL") as? String,
              let url = URL(string: value), !value.isEmpty else {
            manager.paymentHelpPresented = true
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { Task { @MainActor in manager.paymentHelpPresented = true } }
        }
    }
}

struct MeterPaymentHelp: ViewModifier {
    @ObservedObject var manager: ParkingMeterManager
    func body(content: Content) -> some View {
        content.alert("開啟入錶易", isPresented: $manager.paymentHelpPresented) {
            Button("前往 App Store") { UIApplication.shared.open(MeterPayment.storeURL) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("暫未能直接開啟入錶易。已安裝的話，請開啟入錶易繳費；未安裝可前往 App Store。")
        }
    }
}

struct ParkingMeterTestView: View {
    @ObservedObject private var manager = ParkingMeterManager.shared
    @State private var search = ""
    @State private var includeTest = false
    @State private var type = "all"
    @State private var selected: ParkingMeter?
    @State private var showSimulation = false
    @State private var filtered: [ParkingMeter] = []
    @AppStorage("meterVehicle") private var vehicle = MeterVehicle.unset.rawValue
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filtered.count) 個泊位").font(.subheadline.bold())
                Spacer()
                if manager.loading { ProgressView() }
                Button { Task { await manager.refreshSpaces(); await manager.refreshStatus(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.accessibilityLabel("重新載入")
            }.padding(.horizontal).padding(.vertical, 8)
            HStack {
                Picker("泊位類型", selection: $type) {
                    Text("全部車型").tag("all")
                    ForEach(MeterBayType.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Spacer()
                Toggle("測試咪錶", isOn: $includeTest).fixedSize()
            }.font(.caption).padding(.horizontal)
            MeterTestMap(meters: filtered, revision: manager.revision, onSelect: { selected = $0 })
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(MeterDisplayState.allCases, id: \.rawValue) { state in
                            Label { Text(state.title) } icon: { Circle().fill(state.color).frame(width: 9, height: 9) }
                        }
                    }.font(.caption).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(10)
                }
            if let error = manager.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
            if let date = manager.lastStatusFetch {
                Text("狀態更新 \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
        .navigationTitle("全港咪錶測試").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "車位編號、街道、地區")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSimulation = true } label: { Image(systemName: "speedometer") }.accessibilityLabel("範圍與速度模擬")
            }
        }
        .onAppear { manager.prepare(); manager.isTestPageActive = true; filter(); Task { await manager.refreshStatus() } }
        .onDisappear { manager.isTestPageActive = false }
        .onChange(of: manager.allMeters) { _, _ in filter() }
        .onChange(of: search) { _, _ in filter() }
        .onChange(of: type) { _, _ in filter() }
        .onChange(of: includeTest) { _, _ in filter() }
        .onChange(of: vehicle) { _, _ in manager.objectWillChange.send() }
        .sheet(item: $selected) { meter in
            MeterDetailCapsule(meter: meter, manager: manager, onClose: { selected = nil }, onNavigate: {
                MKMapItem(placemark: MKPlacemark(coordinate: meter.coordinate.wgs84ToGCJ02))
                    .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            })
            .presentationDetents([.medium, .large])
            .modifier(MeterPaymentHelp(manager: manager))
        }
        .sheet(isPresented: $showSimulation) { MeterSimulationView() }
    }
    private func filter() {
        filtered = manager.allMeters.filter {
            (includeTest || !$0.isTest) && (type == "all" || $0.bayType.rawValue == type)
                && (search.isEmpty || "\($0.id) \($0.street) \($0.district)".localizedCaseInsensitiveContains(search))
        }
    }
}

struct MeterTestMap: UIViewRepresentable {
    let meters: [ParkingMeter]
    let revision: Int
    var center: CLLocationCoordinate2D? = nil
    var radius: Double? = nil
    let onSelect: (ParkingMeter) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: center ?? CLLocationCoordinate2D(latitude: 22.34, longitude: 114.15),
                                        latitudinalMeters: center == nil ? 55000 : 2200, longitudinalMeters: center == nil ? 55000 : 2200), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.layer.sync(map: map, meters: meters, manager: .shared)
        if let center, let radius, context.coordinator.lastRadius != radius {
            map.removeOverlays(map.overlays)
            map.addOverlays([MKCircle(center: center, radius: radius), MKCircle(center: center, radius: radius * 2)])
            context.coordinator.lastRadius = radius
        }
    }
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MeterTestMap
        let layer = MeterMapLayer()
        var lastRadius: Double?
        init(_ parent: MeterTestMap) { self.parent = parent }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            MeterMapLayer.view(map: mapView, annotation: annotation, manager: .shared)
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let meter = ParkingMeterManager.shared.representative(MeterMapLayer.members(view.annotation)) {
                parent.onSelect(meter)
                if let annotation = view.annotation { mapView.deselectAnnotation(annotation, animated: false) }
            }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 1.5
            renderer.lineDashPattern = circle.radius == parent.radius ? nil : [5, 5]
            return renderer
        }
    }
}

struct MeterSimulationView: View {
    @ObservedObject private var manager = ParkingMeterManager.shared
    @State private var latitude = "22.3000"
    @State private var longitude = "114.1700"
    @State private var speed = 0.0
    @State private var radius = 500.0
    @State private var visibility = MeterVisibility()
    @State private var meters: [ParkingMeter] = []
    @State private var mapID = UUID()
    @State private var selected: ParkingMeter?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var location: CLLocation {
        CLLocation(latitude: Double(latitude) ?? 22.3, longitude: Double(longitude) ?? 114.17)
    }
    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    HStack {
                        TextField("緯度", text: $latitude).keyboardType(.decimalPad)
                        TextField("經度", text: $longitude).keyboardType(.decimalPad)
                        Button { mapID = UUID() } label: { Image(systemName: "location.fill") }.accessibilityLabel("移至座標")
                    }
                    LabeledContent("模擬速度", value: "\(Int(speed)) km/h")
                    Slider(value: $speed, in: 0...80, step: 1)
                    LabeledContent("搜尋半徑", value: "\(Int(radius)) 米")
                    Slider(value: $radius, in: 100...800, step: 10)
                    LabeledContent("速度穩定判斷", value: visibility.speedAllowsDisplay ? "顯示" : "隱藏")
                    LabeledContent("顯示泊位", value: "\(meters.count)")
                }.frame(height: 310)
                MeterTestMap(meters: meters, revision: manager.revision, center: location.coordinate, radius: radius, onSelect: { selected = $0 })
                    .id(mapID)
            }
            .navigationTitle("範圍與速度模擬").navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { now in
                let candidates = MeterSpatialIndex(manager.allMeters).nearby(location, radius: radius * 2)
                meters = visibility.update(candidates: candidates, location: location, speed: speed, radius: radius, now: now)
            }
            .sheet(item: $selected) { meter in
                MeterDetailCapsule(meter: meter, manager: manager, onClose: { selected = nil }, onNavigate: {
                    MKMapItem(placemark: MKPlacemark(coordinate: meter.coordinate.wgs84ToGCJ02))
                        .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                }).modifier(MeterPaymentHelp(manager: manager))
            }
        }
    }
}
