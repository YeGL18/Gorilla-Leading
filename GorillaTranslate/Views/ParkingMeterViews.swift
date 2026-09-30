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
    var pendingAppearance = true
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { "\(meter.street) \(meter.id)" }
    init(_ meter: ParkingMeter) {
        self.meter = meter
        coordinate = meter.coordinate.wgs84ToGCJ02
        super.init()
    }
}

final class MeterGroupAnnotation: NSObject, MKAnnotation {
    let meters: [ParkingMeter]
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ meters: [ParkingMeter]) {
        self.meters = meters
        let latitude = meters.reduce(0) { $0 + $1.latitude } / Double(meters.count)
        let longitude = meters.reduce(0) { $0 + $1.longitude } / Double(meters.count)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude).wgs84ToGCJ02
        title = meters[0].bayType.title
        subtitle = "\(meters.count) 個咪錶位"
        super.init()
    }
}

final class MeterAnnotationView: MKMarkerAnnotationView {
    @MainActor
    func configure(
        _ meters: [ParkingMeter],
        manager: ParkingMeterManager,
        clusteringEnabled: Bool = true
    ) {
        guard let first = meters.first else { return }
        let state = MeterDisplayState.cluster(meters.map { manager.state($0) })
        let isCluster = annotation is MKClusterAnnotation || annotation is MeterGroupAnnotation
        if let cluster = annotation as? MKClusterAnnotation {
            cluster.title = first.bayType.title
            cluster.subtitle = "\(meters.count) 個咪錶位"
        }
        markerTintColor = state.uiColor
        glyphTintColor = state == .incompatible ? .black : .white
        glyphText = isCluster ? "\(meters.count)" : "P"
        clusteringIdentifier = (isCluster || !clusteringEnabled) ? nil : "meter-\(first.bayType.rawValue)"
        titleVisibility = isCluster ? .adaptive : .visible
        subtitleVisibility = .hidden
        canShowCallout = false
        collisionMode = .circle
        displayPriority = .defaultHigh
        isAccessibilityElement = true
        accessibilityLabel = "\(first.bayType.title)，\(meters.count) 個泊位，\(state.title)"
    }
}

@MainActor
final class MeterMapLayer {
    private var annotations: [String: MeterAnnotation] = [:]
    private var lastRevision = -1
    private(set) var clusteringEnabled = true
    static func members(_ annotation: MKAnnotation?) -> [ParkingMeter] {
        if let meter = annotation as? MeterAnnotation { return [meter.meter] }
        if let group = annotation as? MeterGroupAnnotation { return group.meters }
        if let cluster = annotation as? MKClusterAnnotation {
            return cluster.memberAnnotations.compactMap { ($0 as? MeterAnnotation)?.meter }
        }
        return []
    }
    func sync(map: MKMapView, meters: [ParkingMeter], manager: ParkingMeterManager) {
        let wanted = Dictionary(uniqueKeysWithValues: meters.map { ($0.id, $0) })
        let removed = annotations.values.filter { wanted[$0.meter.id] != $0.meter }
        for item in removed {
            annotations.removeValue(forKey: item.meter.id)
            if let view = map.view(for: item) {
                UIView.animate(withDuration: 0.24, animations: {
                    view.alpha = 0
                }, completion: { [weak map] _ in
                    map?.removeAnnotation(item)
                })
            } else {
                map.removeAnnotation(item)
            }
        }
        let added = meters.filter { annotations[$0.id] == nil }.map(MeterAnnotation.init)
        for item in added { annotations[item.meter.id] = item }
        map.addAnnotations(added)
        if lastRevision != manager.revision || !removed.isEmpty || !added.isEmpty {
            for annotation in map.annotations {
                if let view = map.view(for: annotation) as? MeterAnnotationView {
                    view.configure(
                        Self.members(annotation),
                        manager: manager,
                        clusteringEnabled: clusteringEnabled
                    )
                }
            }
            lastRevision = manager.revision
        }
    }

    func containsTargetInCluster(map: MKMapView, targetID: String) -> Bool {
        map.annotations
            .compactMap { $0 as? MKClusterAnnotation }
            .contains { cluster in
                cluster.memberAnnotations.contains {
                    ($0 as? MeterAnnotation)?.meter.id == targetID
                }
            }
    }

