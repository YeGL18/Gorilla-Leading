import SwiftUI
import MapKit

final class RoundedParkingBoundaryRenderer: MKPolygonRenderer {
    override func createPath() {
        let points = (0..<polygon.pointCount).map { point(for: polygon.points()[$0]) }
        guard points.count >= 3 else { return }
        let path = CGMutablePath()
        for i in points.indices {
            let previous = points[(i + points.count - 1) % points.count]
            let corner = points[i]
            let next = points[(i + 1) % points.count]
            let incoming = hypot(previous.x - corner.x, previous.y - corner.y)
            let outgoing = hypot(next.x - corner.x, next.y - corner.y)
            let rounding = min(incoming, outgoing) * 0.12
            let start = CGPoint(x: corner.x + (previous.x - corner.x) * rounding / max(1, incoming),
                                y: corner.y + (previous.y - corner.y) * rounding / max(1, incoming))
            let end = CGPoint(x: corner.x + (next.x - corner.x) * rounding / max(1, outgoing),
                              y: corner.y + (next.y - corner.y) * rounding / max(1, outgoing))
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: corner)
        }
        path.closeSubpath()
        self.path = path
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 8, color: UIColor.systemTeal.withAlphaComponent(0.35).cgColor)
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        context.restoreGState()
    }
}

struct ParkingBoundaryEditor: View {
    @ObservedObject var store: ParkingFloorStore
    let lot: ParkingLotRecord
    @Environment(\.dismiss) private var dismiss
    @State private var vertices: [ParkingBoundaryVertex]
    @State private var selectedID: UUID?
    @State private var showReset = false

    init(store: ParkingFloorStore, lot: ParkingLotRecord) {
        self.store = store
        self.lot = lot
        let radius = max(25, lot.radiusMeters) / sqrt(2)
        let latitude = radius / 111_000
        let longitude = latitude / max(0.2, cos(lot.centerLatitude * .pi / 180))
        let corners = [(-1.0, -1.0), (-1.0, 1.0), (1.0, 1.0), (1.0, -1.0)].map {
            ParkingBoundaryVertex(latitude: lot.centerLatitude + $0.0 * latitude,
                                  longitude: lot.centerLongitude + $0.1 * longitude)
        }
        _vertices = State(initialValue: lot.boundaryVertices ?? corners)
    }

    private var valid: Bool { ParkingBoundaryGeometry.isValid(vertices) }

    var body: some View {
        NavigationStack {
            BoundaryEditingMap(vertices: $vertices, selectedID: $selectedID, records: lot.points)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if !valid {
                            Text(String(localized: "範圍不可交叉或過小"))
                                .font(.caption).foregroundStyle(.red)
                        }
                        HStack(spacing: 16) {
                            Button(action: addVertex) { Image(systemName: "plus") }
                                .disabled(vertices.count >= 24)
                                .accessibilityLabel(String(localized: "新增頂點"))
                                .accessibilityIdentifier("boundaryAdd")
                            Text(String(format: String(localized: "%d 個頂點"), vertices.count))
                                .font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                                .monospacedDigit().contentTransition(.numericText())
                                .accessibilityIdentifier("boundaryCount")
                            Button {
                                guard let selectedID else { return }
                                vertices.removeAll { $0.id == selectedID }
                                self.selectedID = nil
                            } label: { Image(systemName: "minus") }
                                .disabled(vertices.count <= 3 || selectedID == nil)
                                .accessibilityLabel(String(localized: "移除頂點"))
                                .accessibilityIdentifier("boundaryRemove")
                            Button { showReset = true } label: { Image(systemName: "arrow.counterclockwise") }
                                .accessibilityLabel(String(localized: "恢復自動圓形範圍"))
                        }
                        .font(.title3).buttonStyle(.bordered).controlSize(.large)
                    }
                    .padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
                .navigationTitle(String(localized: "調整停車場範圍"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "取消")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "儲存")) {
                            if store.setBoundary(lotID: lot.id, vertices: vertices) { dismiss() }
                        }.disabled(!valid)
                    }
                }
                .confirmationDialog(String(localized: "恢復自動圓形範圍"), isPresented: $showReset,
                                    titleVisibility: .visible) {
                    Button(String(localized: "恢復")) {
                        if store.setBoundary(lotID: lot.id, vertices: nil) { dismiss() }
                    }
                    Button(String(localized: "取消"), role: .cancel) {}
                }
        }
    }

    private func addVertex() {
        guard vertices.count < 24 else { return }
        let index = selectedID.flatMap { id in vertices.firstIndex { $0.id == id } } ?? vertices.indices.max {
            CLLocation(latitude: vertices[$0].latitude, longitude: vertices[$0].longitude)
                .distance(from: CLLocation(latitude: vertices[($0 + 1) % vertices.count].latitude,
                                           longitude: vertices[($0 + 1) % vertices.count].longitude))
            < CLLocation(latitude: vertices[$1].latitude, longitude: vertices[$1].longitude)
                .distance(from: CLLocation(latitude: vertices[($1 + 1) % vertices.count].latitude,
                                           longitude: vertices[($1 + 1) % vertices.count].longitude))
        } ?? 0
        let a = vertices[index], b = vertices[(index + 1) % vertices.count]
        let vertex = ParkingBoundaryVertex(latitude: (a.latitude + b.latitude) / 2,
                                           longitude: (a.longitude + b.longitude) / 2)
        vertices.insert(vertex, at: index + 1)
        selectedID = vertex.id
    }
}

