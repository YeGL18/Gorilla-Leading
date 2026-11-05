import UIKit
import MapKit

@MainActor
private final class MarkerAnimationDriver: NSObject {
    static let shared = MarkerAnimationDriver()
    private struct Entry {
        weak var view: FadingMarkerAnnotationView?
        let start: CFTimeInterval
    }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private struct Disappearance {
        weak var snapshot: UIImageView?
        weak var map: MKMapView?
        let coordinate: CLLocationCoordinate2D
        let offset: CGPoint
        let deadline: CFTimeInterval
    }
    private var disappearing: [ObjectIdentifier: Disappearance] = [:]
    private var link: CADisplayLink?

    func start(_ view: FadingMarkerAnnotationView) {
        entries[ObjectIdentifier(view)] = Entry(view: view, start: CACurrentMediaTime())
        updateDisplayLink()
    }

    func follow(_ snapshot: UIImageView, coordinate: CLLocationCoordinate2D, in map: MKMapView) {
        let anchor = map.convert(coordinate, toPointTo: map)
        disappearing[ObjectIdentifier(snapshot)] = Disappearance(
            snapshot: snapshot, map: map, coordinate: coordinate,
            offset: CGPoint(x: snapshot.frame.minX - anchor.x, y: snapshot.frame.minY - anchor.y),
            deadline: CACurrentMediaTime() + FadingMarkerAnnotationView.fadeDuration
        )
        updateDisplayLink()
    }

    private func updateDisplayLink() {
        guard !entries.isEmpty || !disappearing.isEmpty else {
            link?.invalidate()
            link = nil
            return
        }
        if let link {
            link.preferredFramesPerSecond = disappearing.isEmpty ? 60 : 120
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFramesPerSecond = disappearing.isEmpty ? 60 : 120
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancel(_ view: FadingMarkerAnnotationView) {
        entries.removeValue(forKey: ObjectIdentifier(view))
        updateDisplayLink()
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        for (id, entry) in entries {
            guard let view = entry.view, view.superview != nil else {
                entries.removeValue(forKey: id)
                continue
            }
            let t = min(1, max(0, (now - entry.start) / FadingMarkerAnnotationView.fadeDuration))
            let ease = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            view.setAppearanceOpacity(CGFloat(ease))
            if t >= 1 { entries.removeValue(forKey: id) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, entry) in disappearing {
            guard let snapshot = entry.snapshot, let map = entry.map,
                  snapshot.superview === map, map.window != nil, now < entry.deadline else {
                entry.snapshot?.removeFromSuperview()
                disappearing.removeValue(forKey: id)
                continue
            }
            // Keep a screen-sized native marker anchored to its original world
            // coordinate while pan, zoom, heading and pitch continue changing.
            let anchor = map.convert(entry.coordinate, toPointTo: map)
            snapshot.frame.origin = CGPoint(x: anchor.x + entry.offset.x, y: anchor.y + entry.offset.y)
        }
        CATransaction.commit()
        updateDisplayLink()
    }
}

class FadingMarkerAnnotationView: MKMarkerAnnotationView {
    static let fadeDuration: TimeInterval = 0.28
    static let disappearanceSnapshotName = "annotationDisappearance"
    private var hasVisibleAppearance = false
    private var appearanceScheduled = false
    private var appearanceGeneration = 0
    private var mapAlpha: CGFloat = 1
    private(set) var appearanceOpacity: CGFloat = 1
    private(set) var appearanceCycle = 0
    private var hiddenObservation: NSKeyValueObservation?
    private var appearanceImage: UIImage?
    private var appearanceImageBounds: CGRect = .zero
    private var snapshotScheduled = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        observeVisibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeVisibility()
    }

    private func observeVisibility() {
        // Native clustering can toggle the backing layer without calling the
        // UIView setter or detaching the marker. Observe that lifecycle too.
        hiddenObservation = layer.observe(\.isHidden, options: [.old, .new]) { [weak self] _, change in
            MainActor.assumeIsolated {
                guard let self, change.oldValue != change.newValue,
                      let hidden = change.newValue else { return }
                if hidden {
                    let generation = self.appearanceGeneration
                    // MapKit can briefly hide/reveal the same marker while moving
                    // it. Only a persistent hide is a genuine disappearance.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.appearanceGeneration == generation,
                              self.layer.isHidden else { return }
                        self.fadeOutSnapshot()
                        self.resetAppearance()
                    }
                } else {
                    self.animateAppearance()
                }
            }
        }
    }

    override var alpha: CGFloat {
        // MapKit owns this value. Do not feed our transient fade back into its
        // read/modify/write visibility and marker-size calculations.
        get { mapAlpha }
        set {
            if newValue == mapAlpha { return }
            if newValue == 0, mapAlpha > 0 { fadeOutSnapshot() }
            let wasInvisible = mapAlpha == 0
            mapAlpha = newValue
            applyAppearanceOpacity()
            if wasInvisible && newValue > 0 { animateAppearance() }
        }
    }

    private var renderedOpacity: CGFloat { mapAlpha * appearanceOpacity }

    private func applyAppearanceOpacity() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = Float(renderedOpacity)
        CATransaction.commit()
    }