    func setClusteringEnabled(_ enabled: Bool, map: MKMapView) {
        guard enabled != clusteringEnabled else { return }
        clusteringEnabled = enabled
        let meterAnnotations = Array(annotations.values)
        guard !meterAnnotations.isEmpty else { return }

        // Re-adding forces MapKit to rebuild its clusters with the new identifiers.
        map.removeAnnotations(meterAnnotations)
        map.addAnnotations(meterAnnotations)
    }

    static func view(
        map: MKMapView,
        annotation: MKAnnotation,
        manager: ParkingMeterManager,
        clusteringEnabled: Bool = true
    ) -> MKAnnotationView? {
        let meters = members(annotation)
        guard !meters.isEmpty else { return nil }
        let reuseID = annotation is MKClusterAnnotation || annotation is MeterGroupAnnotation
            ? "MeterCluster" : "MeterSingle"
        let view = (map.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MeterAnnotationView)
            ?? MeterAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        view.annotation = annotation
        view.configure(meters, manager: manager, clusteringEnabled: clusteringEnabled)
        let appearingMeters: [MeterAnnotation]
        if let meter = annotation as? MeterAnnotation {
            appearingMeters = meter.pendingAppearance ? [meter] : []
        } else if let cluster = annotation as? MKClusterAnnotation {
            appearingMeters = cluster.memberAnnotations.compactMap { $0 as? MeterAnnotation }
                .filter(\.pendingAppearance)
        } else {
            appearingMeters = []
        }
        if !appearingMeters.isEmpty {
            for meter in appearingMeters { meter.pendingAppearance = false }
            view.alpha = 0
            UIView.animate(withDuration: 0.28) { view.alpha = 1 }
        } else {
            view.alpha = 1
        }
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
    let onPay: () -> Void
    var horizontalLayout = false
    var compactLayout = false

    var body: some View {
        let state = manager.state(meter)
        Group {
            if horizontalLayout {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        capsuleHeader
                        statusBlock(state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    detailsBlock(state)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        actionButtons(vertical: true)
                    }
                    .frame(width: 160)
                }
            } else {
                VStack(spacing: compactLayout ? 8 : 12) {
                    capsuleHeader
                    statusBlock(state)
                    detailsBlock(state)
                    actionButtons(vertical: false)
                }
            }
        }
        .padding(compactLayout || horizontalLayout ? 14 : 20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: horizontalLayout ? 760 : 420)
        .padding(.horizontal, horizontalLayout ? 20 : 28)
    }

    private var capsuleHeader: some View {
        HStack {
            Text("\(meter.street) · \(meter.id)")
                .font(.headline)
                .lineLimit(horizontalLayout ? 2 : 1)
            Spacer(minLength: 8)
            Button {
                Task { await manager.refreshStatus(force: true) }
            } label: {
                if manager.statusRefreshing {
                    ProgressView().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.clockwise").frame(width: 20, height: 20)
                }
            }
            .disabled(manager.statusRefreshing)
            .accessibilityLabel("刷新佔用狀態")
            .help("刷新佔用狀態")
            .frame(width: 32, height: 32)
            Button(action: onClose) { Image(systemName: "xmark") }
                .accessibilityLabel("關閉")
                .frame(width: 32, height: 32)
        }
    }

