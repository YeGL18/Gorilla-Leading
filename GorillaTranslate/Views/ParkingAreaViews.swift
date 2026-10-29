import SwiftUI
import MapKit

/// 停車場範圍統一用嘅嫩綠（Apple 系統綠，淺色模式 #34C759）。
let parkingBoundaryGreen = UIColor.systemGreen

/// 圓角閉環路徑：每個角按兩邊長度嘅 12% 用 quad curve 削出圓弧。
/// 繪製預覽同最終展示共用同一個 builder，所以畫嗰陣見到嘅角
/// 就係之後喺地圖展示嘅角，唔會生硬轉角。
func boundaryRoundedCorner(_ points: [CGPoint], at index: Int) -> (start: CGPoint, control: CGPoint, end: CGPoint) {
    let previous = points[(index + points.count - 1) % points.count]
    let corner = points[index]
    let next = points[(index + 1) % points.count]
    let incoming = hypot(previous.x - corner.x, previous.y - corner.y)
    let outgoing = hypot(next.x - corner.x, next.y - corner.y)
    let rounding = min(incoming, outgoing) * 0.12
    return (
        CGPoint(x: corner.x + (previous.x - corner.x) * rounding / max(1, incoming),
                y: corner.y + (previous.y - corner.y) * rounding / max(1, incoming)),
        corner,
        CGPoint(x: corner.x + (next.x - corner.x) * rounding / max(1, outgoing),
                y: corner.y + (next.y - corner.y) * rounding / max(1, outgoing))
    )
}

