import SwiftUI
import MapKit
import Charts
import Combine
import UniformTypeIdentifiers

@MainActor
private final class ReplayReadoutClock: ObservableObject {
    @Published var selection = Date.distantPast
}

@MainActor
private final class ReplayTransport: NSObject, ObservableObject {
    @Published private(set) var selection = Date.distantPast
    let readouts = ReplayReadoutClock()
    var onFrame: ((Date) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var reduceMotion = false
    var isScrolling = false
    private var start = Date.distantPast
    private var end = Date.distantPast
    private var motion = ReplayScrubMotion()
    private var playing = false
    private var rate = 8.0
    private var link: CADisplayLink?
    private let proxy = FrameProxy()
    private var timestamp: CFTimeInterval?
    private var publishedAt: CFTimeInterval = 0
    private var readoutAt: CFTimeInterval = 0
    private var publishInterval: CFTimeInterval = 1 / 60

    @MainActor private final class FrameProxy: NSObject {
        weak var owner: ReplayTransport?
        @objc func tick(_ link: CADisplayLink) { owner?.frame(link) }
    }

    override init() { super.init(); proxy.owner = self }
    deinit { link?.invalidate() }
    var currentDate: Date { start.addingTimeInterval(motion.position) }

    func configure(start: Date, end: Date, sampleCount: Int) {
        self.start = start
        self.end = end
        publishInterval = sampleCount > 2000 ? 1 / 30 : 1 / 60
        seek(start)
    }

    func extend(end: Date, sampleCount: Int) {
        self.end = max(start, end)
        publishInterval = sampleCount > 2000 ? 1 / 30 : 1 / 60
    }

    func seek(_ date: Date) {
        playing = false
        motion.seek(min(max(0, end.timeIntervalSince(start)), max(0, date.timeIntervalSince(start))))
        publish()
        stopLink()
    }

    func scrub(_ date: Date, speed: Double) {
        playing = false
        let value = min(max(0, end.timeIntervalSince(start)), max(0, date.timeIntervalSince(start)))
        if reduceMotion { seek(start.addingTimeInterval(value)); return }
        motion.drag(to: value, pointsPerSecond: speed)
        startLink()
    }

    func release() { motion.release(); if !motion.settled { startLink() } }

    func play(_ enabled: Bool, rate: Double) {
        playing = enabled
        self.rate = rate
        if enabled || !motion.settled { startLink() } else { stopLink() }
    }

    func stop() {
        playing = false
        motion.seek(motion.position)
        publish()
        stopLink()
    }

    private func startLink() {
        guard link == nil else { return }
        timestamp = nil
        let display = CADisplayLink(target: proxy, selector: #selector(FrameProxy.tick(_:)))
        display.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        display.add(to: .main, forMode: .common)
        link = display
    }

    private func stopLink() { link?.invalidate(); link = nil; timestamp = nil }
    private func publish() {
        selection = currentDate
        readouts.selection = selection
        onFrame?(selection)
    }

    private func frame(_ display: CADisplayLink) {
        let dt = min(0.05, max(0, timestamp.map { display.timestamp - $0 } ?? 1 / 120))
        timestamp = display.timestamp
        var reachedEnd = false
        if playing {
            motion.seek(min(end.timeIntervalSince(start), motion.position + dt * rate))
            if currentDate >= end { playing = false; reachedEnd = true }
        } else { motion.step(dt) }
        onFrame?(currentDate)
        // Map motion follows every display frame; expensive charts publish at up to 60 Hz.
        let interval = isScrolling ? max(publishInterval, 1 / 15) : publishInterval
        if display.timestamp - publishedAt >= interval - 0.001 || (!playing && motion.settled) {
            publishedAt = display.timestamp
            selection = currentDate
        }
        // Glass controls and numeric readouts do not need the map's frame rate.
        let readoutInterval = isScrolling ? 1.0 / 8 : playing ? 1.0 / 12 : 1.0 / 30
        if display.timestamp - readoutAt >= readoutInterval || (!playing && motion.settled) {
            readoutAt = display.timestamp
            readouts.selection = currentDate
        }
        if !playing && motion.settled { stopLink() }
        // Only a playing frame can complete; seeking/settling at the end cannot.
        if reachedEnd { onPlaybackEnded?() }
    }
}

private struct ReplayTimeReader<Content: View>: View {
    @ObservedObject private var clock: ReplayReadoutClock
    private let transport: ReplayTransport
    @ViewBuilder let content: (Date) -> Content
    init(transport: ReplayTransport, @ViewBuilder content: @escaping (Date) -> Content) {
        clock = transport.readouts
        self.transport = transport
        self.content = content
    }
    var body: some View {
        content(clock.selection)
            .transaction { if transport.isScrolling { $0.disablesAnimations = true } }
    }
}

@MainActor
private final class ReplayResultsBoundary: ObservableObject {
    @Published var top: CGFloat = 0
}

private struct ReplayResultsMask: View {
    @ObservedObject var boundary: ReplayResultsBoundary
    let opacity: Double
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Rectangle().fill(.black).frame(height: min(geometry.size.height,
                    max(0, boundary.top - geometry.frame(in: .global).minY)))
                Rectangle().fill(.black).opacity(opacity)
            }
        }
    }
}