    @ViewBuilder
    private func statusBlock(_ state: MeterDisplayState) -> some View {
        Text(state.title)
            .font(.system(size: horizontalLayout || compactLayout ? 22 : 25, weight: .bold))
            .foregroundStyle(state.color)
            .multilineTextAlignment(horizontalLayout ? .leading : .center)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.35), value: state)
        if manager.vehicle != .unset && !meter.bayType.accepts(manager.vehicle), state != .incompatible {
            Text(meter.bayType == .unknown ? "適用車型未知" : "不適用所選車型")
                .foregroundStyle(.yellow)
                .font(.subheadline.bold())
        }
        if let fetched = manager.lastStatusFetch {
            Text("更新於 \(fetched.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: fetched)
        }
        if let error = manager.errorMessage, error.hasPrefix("狀態") {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func detailsBlock(_ state: MeterDisplayState) -> some View {
        VStack(alignment: horizontalLayout ? .leading : .center, spacing: compactLayout || horizontalLayout ? 5 : 8) {
            Label(meter.bayType.title, systemImage: meter.bayType.symbol).font(.subheadline.bold())
            if meter.bayType == .general {
                Text(meter.bayType.detail).font(.caption).foregroundStyle(.secondary)
            }
            Text(meter.feeText).font(.headline)
            Text(meter.limitText).font(.subheadline)
            Text(meter.hoursText).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(horizontalLayout ? .leading : .center)
            Text("車型及泊車限制以現場標誌為準").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: horizontalLayout ? .leading : .center)
    }

    @ViewBuilder
    private func actionButtons(vertical: Bool) -> some View {
        if vertical {
            Button(action: onNavigate) {
                Label("導航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            Button(action: onPay) {
                Label("前往繳費", systemImage: "creditcard.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 33 / 255, green: 92 / 255, blue: 112 / 255))
        } else {
            HStack(spacing: 12) {
                Button(action: onNavigate) {
                    Label("導航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.glass)
                Button(action: onPay) {
                    Label("前往繳費", systemImage: "creditcard.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(Color(red: 33 / 255, green: 92 / 255, blue: 112 / 255))
            }
        }
    }
}

private struct MeterPopupBlurSlideModifier: ViewModifier {
    let blur: CGFloat
    let y: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: blur).offset(y: y).scaleEffect(scale)
    }
}

struct MeterDetailOverlay: View {
    let meter: ParkingMeter
    @ObservedObject var manager: ParkingMeterManager
    let onClose: () -> Void
    let onNavigate: () -> Void
    let onPay: () -> Void
    var compactLayout = false

    static var popupTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: MeterPopupBlurSlideModifier(blur: 28, y: 10, scale: 0.985),
                identity: MeterPopupBlurSlideModifier(blur: 0, y: 0, scale: 1)
            ),
            removal: .modifier(
                active: MeterPopupBlurSlideModifier(blur: 28, y: 0, scale: 0.985),
                identity: MeterPopupBlurSlideModifier(blur: 0, y: 0, scale: 1)
            )
        ).combined(with: .opacity)
    }

    var body: some View {
        GeometryReader { geo in
            let horizontal = geo.size.width > geo.size.height
            ZStack {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                MeterDetailCapsule(meter: meter, manager: manager,
                                   onClose: onClose, onNavigate: onNavigate, onPay: onPay,
                                   horizontalLayout: horizontal,
                                   compactLayout: compactLayout)
                    .padding(.vertical, horizontal ? 8 : 16)
                    .offset(y: horizontal ? 10 : (compactLayout ? 18 : 56))
            }
        }
    }
}

struct MeterNoticeCapsule: View {
    let notice: MeterNotice
    let onCancel: () -> Void
    let onAction: () -> Void
    let onPay: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(notice.title).font(.headline).multilineTextAlignment(.center)
            Text("\(notice.meter.street) · \(notice.meter.id)").font(.subheadline).foregroundStyle(.secondary)

            if notice.kind == .nearby {
                nearbyActions
            } else {
                HStack(spacing: 12) {
                    Button("取消", action: onCancel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.glass)
                    Button(action: onAction) {
                        Label(notice.actionTitle, systemImage: notice.actionSymbol)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 33 / 255, green: 92 / 255, blue: 112 / 255))
                }
            }
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: 420).padding(.horizontal, 24)
    }

    private var nearbyActions: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("關閉")

            Button(action: onPay) {
                Label("開入錶易", systemImage: "creditcard.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 33 / 255, green: 92 / 255, blue: 112 / 255))

            Button(action: onAction) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("導航")
            .accessibilityHint("開始行車路線去這個咪錶位")
        }
    }
}