func boundaryRoundedLoopPath(_ points: [CGPoint]) -> CGMutablePath {
    let path = CGMutablePath()
    guard points.count >= 3 else {
        path.move(to: points.first ?? .zero)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
    for i in points.indices {
        let corner = boundaryRoundedCorner(points, at: i)
        if i == 0 { path.move(to: corner.start) } else { path.addLine(to: corner.start) }
        path.addQuadCurve(to: corner.end, control: corner.control)
    }
    path.closeSubpath()
    return path
}

func boundaryEdgeHit(_ points: [CGPoint], near touch: CGPoint) -> (index: Int, point: CGPoint)? {
    guard points.count >= 3 else { return nil }
    var nearest: (index: Int, point: CGPoint, distance: CGFloat)?
    for index in points.indices {
        let start = boundaryRoundedCorner(points, at: index).end
        let end = boundaryRoundedCorner(points, at: (index + 1) % points.count).start
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1 else { continue }
        let t = min(1, max(0, ((touch.x - start.x) * dx + (touch.y - start.y) * dy) / lengthSquared))
        let point = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        let distance = hypot(point.x - touch.x, point.y - touch.y)
        if distance <= 18, nearest == nil || distance < nearest!.distance {
            nearest = (index, point, distance)
        }
    }
    return nearest.map { ($0.index, $0.point) }
}

final class RoundedParkingBoundaryRenderer: MKPolygonRenderer {
    override func createPath() {
        let points = (0..<polygon.pointCount).map { point(for: polygon.points()[$0]) }
        guard points.count >= 3 else { return }
        path = boundaryRoundedLoopPath(points)
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
final class BoundaryDrawMapBridge: ObservableObject {
    @Published var isReady = false
    @Published var isDraggingVertex = false
    /// 每次進入／取消換一個識別碼，舊鏡頭動畫不能重新開放操作。
    var sessionID = UUID()

    func reset() {
        sessionID = UUID()
        isReady = false
        isDraggingVertex = false
        centerCoordinateProvider = nil
        onVertexMove = nil
        onVertexInsert = nil
    }
    /// 指針（地圖相機中心）目前對準的 WGS84 座標，由 MapView Coordinator 提供。
    var centerCoordinateProvider: (() -> CLLocationCoordinate2D?)?
    /// 放手後提交移動的頂點（WGS84）；未按完成前只修改本次草稿。
    var onVertexMove: ((Int, CLLocationCoordinate2D) -> Void)?
    var onVertexInsert: ((Int, CLLocationCoordinate2D) -> Void)?
    /// 進入繪製模式時的一次性鏡頭目標（GCJ02 顯示座標 + 距離，米）。用完即清空。
    var initialFocus: (coordinate: CLLocationCoordinate2D, distance: CLLocationDistance)?
}

enum BoundaryDrawAppearance {
    static let duration: TimeInterval = 0.38
    static var animation: Animation { .easeInOut(duration: duration) }
}

/// 疊喺主地圖上嘅繪製圖層：已加頂點、即時橡皮筋、中心十字指針。
/// 用 UIView 直接畫，避免每移一下地圖就更新 SwiftUI 狀態。
final class BoundaryDrawCanvas: UIView, UIGestureRecognizerDelegate {
    /// 已加頂點（GCJ02 顯示座標）。
    var vertices: [CLLocationCoordinate2D] = []
    /// 目前多邊形是否合法（三點以上先有意義）。
    var shapeIsValid = true
    weak var mapView: MKMapView?
    var onVertexMove: ((Int, CLLocationCoordinate2D) -> Void)?
    var onVertexInsert: ((Int, CLLocationCoordinate2D) -> Void)?
    var onVertexDragChanged: ((Bool) -> Void)?
    private var draggedVertex: Int?
    private var dragStartPoint = CGPoint.zero
    private var dragStartCoordinate: CLLocationCoordinate2D?
    private var savedGestures: (scroll: Bool, zoom: Bool, pitch: Bool, rotate: Bool)?
    private var pressedVertex: Int?
    private var cornerPressProgress: [Int: CGFloat] = [:]
    private var cornerFeedbackTimer: Timer?
    private var insertedVertex: Int?
    private var edgeDragTouchAnchor = CGPoint.zero
    private let edgeFeedback = CAShapeLayer()
    private let insertedPoint = CAShapeLayer()
    var isDraggingVertex: Bool { draggedVertex != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        alpha = 0
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragVertex(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(insertVertex(_:)))
        hold.minimumPressDuration = 0.55
        hold.allowableMovement = 14
        hold.cancelsTouchesInView = false
        hold.delegate = self
        addGestureRecognizer(hold)
        edgeFeedback.fillColor = nil
        edgeFeedback.strokeColor = parkingBoundaryGreen.cgColor
        edgeFeedback.lineCap = .round
        edgeFeedback.opacity = 0
        layer.addSublayer(edgeFeedback)
        insertedPoint.path = UIBezierPath(ovalIn: CGRect(x: -4.5, y: -4.5, width: 9, height: 9)).cgPath
        insertedPoint.fillColor = UIColor.white.cgColor
        insertedPoint.shadowColor = UIColor.black.cgColor
        insertedPoint.shadowOpacity = 0.2
        insertedPoint.shadowRadius = 3
        insertedPoint.opacity = 0
        layer.addSublayer(insertedPoint)
    }

    required init?(coder: NSCoder) { fatalError("BoundaryDrawCanvas must be created in code") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first {
            let point = touch.location(in: self)
            let vertex = nearestVertex(to: point)
            setPressedVertex(vertex)
            if vertex == nil, vertices.count < 24, let edge = boundaryEdgeHit(screenPoints, near: point) {
                showEdgeFeedback(edge.index)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        setPressedVertex(nil)
        clearEdgeFeedback()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if !isDraggingVertex { setPressedVertex(nil); clearEdgeFeedback() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cornerFeedbackTimer?.invalidate()
            cornerFeedbackTimer = nil
            pressedVertex = nil
            cornerPressProgress.removeAll()
            clearEdgeFeedback()
        }
    }

    private func setPressedVertex(_ index: Int?) {
        guard pressedVertex != index else { return }
        pressedVertex = index
        cornerFeedbackTimer?.invalidate()
        let start = cornerPressProgress
        let indices = Set(start.keys).union(index.map { [$0] } ?? [])
        let startedAt = CACurrentMediaTime()
        let duration = index == nil ? 0.32 : 0.22
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - startedAt) / duration)
            let progress = CGFloat(1 - pow(1 - t, 3))
            for vertex in indices {
                let from = start[vertex] ?? 0
                let target: CGFloat = vertex == index ? 1 : 0
                self.cornerPressProgress[vertex] = from + (target - from) * progress
            }
            self.setNeedsDisplay()
            if t >= 1 {
                timer.invalidate()
                self.cornerFeedbackTimer = nil
                self.cornerPressProgress = self.cornerPressProgress.filter { $0.value > 0 }
            }
        }
        cornerFeedbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private var screenPoints: [CGPoint] {
        guard let mapView else { return [] }
        return vertices.map { mapView.convert($0, toPointTo: self) }
    }

    private func nearestVertex(to touch: CGPoint) -> Int? {
        let points = screenPoints
        let candidates = points.indices.map { index -> (Int, CGFloat) in
            var distance = hypot(points[index].x - touch.x, points[index].y - touch.y)
            if points.count >= 3 {
                let corner = boundaryRoundedCorner(points, at: index)
                for step in 0...8 {
                    let t = CGFloat(step) / 8, u = 1 - t
                    let x = u * u * corner.start.x + 2 * u * t * corner.control.x + t * t * corner.end.x
                    let y = u * u * corner.start.y + 2 * u * t * corner.control.y + t * t * corner.end.y
                    distance = min(distance, hypot(x - touch.x, y - touch.y))
                }
            }
            return (index, distance)
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 <= 30 else { return nil }
        return nearest.0
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        isDraggingVertex || nearestVertex(to: point) != nil ||
            (vertices.count < 24 && boundaryEdgeHit(screenPoints, near: point) != nil)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizerShouldBeginAtTouch(gestureRecognizer, point: gestureRecognizer.location(in: self))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        gestureRecognizerShouldBeginAtTouch(gestureRecognizer, point: touch.location(in: self))
    }

    private func gestureRecognizerShouldBeginAtTouch(_ gestureRecognizer: UIGestureRecognizer, point: CGPoint) -> Bool {
        if gestureRecognizer is UILongPressGestureRecognizer {
            return vertices.count < 24 && nearestVertex(to: point) == nil && boundaryEdgeHit(screenPoints, near: point) != nil
        }
        return nearestVertex(to: point) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer.view !== self
    }

    private func showEdgeFeedback(_ index: Int) {
        let points = screenPoints
        guard points.indices.contains(index) else { return }
        let path = UIBezierPath()
        path.move(to: boundaryRoundedCorner(points, at: index).end)
        path.addLine(to: boundaryRoundedCorner(points, at: (index + 1) % points.count).start)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFeedback.removeAllAnimations()
        edgeFeedback.path = path.cgPath
        edgeFeedback.opacity = 0.9
        edgeFeedback.lineWidth = 5
        CATransaction.commit()
        let grow = CABasicAnimation(keyPath: "lineWidth")
        grow.fromValue = 2.5
        grow.toValue = 5
        grow.duration = 0.55
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        edgeFeedback.add(grow, forKey: "hold")
    }

    private func clearEdgeFeedback() {
        edgeFeedback.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        edgeFeedback.opacity = 0
        CATransaction.commit()
    }

    private func lockMapForVertexDrag(_ mapView: MKMapView) {
        savedGestures = (mapView.isScrollEnabled, mapView.isZoomEnabled, mapView.isPitchEnabled, mapView.isRotateEnabled)
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        onVertexDragChanged?(true)
    }

    @objc private func insertVertex(_ hold: UILongPressGestureRecognizer) {
        guard let mapView else { return }
        switch hold.state {
        case .began:
            guard vertices.count < 24, let edge = boundaryEdgeHit(screenPoints, near: hold.location(in: self)) else { return }
            let index = edge.index + 1
            let coordinate = mapView.convert(edge.point, toCoordinateFrom: self)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            clearEdgeFeedback()
            cornerFeedbackTimer?.invalidate()
            cornerPressProgress.removeAll()
            pressedVertex = nil
            vertices.insert(coordinate, at: index)
            insertedVertex = index
            draggedVertex = index
            dragStartPoint = edge.point
            edgeDragTouchAnchor = hold.location(in: self)
            lockMapForVertexDrag(mapView)
            setPressedVertex(index)
            updateShapeValidity()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            insertedPoint.removeAllAnimations()
            insertedPoint.position = edge.point
            insertedPoint.opacity = 1
            CATransaction.commit()
            let grow = CASpringAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.01
            grow.toValue = 1
            grow.damping = 14
            grow.stiffness = 240
            grow.duration = 0.3
            insertedPoint.add(grow, forKey: "birth")
            AppHaptics.play(.longPress)
            setNeedsDisplay()
        case .changed, .ended:
            guard let index = insertedVertex, vertices.indices.contains(index) else { return }
            let touch = hold.location(in: self)
            let point = CGPoint(x: dragStartPoint.x + touch.x - edgeDragTouchAnchor.x,
                                y: dragStartPoint.y + touch.y - edgeDragTouchAnchor.y)
            let coordinate = mapView.convert(point, toCoordinateFrom: self)
            guard CLLocationCoordinate2DIsValid(coordinate) else { cancelVertexDrag(); return }
            vertices[index] = coordinate
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            insertedPoint.position = point
            CATransaction.commit()
            updateShapeValidity()
            setNeedsDisplay()
            if hold.state == .ended {
                onVertexInsert?(index, coordinate)
                finishVertexDrag()
                AppHaptics.play(.selection)
            }
        case .cancelled, .failed:
            clearEdgeFeedback()
            if insertedVertex != nil { cancelVertexDrag() }
        default: break
        }
    }

    @objc private func dragVertex(_ pan: UIPanGestureRecognizer) {
        guard let mapView else { return }
        switch pan.state {
        case .began:
            guard let index = nearestVertex(to: pan.location(in: self)) else { return }
            draggedVertex = index
            setPressedVertex(index)
            dragStartCoordinate = vertices[index]
            dragStartPoint = mapView.convert(vertices[index], toPointTo: self)
            lockMapForVertexDrag(mapView)
            fallthrough
        case .changed, .ended:
            guard let index = draggedVertex, vertices.indices.contains(index) else { return }
            let offset = pan.translation(in: self)
            let coordinate = mapView.convert(CGPoint(x: dragStartPoint.x + offset.x, y: dragStartPoint.y + offset.y),
                                             toCoordinateFrom: self)
            guard CLLocationCoordinate2DIsValid(coordinate) else { cancelVertexDrag(); return }
            vertices[index] = coordinate
            updateShapeValidity()
            setNeedsDisplay()
            if pan.state == .ended {
                onVertexMove?(index, coordinate)
                finishVertexDrag()
            }
        case .cancelled, .failed:
            cancelVertexDrag()
        default: break
        }
    }

    func cancelVertexDrag() {
        if let index = insertedVertex, vertices.indices.contains(index) {
            vertices.remove(at: index)
            cornerPressProgress.removeValue(forKey: index)
            updateShapeValidity()
        } else if let index = draggedVertex, vertices.indices.contains(index), let dragStartCoordinate {
            vertices[index] = dragStartCoordinate
            updateShapeValidity()
        }
        finishVertexDrag()
        setNeedsDisplay()
    }

    private func updateShapeValidity() {
        shapeIsValid = ParkingBoundaryGeometry.isValid(vertices.map {
            let wgs = $0.gcj02ToWGS84
            return ParkingBoundaryVertex(latitude: wgs.latitude, longitude: wgs.longitude)
        })
    }

    private func finishVertexDrag() {
        let wasDragging = isDraggingVertex
        if let savedGestures, let mapView {
            mapView.isScrollEnabled = savedGestures.scroll
            mapView.isZoomEnabled = savedGestures.zoom
            mapView.isPitchEnabled = savedGestures.pitch
            mapView.isRotateEnabled = savedGestures.rotate
        }
        savedGestures = nil
        draggedVertex = nil
        insertedVertex = nil
        dragStartCoordinate = nil
        setPressedVertex(nil)
        clearEdgeFeedback()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        insertedPoint.opacity = 0
        CATransaction.commit()
        if wasDragging { onVertexDragChanged?(false) }
    }

    /// 鏡頭到位後以透明度顯示，不改變指針或範圍大小。
    func reveal() {
        UIView.animate(withDuration: BoundaryDrawAppearance.duration, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 1
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let mapView else { return }
        let points = screenPoints
        let target = mapView.convert(mapView.centerCoordinate, toPointTo: self)
        let stroke: UIColor = (points.count >= 3 && !shapeIsValid) ? .systemRed : parkingBoundaryGreen

        // 三點後顯示實際範圍，新增點的預覽另用虛線，避免拖角時出現假的中心頂點。
        if points.count >= 2 {
            let path = UIBezierPath(cgPath: boundaryRoundedLoopPath(points.count == 2 ? points + [target] : points))
            stroke.withAlphaComponent(0.14).setFill()
            path.fill()
            stroke.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 2.5
            path.lineJoinStyle = .round
            path.stroke()
            if points.count >= 3 && !isDraggingVertex {
                let preview = UIBezierPath()
                preview.move(to: points.last!)
                preview.addLine(to: target)
                preview.addLine(to: points[0])
                stroke.withAlphaComponent(0.45).setStroke()
                preview.lineWidth = 1.5
                preview.setLineDash([4, 5], count: 2, phase: 0)
                preview.stroke()
            }
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

        if points.count >= 3 {
            let area = points.indices.reduce(CGFloat.zero) { sum, i in
                let next = points[(i + 1) % points.count]
                return sum + points[i].x * next.y - next.x * points[i].y
            }
            for index in points.indices {
                let corner = boundaryRoundedCorner(points, at: index)
                let previous = points[(index + points.count - 1) % points.count]
                let next = points[(index + 1) % points.count]
                let incoming = CGPoint(x: points[index].x - previous.x, y: points[index].y - previous.y)
                let outgoing = CGPoint(x: next.x - points[index].x, y: next.y - points[index].y)
                let a = max(1, hypot(incoming.x, incoming.y)), b = max(1, hypot(outgoing.x, outgoing.y))
                // Offset along each curve normal: the outer arc gains radius as well as clearance.
                let distance: CGFloat = area >= 0 ? 8 : -8
                func outerPoint(_ t: CGFloat) -> CGPoint {
                    let u = 1 - t
                    let point = CGPoint(
                        x: u * u * corner.start.x + 2 * u * t * corner.control.x + t * t * corner.end.x,
                        y: u * u * corner.start.y + 2 * u * t * corner.control.y + t * t * corner.end.y)
                    let tangent = CGPoint(
                        x: u * (corner.control.x - corner.start.x) + t * (corner.end.x - corner.control.x),
                        y: u * (corner.control.y - corner.start.y) + t * (corner.end.y - corner.control.y))
                    let length = max(0.01, hypot(tangent.x, tangent.y))
                    return CGPoint(x: point.x + tangent.y / length * distance,
                                   y: point.y - tangent.x / length * distance)
                }
                let press = cornerPressProgress[index] ?? 0
                let extensionLength = 3 * press
                let start = outerPoint(0)
                let end = outerPoint(1)
                let arc = UIBezierPath()
                arc.move(to: CGPoint(x: start.x - incoming.x / a * extensionLength,
                                     y: start.y - incoming.y / a * extensionLength))
                arc.addLine(to: start)
                for step in 1...24 { arc.addLine(to: outerPoint(CGFloat(step) / 24)) }
                arc.addLine(to: CGPoint(x: end.x + outgoing.x / b * extensionLength,
                                       y: end.y + outgoing.y / b * extensionLength))
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 5,
                                  color: UIColor.black.withAlphaComponent(0.3).cgColor)
                UIColor.white.withAlphaComponent(0.95 + 0.05 * press).setStroke()
                arc.lineWidth = 4.2 - 0.8 * press
                arc.lineCapStyle = .round
                arc.lineJoinStyle = .round
                arc.stroke()
                context.restoreGState()
            }
        }
        if !isDraggingVertex { drawCrosshair(at: target, in: context) }
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
private struct BoundaryToolbarPressStyle: ButtonStyle {
    var tapPulse: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || tapPulse
        return configuration.label
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.8 : 1)
            .animation(pressed ? .easeOut(duration: 0.07) : .spring(response: 0.28, dampingFraction: 0.72), value: pressed)
    }
}

private struct BoundaryToolbarButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @Environment(\.isEnabled) private var isEnabled
    @State private var tapPulse = false
    @State private var pendingAction: DispatchWorkItem?

    var body: some View {
        Button {
            guard isEnabled, pendingAction == nil else { return }
            tapPulse = true
            // Even a quick tap finishes its downstroke before an action can remove the toolbar.
            let work = DispatchWorkItem {
                pendingAction = nil
                tapPulse = false
                action()
            }
            pendingAction = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } label: {
            label()
        }
        .buttonStyle(BoundaryToolbarPressStyle(tapPulse: tapPulse))
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { cancelPendingAction() }
        }
        .onDisappear { cancelPendingAction() }
    }

    private func cancelPendingAction() {
        pendingAction?.cancel()
        pendingAction = nil
        tapPulse = false
    }
}

struct BoundaryDrawToolbar: View {
    var vertexCount: Int
    var canConfirm: Bool
    var editingEnabled = true
    var onCancel: () -> Void
    var onUndo: () -> Void
    var onAdd: () -> Void
    var onConfirm: () -> Void

    private var undoEnabled: Bool { editingEnabled && vertexCount > 0 }
    private var addEnabled: Bool { editingEnabled && vertexCount < 24 }
    private var confirmEnabled: Bool { editingEnabled && canConfirm }

    var body: some View {
        HStack(spacing: 8) {
            BoundaryToolbarButton(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(String(localized: "取消"))
            .accessibilityIdentifier("boundaryDrawCancel")

            BoundaryToolbarButton(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(undoEnabled ? Color.primary : Color.secondary)
                    .frame(width: 32, height: 32)
            }
            .disabled(!undoEnabled)
            .accessibilityLabel(String(localized: "復原"))
            .accessibilityIdentifier("boundaryDrawUndo")

            Spacer(minLength: 4)

            Text(String(localized: "繪製停車場範圍"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("boundaryDrawTitle")

            Spacer(minLength: 4)

            BoundaryToolbarButton(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(addEnabled ? Color.primary : Color.secondary)
                    .frame(width: 32, height: 32)
            }
            .disabled(!addEnabled)
            .accessibilityLabel(String(localized: "加點"))
            .accessibilityIdentifier("boundaryDrawAdd")

            BoundaryToolbarButton(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(uiColor: parkingBoundaryGreen)))
                    .opacity(confirmEnabled ? 1 : 0.35)
            }
            .disabled(!confirmEnabled)
            .accessibilityLabel(String(localized: "完成"))
            .accessibilityIdentifier("boundaryDrawConfirm")
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .animation(BoundaryDrawAppearance.animation, value: undoEnabled)
        .animation(BoundaryDrawAppearance.animation, value: addEnabled)
        .animation(BoundaryDrawAppearance.animation, value: confirmEnabled)
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
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mergeLot-\(lot.id)")
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
                        .tint(.primary)
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