    fileprivate func setAppearanceOpacity(_ opacity: CGFloat) {
        let becameOpaque = appearanceOpacity != 1 && opacity == 1
        appearanceOpacity = opacity
        applyAppearanceOpacity()
        if becameOpaque { refreshAppearanceSnapshot() }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        let changed = isSelected != selected
        guard changed else { return }
        super.setSelected(selected, animated: animated)
        let generation = appearanceGeneration
        // Cache the final selected/unselected shape, not an intermediate native
        // animation. Reused views must ignore an old selection's scheduled work.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) { [weak self] in
            guard let self, self.appearanceGeneration == generation,
                  self.isSelected == selected else { return }
            self.refreshAppearanceSnapshot()
        }
    }

    func refreshAppearanceSnapshot() {
        guard !snapshotScheduled, superview != nil, !layer.isHidden, appearanceOpacity == 1 else { return }
        snapshotScheduled = true
        let generation = appearanceGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshotScheduled = false
            guard self.appearanceGeneration == generation, self.window != nil,
                  !self.layer.isHidden, self.appearanceOpacity == 1 else { return }
            let bounds = self.snapshotBounds
            self.appearanceImage = self.renderAppearance(in: bounds)
            self.appearanceImageBounds = bounds
        }
    }

    func animateAppearance() {
        // A position update/reparent/didAdd callback is not a new appearance.
        guard superview != nil, !layer.isHidden, !hasVisibleAppearance else { return }
        hasVisibleAppearance = true
        guard !appearanceScheduled, appearanceOpacity == 1 else { return }
        appearanceCycle &+= 1
        appearanceScheduled = true
        setAppearanceOpacity(0)
        let generation = appearanceGeneration
        // MapKit clears animations while attaching/reusing annotation views.
        // Install ours after that transaction, before the next rendered frame.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.appearanceGeneration == generation else { return }
            self.appearanceScheduled = false
            guard self.superview != nil else { return }
            // Native marker rendering samples model opacity, not necessarily
            // UIKit presentation-layer animations. One short-lived shared driver
            // supplies actual intermediate values for every entering marker.
            MarkerAnimationDriver.shared.start(self)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil { animateAppearance() }
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil {
            fadeOutSnapshot()
            resetAppearance()
        }
        super.willMove(toSuperview: newSuperview)
    }

    override func prepareForReuse() {
        fadeOutSnapshot()
        resetAppearance()
        hasVisibleAppearance = false
        appearanceImage = nil
        mapAlpha = 1
        super.prepareForReuse()
        super.alpha = 1
    }

    private func resetAppearance() {
        MarkerAnimationDriver.shared.cancel(self)
        appearanceGeneration &+= 1
        appearanceScheduled = false
        setAppearanceOpacity(1)
    }

    private func fadeOutSnapshot() {
        guard hasVisibleAppearance else { return }
        hasVisibleAppearance = false
        guard window != nil, renderedOpacity > 0, let coordinate = annotation?.coordinate else { return }
        var ancestor = superview
        while let current = ancestor, !(current is MKMapView) { ancestor = current.superview }
        guard let map = ancestor as? MKMapView else { return }
        let contentBounds = appearanceImage == nil ? snapshotBounds : appearanceImageBounds
        let visibleFrame = convert(contentBounds, to: map)
        guard !visibleFrame.isEmpty, map.bounds.intersects(visibleFrame),
              let image = appearanceImage ?? renderAppearance(in: contentBounds) else { return }
        let snapshot = UIImageView(image: image)
        snapshot.alpha = appearanceImage == nil ? 1 : renderedOpacity
        // MapKit may immediately recycle the live view for a cluster/member.
        // Fade a noninteractive snapshot instead of delaying model removal.
        snapshot.frame = visibleFrame
        snapshot.layer.name = Self.disappearanceSnapshotName
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        map.addSubview(snapshot)
        // Capture a coordinate value, not the live annotation/view: MapKit may
        // immediately reuse either while the outgoing image is still fading.
        MarkerAnimationDriver.shared.follow(snapshot, coordinate: coordinate, in: map)
        // MapKit installs/recycles views with implicit UIView animations disabled.
        // Explicit layer animations still run inside those transactions.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = snapshot.layer.opacity
        fade.toValue = 0
        fade.duration = Self.fadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { snapshot.removeFromSuperview() }
        snapshot.layer.opacity = 0
        snapshot.layer.add(fade, forKey: Self.disappearanceSnapshotName)
        CATransaction.commit()
    }

    private var snapshotBounds: CGRect {
        var contentBounds = bounds
        for child in subviews where !child.isHidden {
            contentBounds = contentBounds.union(child.convert(child.bounds, to: self))
        }
        return contentBounds.insetBy(dx: -8, dy: -8)
    }

    private func renderAppearance(in contentBounds: CGRect) -> UIImage? {
        guard !layer.isHidden, !contentBounds.isEmpty else { return nil }
        // Cache the visible native marker before MapKit hides/clears its image.
        // Do not force a layout/screen update while MapKit is removing views.
        let renderer = UIGraphicsImageRenderer(size: contentBounds.size)
        return renderer.image { context in
            context.cgContext.translateBy(x: -contentBounds.minX, y: -contentBounds.minY)
            drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
    }
}