private final class BoundaryHandle: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ vertex: ParkingBoundaryVertex) {
        id = vertex.id
        coordinate = vertex.coordinate.wgs84ToGCJ02
    }
}

private struct BoundaryEditingMap: UIViewRepresentable {
    @Binding var vertices: [ParkingBoundaryVertex]
    @Binding var selectedID: UUID?
    let records: [ParkingPointRecord]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let drag = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dragVertex(_:)))
        drag.minimumPressDuration = 0.2
        drag.cancelsTouchesInView = false
        drag.delegate = context.coordinator
        map.addGestureRecognizer(drag)
        let coordinates = vertices.map { $0.coordinate.wgs84ToGCJ02 }
        let polygon = MKPolygon(coordinates: coordinates, count: coordinates.count)
        map.setVisibleMapRect(polygon.boundingMapRect,
                              edgePadding: UIEdgeInsets(top: 70, left: 60, bottom: 70, right: 60), animated: false)
        for record in records {
            let annotation = MKPointAnnotation()
            annotation.coordinate = record.coordinate.wgs84ToGCJ02
            map.addAnnotation(annotation)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard !coordinator.dragging else { return }
        let IDs = Set(vertices.map(\.id))
        let removed = coordinator.handles.filter { !IDs.contains($0.key) }
        map.removeAnnotations(Array(removed.values))
        for id in removed.keys { coordinator.handles[id] = nil }
        for vertex in vertices {
            if let handle = coordinator.handles[vertex.id] {
                handle.coordinate = vertex.coordinate.wgs84ToGCJ02
            } else {
                let handle = BoundaryHandle(vertex)
                coordinator.handles[vertex.id] = handle
                map.addAnnotation(handle)
            }
        }
        coordinator.updatePolygon(map)
        if let selectedID, let handle = coordinator.handles[selectedID],
           !map.selectedAnnotations.contains(where: { ($0 as? BoundaryHandle)?.id == selectedID }) {
            map.selectAnnotation(handle, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: BoundaryEditingMap
        var handles: [UUID: BoundaryHandle] = [:]
        var polygon: MKPolygon?
        var dragging = false
        private var draggedID: UUID?
        private var grabOffset = CGPoint.zero
        private var renderedVertices: [ParkingBoundaryVertex] = []
        init(_ parent: BoundaryEditingMap) { self.parent = parent }

        func updatePolygon(_ map: MKMapView) {
            guard renderedVertices != parent.vertices else { return }
            renderedVertices = parent.vertices
            if let polygon { map.removeOverlay(polygon) }
            let coordinates = parent.vertices.map { $0.coordinate.wgs84ToGCJ02 }
            let shape = MKPolygon(coordinates: coordinates, count: coordinates.count)
            polygon = shape
            map.addOverlay(shape)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let handle = annotation as? BoundaryHandle else {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "record")
                view.markerTintColor = .systemGray
                view.glyphImage = UIImage(systemName: "parkingsign")
                view.displayPriority = .defaultLow
                return view
            }
            let view = MKAnnotationView(annotation: handle, reuseIdentifier: "vertex")
            view.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
            view.backgroundColor = .systemBackground
            view.layer.cornerRadius = 14
            view.layer.borderWidth = 3
            view.layer.borderColor = UIColor.systemTeal.cgColor
            view.isDraggable = false
            view.canShowCallout = false
            view.displayPriority = .required
            view.accessibilityLabel = String(localized: "範圍頂點")
            view.accessibilityIdentifier = "boundaryVertex-\(handle.id)"
            view.isAccessibilityElement = true
            return view
        }

        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let handle = view.annotation as? BoundaryHandle else { return }
            view.backgroundColor = .systemTeal
            view.layer.borderColor = UIColor.systemBackground.cgColor
            DispatchQueue.main.async {
                guard self.parent.vertices.contains(where: { $0.id == handle.id }) else { return }
                self.parent.selectedID = handle.id
            }
        }

        func mapView(_ map: MKMapView, didDeselect view: MKAnnotationView) {
            guard view.annotation is BoundaryHandle else { return }
            view.backgroundColor = .systemBackground
            view.layer.borderColor = UIColor.systemTeal.cgColor
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let map = gesture.view as? MKMapView else { return false }
            return nearestHandle(to: touch.location(in: map), map: map) != nil
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool { gesture.numberOfTouches == 1 }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        private func nearestHandle(to point: CGPoint, map: MKMapView) -> BoundaryHandle? {
            handles.values.filter { handle in
                let anchor = map.convert(handle.coordinate, toPointTo: map)
                return hypot(anchor.x - point.x, anchor.y - point.y) < 30
            }.min {
                let a = map.convert($0.coordinate, toPointTo: map), b = map.convert($1.coordinate, toPointTo: map)
                return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
            }
        }

        @objc func dragVertex(_ gesture: UILongPressGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            switch gesture.state {
            case .began:
                guard let handle = nearestHandle(to: point, map: map) else { return }
                dragging = true
                draggedID = handle.id
                parent.selectedID = handle.id
                let anchor = map.convert(handle.coordinate, toPointTo: map)
                grabOffset = CGPoint(x: point.x - anchor.x, y: point.y - anchor.y)
                map.isScrollEnabled = false
                map.isZoomEnabled = false
                map.isRotateEnabled = false
                map.isPitchEnabled = false
            case .changed, .ended:
                if let id = draggedID, let handle = handles[id],
                   let index = parent.vertices.firstIndex(where: { $0.id == id }) {
                    handle.coordinate = map.convert(CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y),
                                                    toCoordinateFrom: map)
                    let coordinate = handle.coordinate.gcj02ToWGS84
                    parent.vertices[index].latitude = coordinate.latitude
                    parent.vertices[index].longitude = coordinate.longitude
                    updatePolygon(map)
                }
                if gesture.state == .ended { endDrag(map) }
            case .cancelled, .failed:
                endDrag(map)
            default: break
            }
        }

        private func endDrag(_ map: MKMapView) {
            dragging = false
            draggedID = nil
            map.isScrollEnabled = true
            map.isZoomEnabled = true
            map.isRotateEnabled = true
            map.isPitchEnabled = true
        }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = RoundedParkingBoundaryRenderer(polygon: polygon)
            renderer.strokeColor = (ParkingBoundaryGeometry.isValid(parent.vertices) ? UIColor.systemTeal : UIColor.systemRed)
                .withAlphaComponent(0.8)
            renderer.fillColor = UIColor.systemTeal.withAlphaComponent(0.06)
            renderer.lineWidth = 2
            return renderer
        }
    }
}