struct TripReplayLibraryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TripReplayStore = .shared
    var onClose: (() -> Void)? = nil
    @State private var day = Date()
    @State private var displayedDay = Date()
    @State private var resultsOpacity = 1.0
    @State private var resultsBoundary = ReplayResultsBoundary()
    @State private var confirmDeleteAll = false
    @State private var deleting: UUID?
    @State private var showSettings = false
    @State private var selectedTrip: UUID?

    private var dailyTrips: [TripReplay] {
        store.trips.filter { Calendar.current.isDate($0.start, inSameDayAs: displayedDay) }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        List {
            if store.activeID != nil {
                HStack {
                    Label(LocalizedStringKey(store.isRecording ? "Recording Trip" : "Recording Paused"), systemImage: "record.circle")
                        .foregroundStyle(store.isRecording ? .red : .secondary)
                    Spacer()
                    Button("Finish Trip", action: store.finish)
                }
            }
            Section {
                DatePicker("Trip Date", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .accessibilityIdentifier("replayCalendar")
            }
            Section {
                if let error = store.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if dailyTrips.isEmpty {
                    ContentUnavailableView("No Recorded Trips", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                        description: Text("No Historic Route Notice"))
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("replayEmptyHistory")
                }
                ForEach(dailyTrips) { trip in
                    Button { selectedTrip = trip.id } label: {
                        HStack(spacing: 12) {
                            ReplayRouteThumbnail(trip: trip).frame(width: 92, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ReplayFormat.title(trip))
                                    .font(.headline).lineLimit(2)
                                Text(trip.start.formatted(date: .omitted, time: .shortened) + " – "
                                     + trip.end.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline).monospacedDigit()
                                Text(ReplayFormat.duration(trip.duration))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("replayTripRow")
                    .swipeActions {
                        // A destructive swipe role removes the row optimistically before confirmation.
                        Button { deleting = trip.id } label: {
                            Label("Delete", systemImage: "trash").labelStyle(.titleAndIcon)
                        }
                            .tint(.red)
                    }
                }
            } header: {
                Text(displayedDay, format: .dateTime.year().month().day())
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .global).minY - 12
                    } action: { top in
                        resultsBoundary.top = top
                    }
            }
        }
        // Mask the native list too: per-row opacity excludes UIKit's grouped backing.
        .mask { ReplayResultsMask(boundary: resultsBoundary, opacity: resultsOpacity) }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: Calendar.current.startOfDay(for: day)) {
            let requested = day
            guard !Calendar.current.isDate(requested, inSameDayAs: displayedDay) else {
                withAnimation(.easeIn(duration: 0.18)) { resultsOpacity = 1 }
                return
            }
            withAnimation(.easeOut(duration: 0.12)) { resultsOpacity = 0 }
            do { try await Task.sleep(for: .milliseconds(130)) } catch { return }
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { displayedDay = requested }
            // Commit new rows at zero opacity before starting their entrance animation.
            do { try await Task.sleep(for: .milliseconds(35)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) { resultsOpacity = 1 }
        }
        // Keep navigation-bar geometry identical to the map throughout push/pop.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { libraryHeader }
        .navigationDestination(item: $selectedTrip) { id in
            TripReplayDetailView(tripID: id, store: store, onBack: { selectedTrip = nil })
        }
        .tint(colorScheme == .dark ? Color.white : Color.accentColor)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section {
                        Toggle("Record Foreground Trips", isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
                            .accessibilityIdentifier("replayRecordingToggle")
                        Picker("Keep Trip History", selection: Binding(get: { store.retentionDays }, set: { store.setRetention($0) })) {
                            Text("7 Days").tag(7)
                            Text("30 Days").tag(30)
                            Text("90 Days").tag(90)
                        }
                    } footer: { Text("Replay Privacy Notice") }
                    Section { Text("Replay Storage Limits").font(.footnote).foregroundStyle(.secondary) }
                }
                .navigationTitle("Recording Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "xmark") { showSettings = false }
                        .accessibilityIdentifier("replayCloseSettings")
                } }
            }
        }
        .confirmationDialog("Delete All Trips?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All Trips", role: .destructive, action: store.deleteAll)
        } message: { Text("Replay Delete Notice") }
        .confirmationDialog("Delete Trip?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
                .accessibilityIdentifier("replayConfirmDelete")
        }
    }

    private var libraryHeader: some View {
        ZStack {
            Text("Trip Replay").font(.headline)
                .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 96)
                .accessibilityIdentifier("replayLibraryTitle")
            HStack {
                Button("Close") { if let onClose { onClose() } else { dismiss() } }
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16).frame(height: 44)
                    .contentShape(Capsule())
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityIdentifier("replayCloseLibrary")
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Button("Recording Settings", systemImage: "gearshape") { showSettings = true }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Circle())
                        .accessibilityIdentifier("replayRecordingSettings")
                    Menu {
                        Button("Today", systemImage: "calendar") { day = .now }
                        Button("Delete All Trips", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .accessibilityIdentifier("replayCalendarMenu")
                }
                .font(.system(size: 20, weight: .medium))
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct ReplayRouteThumbnail: View {
    let trip: TripReplay
    var body: some View {
        Map(interactionModes: []) {
            ForEach(Array(trip.routeSegments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.map(\.coordinate)).stroke(.white.opacity(0.55), lineWidth: 4.5)
                MapPolyline(coordinates: segment.map(\.coordinate)).stroke(Color.blue, lineWidth: 3)
            }
            if let first = trip.points.first {
                Marker("", systemImage: "circle.fill", coordinate: first.coordinate).tint(.green).annotationTitles(.hidden)
            }
            if let last = trip.points.last {
                Marker("", systemImage: "flag.checkered", coordinate: last.coordinate).tint(Color.blue).annotationTitles(.hidden)
            }
        }
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReplaySectionDrop: DropDelegate {
    let target: String
    @Binding var order: String
    @Binding var dragged: String?
    static func sections(_ raw: String) -> [String] {
        let valid = ["statistics", "timeline", "selected", "altitude"]
        var result: [String] = []
        for key in raw.split(separator: ",").map(String.init) + valid where valid.contains(key) && !result.contains(key) {
            result.append(key)
        }
        return result
    }
    func validateDrop(info: DropInfo) -> Bool { dragged != nil }
    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        var values = Self.sections(order)
        guard let source = values.firstIndex(of: dragged), let destination = values.firstIndex(of: target) else { return }
        withAnimation(.snappy(duration: 0.25)) {
            values.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
            order = values.joined(separator: ",")
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}

struct FixedSpeedDashboard<SpeedContent: View>: View {
    @ObservedObject var store = TripReplayStore.shared
    let motion: GForceParallaxMotion
    let telemetry: ACTelemetry
    let partiallyOpen: Bool
    let foreground: Color
    let accent: Color
    let textColorOverride: Color?
    let driving: Bool
    let onBlankTap: () -> Void
    @ViewBuilder var speed: () -> SpeedContent
    @AppStorage(SpeedUnit.preferenceKey) private var unitRaw = SpeedUnit.kilometresPerHour.rawValue
    @State private var transport = ReplayTransport()
    private var trip: TripReplay? { driving && !telemetry.isReceiving ? store.drivingTrip : nil }
    private var unit: SpeedUnit { .resolve(unitRaw) }
    private var selection: Binding<Date> {
        Binding(get: { transport.selection }, set: { _ in })
    }
    var body: some View {
        GeometryReader { geometry in
            let layout = SpeedCardLayout(width: geometry.size.width, height: geometry.size.height, partiallyOpen: partiallyOpen)
            let w = layout.width, h = layout.height
            ZStack {
                if layout.horizontal {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 6) { statistics(columns: 5); chart(.speed(unit), height: max(30, h * 0.17)) }
                            .frame(width: (w - 52) * 0.29)
                        VStack(spacing: 6) {
                            action.frame(height: max(84, h * 0.28))
                            Spacer(minLength: 0)
                            liveReadout
                        }.frame(maxWidth: .infinity)
                        VStack(spacing: 6) {
                            force.frame(height: max(100, h * 0.36))
                            chart(.altitude, height: max(30, h * 0.17))
                        }.frame(width: (w - 52) * 0.29)
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 58)
                } else {
                    VStack(spacing: 8) {
                        statistics(columns: 5)
                        HStack(spacing: 8) { action; force }
                            .frame(height: max(84, h * 0.32 - 76))
                        Spacer(minLength: 0)
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                chart(.speed(unit), height: max(34, h * 0.105))
                                chart(.altitude, height: max(34, h * 0.105))
                            }
                            liveReadout
                        }
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 68)
                }
                speed().frame(width: w * (layout.horizontal ? 0.35 : 0.72), height: h * (layout.horizontal ? 0.42 : 0.28))
                    .position(x: w / 2, y: h / 2)
            }
            .frame(width: w, height: h)
            .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: onBlankTap) }
        }
        .foregroundStyle(foreground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fixedSpeedDashboard")
        .task(id: "\(trip?.id)-\(trip?.end)") {
            guard let trip else { transport.stop(); return }
            transport.configure(start: trip.start, end: trip.end, sampleCount: trip.points.count)
            transport.seek(trip.end)
        }
        .onDisappear { transport.stop() }
    }
    private var action: some View {
        SpeedCurrentActionPanel(motion: motion, telemetry: telemetry, accent: accent,
            textColorOverride: textColorOverride, canRecognize: driving || telemetry.isReceiving)
            .instrumentGlass().accessibilityIdentifier("currentActionCard")
    }
    private var force: some View {
        SpeedGForceCirclePanel(motion: motion, telemetry: telemetry, accent: accent,
            textColorOverride: textColorOverride, compact: true, enabled: driving || telemetry.isReceiving)
            .instrumentGlass().accessibilityIdentifier("gForceCircleCard")
    }
    private func statistics(columns: Int) -> some View {
        let metrics: [(String, String)] = [
            ("距離", String(format: "%.2f km", (trip?.distanceMeters ?? 0) / 1000)),
            ("平均速度", ReplayFormat.speed(trip?.averageSpeed ?? 0, unit: unit)),
            ("最高速度", ReplayFormat.speed(trip?.topSpeed ?? 0, unit: unit)),
            ("行程時長", ReplayFormat.duration(trip?.duration ?? 0)),
            ("開車時間", ReplayFormat.duration(trip?.drivingSeconds ?? 0)),
            ("記錄時間", ReplayFormat.duration(trip?.observedSeconds ?? 0)),
            ("峰值 G", String(format: "%.2f G", trip?.peakG ?? 0)),
            ("最高海拔", ReplayFormat.meters(trip?.highestAltitude ?? 0)),
            ("駕駛事件", String(trip?.events.count ?? 0)),
            ("最低海拔", ReplayFormat.meters(trip?.lowestAltitude ?? 0))]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
            ForEach(metrics.indices, id: \.self) { index in
                VStack(spacing: 2) {
                    Text(LocalizedStringKey(metrics[index].0)).font(.system(size: 9)).opacity(0.65)
                    Text(metrics[index].1).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle([2, 6].contains(index) ? accent : foreground)
                }.lineLimit(1).minimumScaleFactor(0.65)
            }
        }.padding(8).instrumentGlass().frame(height: 76).accessibilityIdentifier("speedCompactStatistics")
    }
    private func chart(_ metric: ReplayMetric, height: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.title == "m" ? "海拔變化" : "即時速度")
                .font(.system(size: 10, weight: .semibold))
            if let trip {
                ReplayMetricChart(trip: trip, metric: metric, transport: transport,
                    selection: selection, height: height, compact: true).equatable().allowsHitTesting(false)
            } else { Text("等待開車").font(.caption2).opacity(0.6).frame(maxWidth: .infinity).frame(height: height) }
        }.padding(7).instrumentGlass().frame(height: height + 28)
    }
    private var liveReadout: some View {
            HStack(spacing: 6) {
                Text(driving ? "本次行程 · 即時" : "等待開車")
                Spacer(minLength: 0)
                Text("海拔 " + ReplayFormat.meters(trip?.points.last?.altitude ?? 0))
            }.font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("speedLiveReadout")
    }
}