final class ParkingHoldGestureRecognizer: UILongPressGestureRecognizer {
    static let holdDuration: TimeInterval = 0.6
    var onPress: ((CGPoint) -> Void)?
    var onRelease: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if state == .possible, touches.count == 1, event.allTouches?.count == 1,
           let touch = touches.first, let view {
            onPress?(touch.location(in: view))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if state == .failed || state == .cancelled { onRelease?() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        onRelease?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        onRelease?()
    }

    override func reset() {
        super.reset()
        onRelease?()
    }
}

final class ParkingRecordMarkerView: MKAnnotationView {
    private let content = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 44))
    private let shape = CAShapeLayer()
    private let glyph = UILabel(frame: CGRect(x: 0, y: 0, width: 40, height: 36))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var holding = false
    var isHolding: Bool { holding }
    var sizeScale: CGFloat = 1 {
        didSet { if sizeScale != oldValue { applyScale(animated: false) } }
    }
    var locksDragAppearance = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bounds = CGRect(x: 0, y: 0, width: 40, height: 44)
        clipsToBounds = false
        content.isUserInteractionEnabled = false
        content.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        content.layer.position = CGPoint(x: 20, y: 44)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 20, y: 43))
        path.addCurve(to: CGPoint(x: 2, y: 19), controlPoint1: CGPoint(x: 13, y: 33), controlPoint2: CGPoint(x: 2, y: 30))
        path.addCurve(to: CGPoint(x: 20, y: 1), controlPoint1: CGPoint(x: 2, y: 9), controlPoint2: CGPoint(x: 10, y: 1))
        path.addCurve(to: CGPoint(x: 38, y: 19), controlPoint1: CGPoint(x: 30, y: 1), controlPoint2: CGPoint(x: 38, y: 9))
        path.addCurve(to: CGPoint(x: 20, y: 43), controlPoint1: CGPoint(x: 38, y: 30), controlPoint2: CGPoint(x: 27, y: 33))
        path.close()
        shape.path = path.cgPath
        shape.strokeColor = UIColor.white.cgColor
        shape.lineWidth = 2
        content.layer.addSublayer(shape)
        glyph.font = .systemFont(ofSize: 22, weight: .bold)
        glyph.textAlignment = .center
        glyph.textColor = .white
        content.addSubview(glyph)
        addSubview(content)
        for label in [titleLabel, subtitleLabel] {
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.textColor = UIColor { traits in
                traits.userInterfaceStyle == .dark ? .white
                    : UIColor(red: 0.40, green: 0.43, blue: 0.46, alpha: 1)
            }
            label.layer.shadowOpacity = 0
            addSubview(label)
        }
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(tint: UIColor, glyph text: String, title: String?, subtitle: String?, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.fillColor = tint.cgColor
        CATransaction.commit()
        glyph.text = text
        titleLabel.text = title
        subtitleLabel.text = subtitle
        let titleWidth = min(280, max(40, titleLabel.intrinsicContentSize.width + 8))
        let subtitleWidth = min(280, max(40, subtitleLabel.intrinsicContentSize.width + 8))
        titleLabel.frame = CGRect(x: 20 - titleWidth / 2, y: 48, width: titleWidth, height: 19)
        subtitleLabel.frame = CGRect(x: 20 - subtitleWidth / 2, y: 68, width: subtitleWidth, height: 16)
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        sizeScale = scale
    }

    func containsVisibleContent(_ point: CGPoint) -> Bool {
        !isHidden && alpha > 0 && (bounds.contains(point) ||
            (titleLabel.text?.isEmpty == false && titleLabel.frame.contains(point)) ||
            (subtitleLabel.text?.isEmpty == false && subtitleLabel.frame.contains(point)))
    }

    func animateHold(_ pressed: Bool) {
        guard holding != pressed else { return }
        holding = pressed
        displayPriority = pressed ? .required : (sizeScale > 1 ? .required : .defaultHigh)
        zPriority = pressed ? .max : .defaultUnselected
        applyScale(animated: true)
    }

    private func applyScale(animated: Bool) {
        let target = CGAffineTransform(scaleX: sizeScale * (holding ? 1.2 : 1),
                                       y: sizeScale * (holding ? 1.2 : 1))
        guard animated else { content.transform = target; return }
        UIView.animate(withDuration: holding ? ParkingHoldGestureRecognizer.holdDuration : 0.24,
                       delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.content.transform = target
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        holding = false
        locksDragAppearance = false
        content.layer.removeAllAnimations()
        sizeScale = 1
        titleLabel.text = nil
        subtitleLabel.text = nil
    }
}