struct ParkingLotMergeView: View {
    @ObservedObject var store: ParkingFloorStore
    let sourceID: UUID
    var onMerge: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var target: ParkingLotRecord?
    @State private var showConfirmation = false
    private var source: ParkingLotRecord? { store.lots.first { $0.id == sourceID } }
    private var candidates: [ParkingLotRecord] {
        store.lots.filter {
            $0.id != sourceID && (query.isEmpty || ($0.preferredDisplayName ?? "").localizedStandardContains(query))
        }.sorted {
            $0.centerDistance(to: source?.centerCoordinate ?? $0.centerCoordinate)
                < $1.centerDistance(to: source?.centerCoordinate ?? $1.centerCoordinate)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { lot in
                        Button { target = lot; showConfirmation = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "parkingsign.circle").foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lot.preferredDisplayName ?? String(localized: "未命名"))
                                        .foregroundStyle(.primary)
                                    Text(String(format: String(localized: "%d 次記錄"), lot.points.count))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let source {
                                    Text("\(Int(lot.centerDistance(to: source.centerCoordinate))) m")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }.padding(.vertical, 4)
                        }.accessibilityIdentifier("mergeLot-\(lot.id)")
                    }
                } footer: {
                    Text(String(localized: "合併保留每次停車的位置、時間及樓層，並沿用所選停車場的名稱與自訂範圍。"))
                }
            }
            .navigationTitle(String(localized: "合併停車場"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: String(localized: "停車場"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
            }
            .alert(String(localized: "合併停車場"), isPresented: $showConfirmation) {
                Button(String(localized: "取消"), role: .cancel) { target = nil }
                Button(String(localized: "合併")) {
                    if let target, store.mergeLot(sourceID, into: target.id) {
                        onMerge()
                        dismiss()
                    }
                }
            } message: {
                Text(String(format: String(localized: "將「%@」的 %d 次記錄合併到「%@」？相同樓層的名稱以所選停車場為準。"),
                            source?.preferredDisplayName ?? String(localized: "未命名"), source?.points.count ?? 0,
                            target?.preferredDisplayName ?? String(localized: "未命名")))
            }
        }
    }
}