struct TripReplayDetailView: View {
    let tripID: UUID
    @ObservedObject var store: TripReplayStore = .shared
    var onBack: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SpeedUnit.preferenceKey) private var speedUnitRaw = SpeedUnit.kilometresPerHour.rawValue
    @State private var overviewRequest = 0
    @State private var followsPosition = false
    @State private var transport = ReplayTransport()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = false
    @State private var playbackRate = 8.0
    @State private var showDetails = false
    @State private var replayVisible = false
    @State private var detailsDismissing = false
    @State private var reopenDetailsAfterDismiss = false
    @State private var detent: PresentationDetent = .medium
    @State private var confirmDelete = false
    @State private var sheetSideInsets = UIEdgeInsets.zero
    @AppStorage("replayDetailSectionOrder") private var sectionOrder = "statistics,timeline,selected,altitude"
    @State private var draggedSection: String?
    private var trip: TripReplay? { store.trips.first { $0.id == tripID } }
    private var unit: SpeedUnit { .resolve(speedUnitRaw) }
    private var selection: Date {
        get { transport.selection }
        nonmutating set { pausePlayback(); transport.seek(newValue) }
    }
    private var selectionBinding: Binding<Date> {
        Binding(get: { selection }, set: { selection = $0 })
    }
    private var detailsPresentation: Binding<Bool> {
        Binding(get: { showDetails }, set: { presented in
            if !presented { detailsDismissing = true }
            showDetails = presented
        })
    }

    private func pausePlayback() {
        reopenDetailsAfterDismiss = false
        playing = false
        transport.play(false, rate: playbackRate)
    }

    private func leaveReplay() {
        replayVisible = false
        pausePlayback()
        transport.onPlaybackEnded = nil
        showDetails = false
        transport.stop()
    }

    private func playbackEnded() {
        guard replayVisible, scenePhase == .active, playing, trip != nil else { return }
        playing = false
        // UIKit cannot present again until an interactive dismissal finishes.
        if detailsDismissing { reopenDetailsAfterDismiss = true }
        else { showDetails = true }
    }

    private func detailsDismissed() {
        detailsDismissing = false
        let reopen = reopenDetailsAfterDismiss
        reopenDetailsAfterDismiss = false
        guard reopen, replayVisible, scenePhase == .active, trip != nil else { return }
        showDetails = true
    }

    var body: some View {
        Group {
            if let trip { map(trip) }
            else { ContentUnavailableView("No Recorded Trips", systemImage: "map") }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { leaveReplay() }
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Back").accessibilityIdentifier("replayBack")
                Spacer()
                Button { showDetails = true } label: {
                    Image(systemName: "chart.xyaxis.line").frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Trip Details")
                    .accessibilityIdentifier("replayDetailsButton")
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
        }
        .tint(colorScheme == .dark ? Color.white : Color.accentColor)
        .sheet(isPresented: detailsPresentation, onDismiss: detailsDismissed) {
            if let trip {
                replayPanel(trip)
                    .tint(colorScheme == .dark ? Color.white : Color.accentColor)
                    .presentationDetents([.height(280), .medium, .large], selection: $detent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
        .onAppear {
            replayVisible = true
            detailsDismissing = false
            reopenDetailsAfterDismiss = false
            if let trip { transport.configure(start: trip.start, end: trip.end, sampleCount: trip.points.count) }
            transport.reduceMotion = reduceMotion
            transport.onPlaybackEnded = playbackEnded
            showDetails = true
        }
        .onDisappear { leaveReplay() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pausePlayback(); transport.stop() } }
        .onChange(of: playing) { _, value in
            transport.play(value && playing && replayVisible && scenePhase == .active, rate: playbackRate)
        }
        .onChange(of: playbackRate) { _, value in
            transport.play(playing && replayVisible && scenePhase == .active, rate: value)
        }
        .onChange(of: reduceMotion) { _, value in transport.reduceMotion = value }
    }

    private func map(_ trip: TripReplay) -> some View {
        ReplayRouteMap(trip: trip, transport: transport, overviewRequest: overviewRequest,
                       sheetFraction: !showDetails ? 0 : detent == .large ? 0.82 : detent == .medium ? 0.5 : 0.32,
                       followsPosition: followsPosition, onStopFollowing: { followsPosition = false })
        .accessibilityIdentifier("tripReplayMap")
        .ignoresSafeArea()
    }

    private func replayPanel(_ trip: TripReplay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ReplayFormat.title(trip)).font(.headline)
                        Text((trip.originName ?? String(localized: "Trip Start")) + " → "
                             + (trip.destinationName ?? String(localized: "Trip End")))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("replayEndpoints")
                        Text(trip.start, format: .dateTime.year().month().day()).font(.title3.bold())
                        Text(trip.start.formatted(date: .omitted, time: .shortened) + " – " + trip.end.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        followsPosition = false
                        overviewRequest += 1
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Show Full Route")
                    .accessibilityIdentifier("replayOverview")
                    Button { followsPosition.toggle() } label: {
                        Image(systemName: followsPosition ? "location.fill" : "scope")
                            .font(.system(size: 23, weight: .medium)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("跟隨行程位置")
                    .accessibilityValue(followsPosition ? "開啟" : "關閉")
                    .accessibilityIdentifier("replayFollowPosition")
                }
                ForEach(detailSections, id: \.self) { section in
                    replaySection(section, trip: trip)
                        .onDrag {
                            draggedSection = section
                            AppHaptics.play(.longPress)
                            return NSItemProvider(object: section as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReplaySectionDrop(target: section,
                            order: $sectionOrder, dragged: $draggedSection))
                }
                Button("Delete Trip", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20).padding(.top, 8)
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .onScrollPhaseChange { _, phase in transport.isScrolling = phase != .idle }
        .overlay(alignment: .bottom) { playback(trip).offset(y: 12) }
        .padding(.leading, sheetSideInsets.left)
        .padding(.trailing, sheetSideInsets.right)
        .background(ReplaySheetSafeAreaReader(insets: $sheetSideInsets))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripReplayPanel")
        .confirmationDialog("Delete Trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                leaveReplay()
                store.delete(tripID)
                if let onBack { onBack() } else { dismiss() }
            }
        } message: { Text("Replay Delete Notice") }
    }

    private var detailSections: [String] { ReplaySectionDrop.sections(sectionOrder) }

    @ViewBuilder private func replaySection(_ section: String, trip: TripReplay) -> some View {
        Group {
            switch section {
            case "statistics":
                ReplayStatistics(trip: trip, unit: unit)
                    .equatable()
                    .replaySurface(expanded: detent == .large)
            case "timeline":
                VStack(alignment: .leading, spacing: 10) {
                if trip.hasGaps {
                    Label("Partial Trip Notice", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ReplayTimeReader(transport: transport) { _ in
                    HStack {
                        Text("Timeline").font(.headline)
                        Spacer()
                        ReplayCurrentEventBadge(action: trip.events.first(where: { $0.start <= selection && $0.end >= selection })?.action)
                    }
                    }
                    ReplayMetricChart(trip: trip, metric: .speed(unit), transport: transport, selection: selectionBinding).equatable()
                    ReplayEventTimeline(trip: trip, transport: transport, selection: selectionBinding, playing: $playing).equatable()
                }
                .replaySurface(expanded: detent == .large)
                }
            case "selected":
                selectedMoment(trip)
                    .replaySurface(expanded: detent == .large)
            default:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Altitude Changes").font(.headline)
                        Spacer()
                        Text("GPS · m").font(.caption).foregroundStyle(.secondary)
                    }
                    ReplayMetricChart(trip: trip, metric: .altitude, transport: transport, selection: selectionBinding).equatable()
                    Text("Replay Altitude Notice").font(.caption).foregroundStyle(.secondary)
                }
                .replaySurface(expanded: detent == .large)
            }
        }.accessibilityIdentifier("replaySection-\(section)")
    }

    private func selectedMoment(_ trip: TripReplay) -> some View {
        ReplayTimeReader(transport: transport) { _ in
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Moment").font(.headline)
                Spacer()
                Text(selection, format: .dateTime.hour().minute().second()).font(.caption).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.16), value: Int(selection.timeIntervalSinceReferenceDate))
                    .accessibilityIdentifier("replaySelectedTime")
            }
            if let point = trip.point(at: selection) {
                HStack {
                    ReplayStat(title: "Speed", value: ReplayFormat.speed(point.speedKmh, unit: unit), symbol: "speedometer")
                    Spacer()
                    ReplayStat(title: "Altitude", value: ReplayFormat.meters(point.altitude), symbol: "mountain.2")
                }
            } else {
                Label("No Data At This Moment", systemImage: "slash.circle").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("replaySelectedMoment")
        }
    }

    private func playback(_ trip: TripReplay) -> some View {
        ReplayTimeReader(transport: transport) { _ in
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                transportButton(LocalizedStringKey(playing ? "Pause" : "Play"),
                                symbol: playing ? "pause.fill" : "play.fill", identifier: "replayPlayPause") {
                    if playing { pausePlayback() }
                    else {
                        reopenDetailsAfterDismiss = false
                        if selection >= trip.end { selection = trip.start }
                        playing = true
                    }
                }
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Spacer(minLength: 28)
                        Text(ReplayFormat.duration(max(0, selection.timeIntervalSince(trip.start))))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.16), value: Int(selection.timeIntervalSince(trip.start)))
                        Spacer(minLength: 0)
                        Menu {
                            Picker("Playback Speed", selection: $playbackRate) {
                                ForEach([1.0, 4, 8, 16], id: \.self) { Text("\(Int($0))×").tag($0) }
                            }
                        } label: { Text("\(Int(playbackRate))×").font(.caption.bold()).frame(minWidth: 28) }
                        .accessibilityLabel("Playback Speed")
                        .accessibilityIdentifier("replayPlaybackRate")
                    }
                    ReplayTimelineScrubber(value: Binding(get: { min(trip.duration, max(0, selection.timeIntervalSince(trip.start))) },
                        set: { selection = trip.start.addingTimeInterval($0) }), in: 0...max(1, trip.duration),
                        onDrag: { seconds, speed in
                            pausePlayback()
                            transport.scrub(trip.start.addingTimeInterval(seconds), speed: speed)
                        }, onRelease: { transport.release() })
                        .accessibilityLabel("Trip Timeline").accessibilityIdentifier("replayScrubber")
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 190).frame(height: 54)
                .glassEffect(.regular.interactive(), in: .capsule)
                transportButton("Previous Event", symbol: "chevron.left", identifier: "replayPreviousEvent",
                                enabled: trip.events.contains { $0.start < selection.addingTimeInterval(-0.1) }) {
                    selectEvent(trip, forward: false)
                }
                transportButton("Next Event", symbol: "chevron.right", identifier: "replayNextEvent",
                                enabled: trip.events.contains { $0.start > selection.addingTimeInterval(0.1) }) {
                    selectEvent(trip, forward: true)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 2)
        .frame(maxWidth: 430)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("replayFloatingControls")
        }
    }

    private func transportButton(_ title: LocalizedStringKey, symbol: String, identifier: String,
                                 enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(!enabled).opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title).help(Text(title))
        .accessibilityIdentifier(identifier)
    }

    private func selectEvent(_ trip: TripReplay, forward: Bool) {
        let candidates = trip.events.map(\.start).sorted()
        let date = forward ? candidates.first { $0 > selection.addingTimeInterval(0.1) }
            : candidates.last { $0 < selection.addingTimeInterval(-0.1) }
        if let date { playing = false; selection = date }
    }

}