/// Keep content scaling separate from MapKit's native view transform.
final class ScaledMarkerAnnotationView: FadingMarkerAnnotationView {
    private var holdScale: CGFloat = 1

    func animateHold(_ pressed: Bool) {
        holdScale = pressed ? 1.28 : 1
        let target = CATransform3DMakeScale(sizeScale * holdScale, sizeScale * holdScale, 1)
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: layer.presentation()?.sublayerTransform ?? layer.sublayerTransform)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = pressed ? ParkingHoldGestureRecognizer.holdDuration : 0.24
        animation.timingFunction = CAMediaTimingFunction(name: pressed ? .easeInEaseOut : .easeOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()
        layer.add(animation, forKey: "parkingHold")
    }
    /// MapKit lays out titles/subtitles outside the marker's own bounds.
    func containsVisibleContent(_ point: CGPoint) -> Bool {
        guard !isHidden, !layer.isHidden, alpha > 0 else { return false }
        if bounds.contains(point) { return true }
        func contains(_ view: UIView) -> Bool {
            guard !view.isHidden, !view.layer.isHidden, view.alpha > 0 else { return false }
            let local = convert(point, to: view)
            return view.bounds.contains(local) || view.subviews.contains(where: contains)
        }
        return subviews.contains(where: contains)
    }

    var snapshotSignature: String?
    var locksDragAppearance = false {
        didSet {
            if locksDragAppearance { super.setSelected(false, animated: false) }
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(locksDragAppearance ? false : selected,
                          animated: locksDragAppearance ? false : animated)
    }

    var sizeScale: CGFloat = 1 {
        didSet {
            guard sizeScale != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.sublayerTransform = CATransform3DMakeScale(sizeScale * holdScale, sizeScale * holdScale, 1)
            CATransaction.commit()
        }
    }

    override func prepareForReuse() {
        holdScale = 1
        layer.removeAnimation(forKey: "parkingHold")
        sizeScale = 1
        layer.sublayerTransform = CATransform3DIdentity
        snapshotSignature = nil
        locksDragAppearance = false
        super.prepareForReuse()
    }
}

/// Receives only touches actually delivered to the map, unlike hit-test probes
/// beneath SwiftUI overlays. Failing immediately never holds up MapKit gestures.
final class MapBlankTapGestureRecognizer: UITapGestureRecognizer {
    private var origin: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first { origin = touch.location(in: view) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let origin, let touch = touches.first else { return }
        let current = touch.location(in: view)
        if hypot(current.x - origin.x, current.y - origin.y) > 4 { state = .failed }
    }

