import SwiftUI
import MapKit

/// 停車場範圍統一用嘅嫩綠（Apple 系統綠，淺色模式 #34C759）。
let parkingBoundaryGreen = UIColor.systemGreen

/// 圓角閉環路徑：每個角按兩邊長度嘅 12% 用 quad curve 削出圓弧。
/// 繪製預覽同最終展示共用同一個 builder，所以畫嗰陣見到嘅角
/// 就係之後喺地圖展示嘅角，唔會生硬轉角。
func boundaryRoundedLoopPath(_ points: [CGPoint]) -> CGMutablePath {
    let path = CGMutablePath()
    guard points.count >= 3 else {
        path.move(to: points.first ?? .zero)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
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
    return path
}

final class RoundedParkingBoundaryRenderer: MKPolygonRenderer {
    /// 彈出彈入進度用嘅縮放（0.72=收埋，1=完全彈出）。改咗即刻作廢舊路徑。
    var popScale: CGFloat = 1 {
        didSet { if popScale != oldValue { path = nil } }
    }

    override func createPath() {
        let raw = (0..<polygon.pointCount).map { point(for: polygon.points()[$0]) }
        guard raw.count >= 3 else { return }
        if popScale >= 0.999 {
            path = boundaryRoundedLoopPath(raw)
            return
        }
        // 彈出彈入：圍住形心縮放，條邊線跟住一齊彈
        let cx = raw.reduce(0) { $0 + $1.x } / CGFloat(raw.count)
        let cy = raw.reduce(0) { $0 + $1.y } / CGFloat(raw.count)
        let scaled = raw.map { CGPoint(x: cx + ($0.x - cx) * popScale, y: cy + ($0.y - cy) * popScale) }
        path = boundaryRoundedLoopPath(scaled)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 8, color: parkingBoundaryGreen.withAlphaComponent(0.35).cgColor)
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        context.restoreGState()
    }
}

// MARK: - 主地圖繪製停車場範圍（中心指針 + 逐點新增，參照影片交互）

/// 連接 SwiftUI 工具列與地圖：「加點」時讀取指針對準的座標；進入模式時設定一次性鏡頭目標。
final class BoundaryDrawMapBridge {
    /// 指針（地圖相機中心）目前對準的 WGS84 座標，由 MapView Coordinator 提供。
    var centerCoordinateProvider: (() -> CLLocationCoordinate2D?)?
    /// 進入繪製模式時的一次性鏡頭目標（GCJ02 顯示座標 + 距離，米）。用完即清空。
    var initialFocus: (coordinate: CLLocationCoordinate2D, distance: CLLocationDistance)?
}

/// 疊喺主地圖上嘅繪製圖層：已加頂點、即時橡皮筋、中心十字指針。
/// 用 UIView 直接畫，避免每移一下地圖就更新 SwiftUI 狀態。
final class BoundaryDrawCanvas: UIView {
    /// 已加頂點（GCJ02 顯示座標）。
    var vertices: [CLLocationCoordinate2D] = []
    /// 目前多邊形是否合法（三點以上先有意義）。
    var shapeIsValid = true
    weak var mapView: MKMapView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("BoundaryDrawCanvas must be created in code") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let mapView else { return }
        let points = vertices.map { mapView.convert($0, toPointTo: self) }
        let target = mapView.convert(mapView.centerCoordinate, toPointTo: self)
        let stroke: UIColor = (points.count >= 3 && !shapeIsValid) ? .systemRed : parkingBoundaryGreen

        // 即時預覽跟影片：指針係「假頂點」，兩點起連埋指針即成閉環範圍（第三點未加都睇到成個區域）。
        // 每個角都用 boundaryRoundedLoopPath 削圓弧——同最終地圖展示一致。
        if points.count >= 2 {
            let path = UIBezierPath(cgPath: boundaryRoundedLoopPath(points + [target]))
            stroke.withAlphaComponent(0.14).setFill()
            path.fill()
            stroke.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 2.5
            path.lineJoinStyle = .round
            path.stroke()
        } else if points.count == 1 {
            // 一點：拉住一條邊去指針
            let path = UIBezierPath()
            path.move(to: points[0])
            path.addLine(to: target)
            stroke.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 2.5
            path.lineCapStyle = .round
            path.stroke()
        }

        drawCrosshair(at: target, in: context)
    }

    /// 中心十字指針：白色底描邊確保深淺地圖上都清晰。
    private func drawCrosshair(at center: CGPoint, in context: CGContext) {
        let gap: CGFloat = 4
        let arm: CGFloat = 14
        for (width, color) in [(4.0, UIColor.white.withAlphaComponent(0.9)), (1.8, UIColor.label)] {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            for offset in [-arm, gap] {
                context.move(to: CGPoint(x: center.x + offset, y: center.y))
                context.addLine(to: CGPoint(x: center.x + (offset < 0 ? -gap : arm), y: center.y))
                context.move(to: CGPoint(x: center.x, y: center.y + offset))
                context.addLine(to: CGPoint(x: center.x, y: center.y + (offset < 0 ? -gap : arm)))
            }
            context.strokePath()
        }
    }
}

/// 繪製模式底部工具列：✕ 取消 │ ↩ 復原 │ 標題 │ ⊕ 加點 │ ✓ 完成。
/// 復原掣放喺標題左手邊（跟影片版面）。
struct BoundaryDrawToolbar: View {
    var vertexCount: Int
    var canConfirm: Bool
    var onCancel: () -> Void
    var onUndo: () -> Void
    var onAdd: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(String(localized: "取消"))
            .accessibilityIdentifier("boundaryDrawCancel")

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .disabled(vertexCount == 0)
            .accessibilityLabel(String(localized: "復原"))
            .accessibilityIdentifier("boundaryDrawUndo")

            Spacer(minLength: 4)

            Text(String(localized: "繪製停車場範圍"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("boundaryDrawTitle")

            Spacer(minLength: 4)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .disabled(vertexCount >= 24)
            .accessibilityLabel(String(localized: "加點"))
            .accessibilityIdentifier("boundaryDrawAdd")

            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(canConfirm ? Color.accentColor : Color.secondary.opacity(0.35)))
            }
            .disabled(!canConfirm)
            .accessibilityLabel(String(localized: "完成"))
            .accessibilityIdentifier("boundaryDrawConfirm")
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Capsule().fill(.regularMaterial))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 16)
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
            renderer.strokeColor = (ParkingBoundaryGeometry.isValid(parent.vertices) ? parkingBoundaryGreen : UIColor.systemRed)
                .withAlphaComponent(0.8)
            renderer.fillColor = parkingBoundaryGreen.withAlphaComponent(0.06)
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