// Only reserve the part of a window's side safe area actually covered by this
// sheet. A centred iPhone/iPad sheet gets zero extra padding; Duo's outer screen
// and a landscape phone reserve their system indicator/camera strip as needed.
private struct ReplaySheetSafeAreaReader: UIViewRepresentable {
    @Binding var insets: UIEdgeInsets
    final class Probe: UIView {
        var report: ((UIEdgeInsets) -> Void)?
        private var previous = UIEdgeInsets.zero
        override func didMoveToWindow() { super.didMoveToWindow(); updateInsets() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); updateInsets() }
        override func layoutSubviews() { super.layoutSubviews(); updateInsets() }
        private func updateInsets() {
            guard let window, bounds.width > 0 else { return }
            let frame = convert(bounds, to: window)
            let next = UIEdgeInsets(top: 0,
                left: max(0, window.safeAreaInsets.left - frame.minX), bottom: 0,
                right: max(0, window.safeAreaInsets.right - (window.bounds.maxX - frame.maxX)))
            guard abs(next.left - previous.left) > 0.5 || abs(next.right - previous.right) > 0.5 else { return }
            previous = next
            DispatchQueue.main.async { [weak self] in self?.report?(next) }
        }
    }
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.report = { if insets != $0 { insets = $0 } }
    }
}