    override func reset() {
        super.reset()
        origin = nil
    }
}

private final class MapTouchDeliveryObserver: UIGestureRecognizer {
    var delivered: ((Set<UITouch>) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
        delivered?(touches)
    }

    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}

/// The same narrow, translucent white casing used by trip replay. Draw it
/// inside the renderer so route replacement and animation cannot orphan a line.
class OutlinedRoutePolylineRenderer: MKPolylineRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if path == nil { createPath() }
        guard let path, zoomScale > 0 else { return }
        drawOutlinedPath(path, zoomScale: zoomScale, in: context)
    }

    func drawOutlinedPath(_ path: CGPath, zoomScale: MKZoomScale, in context: CGContext) {
        guard zoomScale > 0 else { return }
        context.saveGState()
        applyStrokeProperties(to: context, atZoomScale: zoomScale)
        strokeOutlinedPath(path, in: context, width: lineWidth / CGFloat(zoomScale))
        context.restoreGState()
    }

    func strokeOutlinedPath(_ path: CGPath, in context: CGContext, width: CGFloat) {
        context.saveGState()
        context.setLineWidth(width * ((lineWidth + 2) / max(0.01, lineWidth)))
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.55 * (strokeColor?.cgColor.alpha ?? 1)).cgColor)
        context.beginPath()
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
        // Do not inherit MKOverlayPathRenderer's adjusted stroke width. Both
        // strokes must use the same explicit map-to-screen conversion.
        context.saveGState()
        context.setLineWidth(width)
        context.setStrokeColor((strokeColor ?? .clear).cgColor)
        context.beginPath()
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}

class NonAdjustingMapView: MKMapView {
    func isAnnotationHit(at point: CGPoint) -> Bool {
        for annotation in annotations {
            guard let marker = self.view(for: annotation), !marker.isHidden, marker.alpha > 0.01 else { continue }
            if annotation is MKUserLocation {
                let center = convert(annotation.coordinate, toPointTo: self)
                if hypot(point.x - center.x, point.y - center.y) <= 18 { return true }
                continue
            }
            let local = convert(point, to: marker)
            if marker.bounds.contains(local) { return true }
            // Native annotation titles can sit outside the pin's bounds.
            func hitsLabel(_ view: UIView) -> Bool {
                guard !view.isHidden, view.alpha > 0.01 else { return false }
                if view is UILabel, view.bounds.contains(convert(point, to: view)) { return true }
                return view.subviews.contains(where: hitsLabel)
            }
            if marker.subviews.contains(where: hitsLabel) { return true }
        }
        return false
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        installTouchObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installTouchObservation()
    }

    private func installTouchObservation() {
        let observer = MapTouchDeliveryObserver(target: nil, action: nil)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.delivered = { [weak self] touches in self?.receivedMapTouches(touches) }
        addGestureRecognizer(observer)
    }