@MainActor
enum MeterPayment {
    static let storeURL = URL(string: "https://apps.apple.com/hk/app/id1508101096")!
    static func open(manager: ParkingMeterManager) {
        manager.dismissNotice()
        // HKeMeter's launch scheme has been verified on a physical device.
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
            MeterTestMap(meters: filtered, revision: manager.revision, onSelect: { meter in
                withAnimation(.easeOut(duration: 0.28)) { selected = meter }
            })
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
        .overlay {
            if let meter = selected {
                MeterDetailOverlay(meter: meter, manager: manager,
                                   onClose: { dismissDetail() },
                                   onNavigate: {
                                       dismissDetail()
                                       MKMapItem(placemark: MKPlacemark(coordinate: meter.coordinate.wgs84ToGCJ02))
                                           .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                                   },
                                   onPay: {
                                       dismissDetail()
                                       MeterPayment.open(manager: manager)
                                   })
                    .transition(MeterDetailOverlay.popupTransition)
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
        .sheet(isPresented: $showSimulation) { MeterSimulationView() }
        .modifier(MeterPaymentHelp(manager: manager))
    }
    private func dismissDetail() {
        withAnimation(.easeIn(duration: 0.18)) { selected = nil }
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
        context.coordinator.update(map: map)
        if let center, let radius, context.coordinator.lastRadius != radius {
            map.removeOverlays(map.overlays)
            map.addOverlays([MKCircle(center: center, radius: radius), MKCircle(center: center, radius: radius * 2)])
            context.coordinator.lastRadius = radius
        }
    }
    class Coordinator: NSObject, MKMapViewDelegate {
        private struct GridKey: Hashable {
            let row: Int
            let column: Int
            let bayType: MeterBayType
        }

        var parent: MeterTestMap
        private var displayed: [MKAnnotation] = []
        private var meterIDs: [String] = []
        private var lastRevision = -1
        var lastRadius: Double?
        init(_ parent: MeterTestMap) { self.parent = parent }

        func update(map: MKMapView) {
            let ids = parent.meters.map(\.id)
            if ids != meterIDs {
                render(map: map, ids: ids)
            } else if parent.revision != lastRevision {
                refreshVisibleViews(map: map)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            render(map: mapView, ids: parent.meters.map(\.id))
        }

        private func render(map: MKMapView, ids: [String]) {
            let center = map.region.center.gcj02ToWGS84
            let span = map.region.span
            let latitudeMargin = span.latitudeDelta * 0.1 + 0.005
            let longitudeMargin = span.longitudeDelta * 0.1 + 0.005
            let minLatitude = center.latitude - span.latitudeDelta / 2 - latitudeMargin
            let maxLatitude = center.latitude + span.latitudeDelta / 2 + latitudeMargin
            let minLongitude = center.longitude - span.longitudeDelta / 2 - longitudeMargin
            let maxLongitude = center.longitude + span.longitudeDelta / 2 + longitudeMargin
            let visible = parent.meters.filter {
                (minLatitude...maxLatitude).contains($0.latitude)
                    && (minLongitude...maxLongitude).contains($0.longitude)
            }

            let next: [MKAnnotation]
            if visible.count <= 450 {
                next = visible.map { MeterAnnotation($0) as MKAnnotation }
            } else {
                let latitudeCell = max((maxLatitude - minLatitude) / 12, 0.0001)
                let longitudeCell = max((maxLongitude - minLongitude) / 12, 0.0001)
                let groups = Dictionary(grouping: visible) { meter in
                    GridKey(row: Int((meter.latitude - minLatitude) / latitudeCell),
                            column: Int((meter.longitude - minLongitude) / longitudeCell),
                            bayType: meter.bayType)
                }
                next = groups.values.map { group -> MKAnnotation in
                    group.count == 1 ? MeterAnnotation(group[0]) : MeterGroupAnnotation(group)
                }
            }

            map.removeAnnotations(displayed)
            displayed = next
            map.addAnnotations(next)
            meterIDs = ids
            lastRevision = parent.revision
        }

        private func refreshVisibleViews(map: MKMapView) {
            for annotation in displayed {
                if let view = map.view(for: annotation) as? MeterAnnotationView {
                    view.configure(MeterMapLayer.members(annotation), manager: .shared)
                }
            }
            lastRevision = parent.revision
        }

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
    @State private var index = MeterSpatialIndex([])
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
                MeterTestMap(meters: meters, revision: manager.revision, center: location.coordinate, radius: radius, onSelect: { meter in
                    withAnimation(.easeOut(duration: 0.28)) { selected = meter }
                })
                    .id(mapID)
            }
            .overlay {
                if let meter = selected {
                    MeterDetailOverlay(meter: meter, manager: manager,
                                       onClose: { dismissDetail() },
                                       onNavigate: {
                                           dismissDetail()
                                           MKMapItem(placemark: MKPlacemark(coordinate: meter.coordinate.wgs84ToGCJ02))
                                               .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                                       },
                                       onPay: {
                                           dismissDetail()
                                           MeterPayment.open(manager: manager)
                                       })
                        .transition(MeterDetailOverlay.popupTransition)
                }
            }
            .navigationTitle("範圍與速度模擬").navigationBarTitleDisplayMode(.inline)
            .onAppear { index = MeterSpatialIndex(manager.allMeters) }
            .onChange(of: manager.allMeters) { _, meters in index = MeterSpatialIndex(meters) }
            .onReceive(timer) { now in
                let candidates = index.nearby(location, radius: radius * 2)
                meters = visibility.update(candidates: candidates, location: location, speed: speed, radius: radius, now: now)
            }
            .modifier(MeterPaymentHelp(manager: manager))
        }
    }
    private func dismissDetail() {
        withAnimation(.easeIn(duration: 0.18)) { selected = nil }
    }
}