private struct ReplayRouteMap: UIViewRepresentable {
    let trip: TripReplay
    let transport: ReplayTransport
    let overviewRequest: Int
    let sheetFraction: CGFloat
    let followsPosition: Bool
    let onStopFollowing: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LayoutMap {
        let map = LayoutMap()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = true
        map.showsUserLocation = false
        map.onResize = { [weak coordinator = context.coordinator] in coordinator?.fit() }
        context.coordinator.map = map
        transport.onFrame = { [weak coordinator = context.coordinator] in coordinator?.moveCursor(to: $0) }
        return map
    }

    func updateUIView(_ map: LayoutMap, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleUIView(_ map: LayoutMap, coordinator: Coordinator) {
        coordinator.stopCameraTracking()
        map.delegate = nil
    }

    final class LayoutMap: MKMapView {
        var onResize: (() -> Void)?
        private var previousSize = CGSize.zero
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != previousSize {
                previousSize = bounds.size
                DispatchQueue.main.async { [weak self] in self?.onResize?() }
            }
        }
    }

    final class Pin: MKPointAnnotation {
        let kind: Int
        init(kind: Int) { self.kind = kind; super.init() }
    }

    final class PositionDot: MKAnnotationView {
        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            configure()
        }
        required init?(coder: NSCoder) { super.init(coder: coder); configure() }
        private func configure() {
            frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            backgroundColor = .clear
            let halo = CALayer()
            halo.frame = bounds
            halo.cornerRadius = 18
            halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.16).cgColor
            let dot = CALayer()
            dot.frame = CGRect(x: 8, y: 8, width: 20, height: 20)
            dot.cornerRadius = 10
            dot.backgroundColor = UIColor.systemBlue.cgColor
            dot.borderColor = UIColor.white.cgColor
            dot.borderWidth = 2.5
            layer.addSublayer(halo)
            layer.addSublayer(dot)
            canShowCallout = false
            displayPriority = .required
            isAccessibilityElement = true
            accessibilityLabel = String(localized: "Replay Position")
            accessibilityIdentifier = "replayPositionDot"
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: LayoutMap?
        private var stamp = ""
        private var bounds = MKMapRect.null
        private var request = -1
        private var fraction: CGFloat = 0
        private let start = Pin(kind: 0)
        private let end = Pin(kind: 1)
        // MapKit positions annotation views asynchronously as its camera changes.
        // Keep the interpolated cursor in our own overlay so there is one writer.
        private let positionView = PositionDot(annotation: nil, reuseIdentifier: nil)
        private var cursorCoordinate: CLLocationCoordinate2D?
        private var currentTrip: TripReplay?
        private var following = false
        private var stopFollowing: (() -> Void)?
        private var followDate = Date.distantPast
        private var cameraLink: CADisplayLink?
        private var lastCameraTick: CFTimeInterval?
        private let cameraProxy = CameraProxy()
        private var travelHeading: Double?

        private final class CameraProxy: NSObject {
            weak var owner: Coordinator?
            @objc func frame(_ link: CADisplayLink) { owner?.cameraFrame(link) }
        }

        deinit { cameraLink?.invalidate() }

        func stopCameraTracking() {
            cameraLink?.invalidate()
            cameraLink = nil
            lastCameraTick = nil
        }