    private func receivedMapTouches(_ touches: Set<UITouch>) {
        guard onTouchBegan != nil || onTouchEnded != nil else { return }
        activeTouches.formUnion(touches)
        guard touchPollTimer == nil else { return }
        beginAnnotationTouch()
        allowsUserCameraChanges = true
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTouchRelease() }
        }
        touchPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        // This is still the initial touch delivery, before pan recognition.
        onTouchBegan?()
    }
    func annotationsDidAppear(_ views: [MKAnnotationView]) {
        for case let view as FadingMarkerAnnotationView in views {
            view.animateAppearance()
        }
    }

    static func displayFrame(in size: CGSize, centerOffset: CGPoint) -> CGRect {
        CGRect(x: min(0, -centerOffset.x), y: min(0, -centerOffset.y),
               width: size.width + abs(centerOffset.x), height: size.height + abs(centerOffset.y))
    }

    private var isAnnotationDragActive = false
    private var suppressSelectionUntilNextTouch = false
    var isAnnotationSelectionSuppressed: Bool {
        isAnnotationDragActive || suppressSelectionUntilNextTouch
    }

    func beginAnnotationDrag() {
        isAnnotationDragActive = true
        suppressSelectionUntilNextTouch = true
    }

    func beginAnnotationHold() {
        suppressSelectionUntilNextTouch = true
    }

    func allowAnnotationTap() {
        if !isAnnotationDragActive { suppressSelectionUntilNextTouch = false }
    }

    func endAnnotationDrag() {
        isAnnotationDragActive = false
        // Keep ownership of the release event, including delayed MapKit selection.
        // A new touch after the marker settles can select annotations normally.
    }

    func beginAnnotationTouch() {
        if !isAnnotationDragActive { suppressSelectionUntilNextTouch = false }
    }

    /// MapKit can deliver native selection directly to its delegate, bypassing
    /// selectAnnotation. Reject that path before a meter popup changes app state.
    func rejectSelectionDuringAnnotationDrag(_ view: MKAnnotationView) -> Bool {
        guard isAnnotationSelectionSuppressed else { return false }
        if let annotation = view.annotation { deselectAnnotation(annotation, animated: false) }
        return true
    }
    var allowCameraChange = false
    var allowsUserCameraChanges = false
    var onTouchBegan: (() -> Void)?
    var onTouchEnded: (() -> Void)?
    private var activeTouches: Set<UITouch> = []
    private var touchPollTimer: Timer?
    private var savedCameraBeforeLayout: MKMapCamera?

    func cameraFitting(_ rect: MKMapRect, edgePadding: UIEdgeInsets) -> MKMapCamera {
        let original = camera.copy() as! MKMapCamera
        let originalPermission = allowCameraChange
        let originalDelegate = delegate
        // Ask MapKit for its exact padded fit, then restore before this run-loop
        // turn can render. Suppress delegate side effects from the fitting probe.
        delegate = nil
        allowCameraChange = true
        defer {
            setCamera(original, animated: false)
            allowCameraChange = originalPermission
            delegate = originalDelegate
        }
        setVisibleMapRect(rect, edgePadding: edgePadding, animated: false)
        return camera.copy() as! MKMapCamera
    }

    // Collect any additional fingers while a delivered map touch is held.
    // Never start camera ownership from hitTest: overlays may win the touch.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard hit != nil, let event, event.type == .touches,
              onTouchBegan != nil || onTouchEnded != nil,
              bounds.contains(point) else { return hit }
        // hitTest is also a probe beneath SwiftUI overlays. It does not mean the
        // touch was delivered here (a text field or button may win instead).
        // Wait for UIKit to assign touch.view before taking camera ownership.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.touchPollTimer != nil else { return }
            let delivered = (event.allTouches ?? []).filter {
                $0.view?.isDescendant(of: self) == true && $0.phase != .ended && $0.phase != .cancelled
            }
            guard !delivered.isEmpty else { return }
            self.activeTouches.formUnion(delivered)
        }
        return hit
    }

    private func checkTouchRelease() {
        activeTouches = activeTouches.filter { $0.phase != .ended && $0.phase != .cancelled }
        guard activeTouches.isEmpty else { return }
        stopObservingTouches()
        onTouchEnded?()
    }

    func stopObservingTouches() {
        touchPollTimer?.invalidate()
        touchPollTimer = nil
        activeTouches.removeAll()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            let wasActive = !activeTouches.isEmpty
            stopObservingTouches()
            if wasActive { onTouchEnded?() }
        }
    }

    override func setCamera(_ newCamera: MKMapCamera, animated: Bool) {
        guard allowCameraChange || allowsUserCameraChanges else { return }
        super.setCamera(newCamera, animated: animated)
    }

    override func setRegion(_ newRegion: MKCoordinateRegion, animated: Bool) {
        guard allowCameraChange || allowsUserCameraChanges else { return }
        super.setRegion(newRegion, animated: animated)
    }

    override func selectAnnotation(_ annotation: MKAnnotation, animated: Bool) {
        // 藍點唔俾選中：MapKit 內建 tap-to-select 喺停車點同藍點疊埋／太近嗰陣會誤判做藍點，
        // 跟手自動退選停車點，個標就又縮又漲又閃。任何人想選中藍點都擋走。
        if annotation is MKUserLocation || isAnnotationSelectionSuppressed { return }
        super.selectAnnotation(annotation, animated: animated)
    }

    override func layoutSubviews() {
        if !allowCameraChange && !allowsUserCameraChanges {
            savedCameraBeforeLayout = camera.copy() as? MKMapCamera
        }
        super.layoutSubviews()
        if !allowCameraChange && !allowsUserCameraChanges, let saved = savedCameraBeforeLayout {
            let current = camera
            if current.centerCoordinate.latitude != saved.centerCoordinate.latitude ||
                current.centerCoordinate.longitude != saved.centerCoordinate.longitude ||
                current.centerCoordinateDistance != saved.centerCoordinateDistance ||
                current.heading != saved.heading || current.pitch != saved.pitch {
                camera = saved
            }
            savedCameraBeforeLayout = nil
        }
    }
}