        private func startCameraTracking() {
            guard cameraLink == nil else { return }
            cameraProxy.owner = self
            let link = CADisplayLink(target: cameraProxy, selector: #selector(CameraProxy.frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            cameraLink = link
            link.add(to: .main, forMode: .common)
        }

        func update(_ value: ReplayRouteMap) {
            guard let map else { return }
            stopFollowing = value.onStopFollowing
            let beganFollowing = value.followsPosition && !following
            following = value.followsPosition
            if !following { stopCameraTracking() }
            let nextStamp = "\(value.trip.id)-\(value.trip.points.count)-\(value.trip.end.timeIntervalSinceReferenceDate)"
            let changed = stamp != nextStamp
            if changed {
                stamp = nextStamp
                currentTrip = value.trip
                map.removeOverlays(map.overlays)
                var outlines: [MKPolyline] = [], lines: [MKPolyline] = []
                bounds = .null
                for segment in value.trip.routeSegments {
                    let coordinates = segment.map(\.coordinate)
                    let outer = MKPolyline(coordinates: coordinates, count: coordinates.count)
                    outer.title = "outline"
                    outlines.append(outer)
                    lines.append(MKPolyline(coordinates: coordinates, count: coordinates.count))
                    bounds = bounds.union(outer.boundingMapRect)
                }
                map.addOverlays(outlines + lines, level: .aboveRoads)
                if let first = value.trip.points.first {
                    start.coordinate = first.coordinate
                    if !map.annotations.contains(where: { $0 === start }) { map.addAnnotation(start) }
                }
                if let last = value.trip.points.last {
                    end.coordinate = last.coordinate
                    if !map.annotations.contains(where: { $0 === end }) { map.addAnnotation(end) }
                }
            }
            start.title = value.trip.originName ?? String(localized: "Trip Start")
            end.title = value.trip.destinationName ?? String(localized: "Trip End")
            moveCursor(to: value.transport.currentDate)
            let requested = request >= 0 && request != value.overviewRequest
            let needsFit = changed || request != value.overviewRequest
            request = value.overviewRequest
            fraction = value.sheetFraction
            if beganFollowing { travelHeading = nil; startCameraTracking() }
            else if needsFit { fit(animated: requested) }
        }

        func moveCursor(to date: Date) {
            guard let map else { return }
            followDate = date
            if let coordinate = currentTrip?.displayCoordinate(at: date) {
                cursorCoordinate = coordinate
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if positionView.superview == nil {
                    positionView.isUserInteractionEnabled = false
                    map.addSubview(positionView)
                }
                positionView.isHidden = false
                positionDot()
                CATransaction.commit()
                if following { startCameraTracking() }
            } else {
                cursorCoordinate = nil
                positionView.isHidden = true
            }
        }

        private func positionDot() {
            guard let map, let coordinate = cursorCoordinate else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            positionView.center = map.convert(coordinate, toPointTo: map)
            CATransaction.commit()
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { positionDot() }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if following, mapView.subviews.contains(where: { view in
                view.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true
            }) {
                following = false
                stopCameraTracking()
                stopFollowing?()
            }
        }

        private func cameraFrame(_ link: CADisplayLink) {
            guard following, let map, let coordinate = cursorCoordinate else { return }
            let dt = min(1 / 15.0, max(1 / 240.0, link.timestamp - (lastCameraTick ?? link.timestamp - 1 / 60)))
            lastCameraTick = link.timestamp
            let speed = currentTrip?.point(at: followDate)?.speedKmh ?? 0
            // Ignore tiny stationary changes when deriving the road direction.
            if let a = currentTrip?.displayCoordinate(at: followDate.addingTimeInterval(-0.5)),
               let b = currentTrip?.displayCoordinate(at: followDate.addingTimeInterval(0.8)),
               CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) > 2 {
                let from = MKMapPoint(a), to = MKMapPoint(b)
                travelHeading = atan2(to.x - from.x, from.y - to.y) * 180 / .pi
            }
            let current = map.camera
            let alpha = 1 - exp(-dt / 0.28)
            let headingDelta = ((travelHeading ?? current.heading) - current.heading + 540)
                .truncatingRemainder(dividingBy: 360) - 180
            let heading = current.heading + max(-90 * dt, min(90 * dt, headingDelta * alpha))
            let targetDistance = min(1100, max(540, 540 + speed * 4))
            let distance = current.centerCoordinateDistance
                + (targetDistance - current.centerCoordinateDistance) * (1 - exp(-dt / 0.45))
            let pitch = Double(current.pitch) + (35 - Double(current.pitch)) * alpha
            let top = max(60, map.safeAreaInsets.top + 40)
            let bottom = max(top + 40, map.bounds.height * (1 - fraction))
            let anchor = CGPoint(x: map.bounds.midX, y: top + (bottom - top) * 0.52)
            // Derive the look-ahead from the target camera, never feed the last
            // rendered projection back into the next camera. MapKit renders that
            // projection asynchronously; a feedback loop oscillates at frame rate.
            let position = MKMapPoint(coordinate)
            let screenAngle = atan((0.5 - anchor.y / max(1, map.bounds.height)) * 2 * tan(Double.pi / 12))
            let pitchRadians = pitch * .pi / 180
            let ahead = distance * cos(pitchRadians) * (tan(pitchRadians + screenAngle) - tan(pitchRadians))
            let mapOffset = ahead / MKMetersPerMapPointAtLatitude(coordinate.latitude)
            let headingRadians = heading * .pi / 180
            let center = MKMapPoint(current.centerCoordinate)
            let target = MKMapPoint(x: position.x - sin(headingRadians) * mapOffset,
                                   y: position.y + cos(headingRadians) * mapOffset)
            let remaining = hypot(target.x - center.x, target.y - center.y) * MKMetersPerMapPointAtLatitude(coordinate.latitude)
            if remaining < 0.08, abs(headingDelta) < 0.05,
               abs(35 - Double(current.pitch)) < 0.05,
               abs(targetDistance - current.centerCoordinateDistance) < 0.5 {
                stopCameraTracking()
                return
            }
            let positionAlpha = remaining > 350 ? alpha : 1 - exp(-dt / 0.10)
            let next = MKMapPoint(x: center.x + (target.x - center.x) * positionAlpha,
                                 y: center.y + (target.y - center.y) * positionAlpha)
            map.setCamera(MKMapCamera(lookingAtCenter: next.coordinate,
                fromDistance: distance, pitch: CGFloat(pitch), heading: heading), animated: false)
            positionDot()
        }

        func fit(animated: Bool = false) {
            if following { return }
            guard let map, !bounds.isNull, map.bounds.width > 0, map.bounds.height > 0 else { return }
            let safeArea = map.window?.safeAreaInsets ?? .zero
            let top = max(65, max(map.safeAreaInsets.top, safeArea.top) + 64)
            let bottom = min(map.bounds.height - top - 100, max(60, map.bounds.height * fraction + 28))
            let padded = bounds.insetBy(dx: -max(40, bounds.width * 0.04), dy: -max(40, bounds.height * 0.04))
            map.setVisibleMapRect(padded, edgePadding: UIEdgeInsets(top: top,
                left: max(44, safeArea.left + 24), bottom: max(0, bottom), right: max(44, safeArea.right + 24)), animated: animated)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.title == "outline" ? .white.withAlphaComponent(0.55) : .systemBlue
            renderer.lineWidth = line.title == "outline" ? 7 : 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let identifier = "replay-pin-\(pin.kind)"
            if pin.kind == 2 {
                let dot = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? PositionDot)
                    ?? PositionDot(annotation: pin, reuseIdentifier: identifier)
                dot.annotation = pin
                return dot
            }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: identifier)
            view.annotation = pin
            view.glyphImage = UIImage(systemName: pin.kind == 0 ? "circle.fill" : pin.kind == 1 ? "flag.checkered" : "location.north.fill")
            view.markerTintColor = pin.kind == 0 ? .systemGreen : .systemBlue
            view.glyphTintColor = .white
            view.titleVisibility = pin.kind == 2 ? .hidden : .adaptive
            view.subtitleVisibility = .hidden
            view.canShowCallout = false
            view.displayPriority = .required
            return view
        }
    }
}

private extension View {
    func replaySurface(expanded: Bool) -> some View {
        modifier(ReplaySurface(expanded: expanded))
    }
}

private struct ReplaySurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let expanded: Bool

    func body(content: Content) -> some View {
        content.padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: colorScheme == .dark ? 0.55 : 0.45)
                        .opacity(expanded ? 0.16 : 0.12))
                    .animation(.easeInOut(duration: 0.35), value: expanded)
            }
    }
}

private struct ReplayEventTimeline: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trip: TripReplay
    let transport: ReplayTransport
    @Binding var selection: Date
    @Binding var playing: Bool
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.trip.id == rhs.trip.id && lhs.trip.events.count == rhs.trip.events.count
            && lhs.trip.events.last?.id == rhs.trip.events.last?.id && lhs.trip.end == rhs.trip.end
    }

    var body: some View {
        Chart {
            ForEach(trip.events) { event in
                RectangleMark(xStart: .value("Time", event.start), xEnd: .value("Time", event.end),
                              yStart: .value("Event", 0), yEnd: .value("Event", 1))
                    .foregroundStyle(event.action == .accelerating || event.action == .braking ? Color.orange : colorScheme == .dark ? .white : .accentColor)
                    .cornerRadius(3)
            }
        }
        .chartXScale(domain: trip.start...max(trip.end, trip.start.addingTimeInterval(1)))
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .chartOverlay { proxy in
            ReplayMetricCursor(trip: trip, metric: nil, transport: transport, proxy: proxy).allowsHitTesting(false)
        }
        .chartGesture { proxy in SpatialTapGesture().onEnded {
            if let date: Date = proxy.value(atX: $0.location.x) {
                playing = false; selection = min(trip.end, max(trip.start, date))
            }
        } }
        .frame(height: 24)
        .accessibilityLabel("Driving Events")
        .accessibilityIdentifier("replayEventTimeline")
    }
}

private struct ReplayTimelineScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onDrag: (Double, Double) -> Void
    let onRelease: () -> Void
    @State private var lastDrag: (x: CGFloat, time: TimeInterval)?

    init(value: Binding<Double>, in range: ClosedRange<Double>,
         onDrag: @escaping (Double, Double) -> Void, onRelease: @escaping () -> Void) {
        _value = value
        self.range = range
        self.onDrag = onDrag
        self.onRelease = onRelease
    }

    private var fraction: Double {
        min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 4)
            let count = max(8, min(48, Int(width / 7)))
            Canvas { context, size in
                for index in 0...count {
                    let progress = Double(index) / Double(count)
                    let height: CGFloat = index.isMultiple(of: 5) ? 12 : 6
                    let rect = CGRect(x: 1 + progress * width, y: (size.height - height) / 2, width: 2, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                 with: .color(progress <= fraction ? .mint.opacity(0.85) : .secondary.opacity(0.35)))
                }
                let cursor = CGRect(x: 1 + fraction * width, y: (size.height - 20) / 2, width: 2, height: 20)
                context.fill(Path(roundedRect: cursor, cornerRadius: 1), with: .color(.primary))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                let progress = min(1, max(0, (gesture.location.x - 1) / width))
                let now = ProcessInfo.processInfo.systemUptime
                if let previous = lastDrag {
                    let speed = Double(gesture.location.x - previous.x) / max(0.001, now - previous.time)
                    onDrag(range.lowerBound + progress * (range.upperBound - range.lowerBound), speed)
                } else { value = range.lowerBound + progress * (range.upperBound - range.lowerBound) }
                lastDrag = (gesture.location.x, now)
            }.onEnded { _ in lastDrag = nil; onRelease() })
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(ReplayFormat.duration(value))
        .accessibilityAdjustableAction { direction in
            let step = max(1, (range.upperBound - range.lowerBound) / 100)
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

private struct ReplayStat: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    var accent: Color? = nil
    var tintValue = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(accent ?? .secondary)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tintValue ? accent ?? .primary : .primary)
                .lineLimit(1).minimumScaleFactor(0.65)
        }
    }
}

private struct ReplayStatistics: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("colorGroupMode") private var colorGroupRaw = -1
    @AppStorage("darkKnightMode") private var legacyDarkKnight = false
    @AppStorage("orbColorPreset") private var orbPreset = 0
    let trip: TripReplay
    let unit: SpeedUnit
    var showsAll = false
    @State private var expanded = false
    private var orbAccent: Color {
        Color(hex: GorillaColorGroup.resolve(raw: colorGroupRaw, legacyDarkKnight: legacyDarkKnight)
            .dotColorHex(speed: trip.topSpeed ?? 0, preset: orbPreset)).readableAccent(in: colorScheme)
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.unit == rhs.unit && lhs.showsAll == rhs.showsAll && lhs.trip.id == rhs.trip.id
            && lhs.trip.points.count == rhs.trip.points.count && lhs.trip.points.last == rhs.trip.points.last
            && lhs.trip.events.count == rhs.trip.events.count
    }
    var body: some View {
        VStack(spacing: 12) {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
            ReplayStat(title: "Distance", value: String(format: "%.2f km", trip.distanceMeters / 1000), symbol: "point.bottomleft.forward.to.point.topright.scurvepath")
            ReplayStat(title: "Average Speed", value: ReplayFormat.speed(trip.averageSpeed, unit: unit), symbol: "speedometer")
            ReplayStat(title: "Top Speed", value: ReplayFormat.speed(trip.topSpeed, unit: unit), symbol: "arrow.up.right", accent: orbAccent, tintValue: true)
            ReplayStat(title: "Trip Duration", value: ReplayFormat.duration(trip.duration), symbol: "clock")
            if expanded || showsAll {
            ReplayStat(title: "Driving Time", value: ReplayFormat.duration(trip.drivingSeconds), symbol: "car")
            ReplayStat(title: "Observed Time", value: ReplayFormat.duration(trip.observedSeconds), symbol: "location")
            ReplayStat(title: "Peak G", value: trip.peakG.map { String(format: "%.2f G", $0) } ?? "—", symbol: "g.circle", accent: orbAccent, tintValue: true)
            ReplayStat(title: "Highest Altitude", value: ReplayFormat.meters(trip.highestAltitude), symbol: "mountain.2.fill", accent: Color.green.readableAccent(in: colorScheme))
                .accessibilityIdentifier("replayHighestAltitude")
            ReplayStat(title: "Driving Events", value: String(trip.events.count), symbol: "steeringwheel")
                .accessibilityIdentifier("replayEventCount")
            ReplayStat(title: "Lowest Altitude", value: ReplayFormat.meters(trip.lowestAltitude), symbol: "arrow.down.to.line", accent: Color.blue.readableAccent(in: colorScheme))
                .accessibilityIdentifier("replayLowestAltitude")
            }
        }
        if !showsAll { Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.44, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                Text(LocalizedStringKey(expanded ? "Show Less" : "Show All Metrics"))
                    .contentTransition(.opacity)
            }
            .font(.caption.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.plain).foregroundStyle(.tint)
        .accessibilityIdentifier("replayExpandStatistics")
        }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("replayStatistics")
    }
}

private struct ReplayCurrentEventBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: SpeedDrivingAction?

    var body: some View {
        ZStack(alignment: .trailing) {
            if let action {
                Label(LocalizedStringKey(action.resultTitle), systemImage: action.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(action == .accelerating || action == .braking ? Color.orange : colorScheme == .dark ? .white : .accentColor)
                    .id(action.rawValue)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.88, anchor: .trailing).combined(with: .opacity))
                    .accessibilityIdentifier("replayCurrentEvent")
            }
        }
        .frame(minHeight: 20)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82), value: action?.rawValue)
    }
}

private enum ReplayMetric {
    case speed(SpeedUnit), altitude
    func value(_ point: TripReplayPoint) -> Double? {
        switch self {
        case .speed(let unit): return point.speedKmh.map { unit.value(fromKmh: $0) }
        case .altitude: return point.altitude
        }
    }
    var title: String {
        switch self { case .speed(let unit): return unit.symbol; case .altitude: return "m" }
    }
    var identifier: String {
        switch self { case .speed: return "replaySpeedChart"; case .altitude: return "replayAltitudeChart" }
    }
    var tint: Color {
        switch self { case .speed: return .mint; case .altitude: return .cyan }
    }
}

private struct ReplayMetricChart: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trip: TripReplay
    let metric: ReplayMetric
    let transport: ReplayTransport
    @Binding var selection: Date
    var height: Double = 170
    var compact = false
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.trip.id == rhs.trip.id && lhs.trip.points.count == rhs.trip.points.count
            && lhs.trip.points.last == rhs.trip.points.last && lhs.metric.title == rhs.metric.title
            && lhs.height == rhs.height && lhs.compact == rhs.compact
    }
    private struct Datum: Identifiable {
        let id: Int
        let time: Date
        let value: Double
        let segment: Int
    }
    @State private var cachedData: [Datum] = []
    private var data: [Datum] {
        var result: [Datum] = []
        var segment = 0
        for (index, point) in trip.points.enumerated() {
            if index > 0 && (!trip.points[index - 1].connects(to: point) || metric.value(trip.points[index - 1]) == nil) { segment += 1 }
            if let value = metric.value(point) { result.append(.init(id: index, time: point.time, value: value, segment: segment)) }
        }
        return result
    }

    var body: some View {
        let samples = cachedData
        let baseline = 0.0
        Group {
        if samples.isEmpty {
            Group {
                if compact { Text("—").font(.caption).foregroundStyle(.secondary) }
                else { ContentUnavailableView("No Reliable Samples", systemImage: "chart.xyaxis.line") }
            }.frame(height: height).accessibilityIdentifier(metric.identifier)
        } else {
            Chart {
                ForEach(samples) { datum in
                    AreaMark(x: .value("Time", datum.time), yStart: .value(metric.title, baseline),
                             yEnd: .value(metric.title, datum.value), series: .value("Segment", datum.segment))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [metric.tint.opacity(0.32), metric.tint.opacity(0.025)],
                                                        startPoint: .top, endPoint: .bottom))
                }
                ForEach(samples) { datum in
                    LineMark(x: .value("Time", datum.time), y: .value(metric.title, datum.value), series: .value("Segment", datum.segment))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(metric.tint).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.12))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number, format: .number.precision(.fractionLength(0...1)))
                                .font(.caption2)
                                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.7) : Color.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(ReplayFormat.duration(max(0, date.timeIntervalSince(trip.start))))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXScale(domain: trip.start...max(trip.end, trip.start.addingTimeInterval(1)))
            .chartOverlay { proxy in
                if !compact {
                    ReplayMetricCursor(trip: trip, metric: metric, transport: transport, proxy: proxy)
                        .allowsHitTesting(false)
                }
            }
            // A tap selects a moment without consuming vertical sheet scrolling.
            // Continuous scrubbing remains available on the pinned timeline slider.
            .chartGesture { proxy in
                SpatialTapGesture().onEnded {
                    if let date: Date = proxy.value(atX: $0.location.x) {
                        selection = min(trip.end, max(trip.start, date))
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXAxis(compact ? .hidden : .automatic)
            .chartYAxis(compact ? .hidden : .automatic)
            .frame(height: height)
            .accessibilityIdentifier(metric.identifier)
        }
        }
        .onChange(of: "\(trip.id)-\(trip.points.count)-\(trip.end)-\(metric.title)", initial: true) { _, _ in
            cachedData = data
        }
    }
}

// Only this lightweight overlay observes playback time; the sampled curves stay cached.
private struct ReplayMetricCursor: View {
    @Environment(\.colorScheme) private var colorScheme
    let trip: TripReplay
    let metric: ReplayMetric?
    @ObservedObject var transport: ReplayTransport
    let proxy: ChartProxy

    var body: some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plot = geometry[anchor]
                Canvas { context, _ in
                    guard let x = proxy.position(forX: transport.selection) else { return }
                    var line = Path()
                    line.move(to: CGPoint(x: plot.minX + x, y: plot.minY))
                    line.addLine(to: CGPoint(x: plot.minX + x, y: plot.maxY))
                    context.stroke(line, with: .color((colorScheme == .dark ? Color.white : .black).opacity(0.3)),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                    if let metric, let point = trip.point(at: transport.selection), let value = metric.value(point),
                       let y = proxy.position(forY: value) {
                        let dot = CGRect(x: plot.minX + x - 3, y: plot.minY + y - 3, width: 6, height: 6)
                        context.fill(Path(ellipseIn: dot), with: .color(metric.tint))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

enum ReplayFormat {
    static func title(_ trip: TripReplay) -> String {
        let name = trip.destinationName ?? String(localized: "Recorded Journey")
        return trip.isHabitualRoute ? name + " (" + String(localized: "Habitual Route") + ")" : name
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    static func speed(_ kmh: Double?, unit: SpeedUnit) -> String {
        kmh.map { String(format: "%.0f %@", unit.value(fromKmh: $0), unit.symbol) } ?? "—"
    }
    static func meters(_ value: Double?) -> String { value.map { String(format: "%.0f m", $0) } ?? "—" }
}
