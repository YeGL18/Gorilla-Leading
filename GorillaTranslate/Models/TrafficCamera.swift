import SwiftUI
import MapKit
import AVFoundation

struct TrafficCamera: Codable, Identifiable {
    let id: String
    let kind: String
    let name: String
    let english: String
    let latitude: Double
    let longitude: Double
    var roadSpeedLimitKmh: Int? = nil
    var roadSpeedMatchDistance: Double? = nil
    var displayedSpeedLimitKmh: Int { roadSpeedLimitKmh ?? 50 }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var title: String { kind == "sec" ? String(localized: "測速相機") : String(localized: "衝紅燈相機") }
    var symbol: String { kind == "sec" ? "camera.fill" : "trafficlight.fill" }
    var localizedName: String {
        let language = LanguageManager.languageCode
        return language.hasPrefix("zh") || language.hasPrefix("yue") ? name : english
    }
    // Cardinal direction is supplied in the site description, not a surveyed heading.
    var direction: Double? {
        let directions: [(String, Double)] = [("NORTHEAST",45),("NORTHWEST",315),("SOUTHEAST",135),
            ("SOUTHWEST",225),("NORTH",0),("SOUTH",180),("EAST",90),("WEST",270)]
        let text = english.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        return directions.first { text.contains("(\($0.0)BOUND)") }?.1
    }
}

struct CameraApproachPolicy {
    private var previous: [String: (distance: Double, date: Date)] = [:]
    private var alerted = Set<String>()
    private var lastAlert = Date.distantPast

    static func angle(_ first: Double, _ second: Double) -> Double {
        abs((first - second + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    static func warningRadius(speed: Double) -> Double { min(300, max(30, speed * 8)) }

    mutating func update(location: CLLocation, cameras: [TrafficCamera], driving: Bool,
                         now: Date) -> (camera: TrafficCamera, distance: Double, shouldSound: Bool)? {
        guard driving, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35,
              now.timeIntervalSince(location.timestamp) >= -2,
              now.timeIntervalSince(location.timestamp) <= 5,
              location.speed >= 3, location.course >= 0,
              location.courseAccuracy < 0 || location.courseAccuracy <= 30 else {
            previous.removeAll()
            return nil
        }
        let radius = Self.warningRadius(speed: location.speed)
        var candidates: [(TrafficCamera, Double)] = []
        for camera in cameras {
            let distance = location.distance(from: CLLocation(latitude: camera.latitude, longitude: camera.longitude))
            if distance > 800 { alerted.remove(camera.id); previous.removeValue(forKey: camera.id); continue }
            let old = previous[camera.id]
            // Do not count duplicate or out-of-order fixes as approach evidence.
            guard old == nil || location.timestamp > old!.date else { continue }
            previous[camera.id] = (distance, location.timestamp)
            guard distance <= radius, distance > 25, let old,
                  location.timestamp.timeIntervalSince(old.date) <= 5, old.distance - distance >= 2 else { continue }
            let a = location.coordinate.latitude * .pi / 180
            let b = camera.latitude * .pi / 180
            let d = (camera.longitude - location.coordinate.longitude) * .pi / 180
            let bearing = (atan2(sin(d) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(d)) * 180 / .pi + 360)
                .truncatingRemainder(dividingBy: 360)
            let angle = Self.angle(location.course, bearing)
            let crossTrack = distance * sin(angle * .pi / 180)
            guard angle <= 35, abs(crossTrack) <= max(25, location.horizontalAccuracy + 10) else { continue }
            if let direction = camera.direction, Self.angle(location.course, direction) > 65 { continue }
            candidates.append((camera, distance))
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        let sound = !alerted.contains(nearest.0.id) && now.timeIntervalSince(lastAlert) >= 12
        if sound { alerted.insert(nearest.0.id); lastAlert = now }
        return (nearest.0, nearest.1, sound)
    }
}

enum MapMarkerOverviewMode {
    case nearby, cameras, meters, landmarks, airport
}

enum CameraSpeechFormat: String, CaseIterable, Identifiable {
    case beepOnly, number, short, full
    static let preferenceKey = "trafficCameraSpeechFormat"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beepOnly: return String(localized: "只嗶嗶兩聲")
        case .number: return String(localized: "嗶嗶 + 80")
        case .short: return String(localized: "嗶嗶 + 簡短限速")
        case .full: return String(localized: "嗶嗶 + 限速及單位")
        }
    }
}

enum CameraSpeechLanguage: String, CaseIterable, Identifiable {
    case english = "en", cantonese = "yue", traditionalChinese = "zh-Hant", simplifiedChinese = "zh-Hans"
    case japanese = "ja", korean = "ko", french = "fr", german = "de", spanish = "es", portuguese = "pt"
    case italian = "it", dutch = "nl", polish = "pl", turkish = "tr", russian = "ru", ukrainian = "uk"
    case indonesian = "id", malay = "ms", thai = "th", vietnamese = "vi"
    static let preferenceKey = "trafficCameraSpeechLanguage"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .english: "English"
        case .cantonese: "粵語"
        case .traditionalChinese: "繁體中文"
        case .simplifiedChinese: "简体中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .portuguese: "Português"
        case .italian: "Italiano"
        case .dutch: "Nederlands"
        case .polish: "Polski"
        case .turkish: "Türkçe"
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .indonesian: "Bahasa Indonesia"
        case .malay: "Bahasa Melayu"
        case .thai: "ไทย"
        case .vietnamese: "Tiếng Việt"
        }
    }
    var voiceTags: [String] {
        switch self {
        case .english: ["en-GB", "en-US"]
        case .cantonese: ["yue-HK", "zh-HK"]
        case .traditionalChinese: ["zh-TW"]
        case .simplifiedChinese: ["zh-CN"]
        case .japanese: ["ja-JP"]
        case .korean: ["ko-KR"]
        case .french: ["fr-FR", "fr-CA"]
        case .german: ["de-DE"]
        case .spanish: ["es-ES", "es-MX"]
        case .portuguese: ["pt-PT", "pt-BR"]
        case .italian: ["it-IT"]
        case .dutch: ["nl-NL", "nl-BE"]
        case .polish: ["pl-PL"]
        case .turkish: ["tr-TR"]
        case .russian: ["ru-RU"]
        case .ukrainian: ["uk-UA"]
        case .indonesian: ["id-ID"]
        case .malay: ["ms-MY"]
        case .thai: ["th-TH"]
        case .vietnamese: ["vi-VN"]
        }
    }
    static func from(_ tag: String) -> Self? {
        let code = tag.replacingOccurrences(of: "_", with: "-").lowercased()
        if code.hasPrefix("yue") || code == "zh-hk" || code.hasPrefix("zh-hant-hk") { return .cantonese }
        if code.hasPrefix("zh-hant") || code == "zh-tw" || code == "zh-mo" { return .traditionalChinese }
        if code.hasPrefix("zh") { return .simplifiedChinese }
        let base = code.split(separator: "-").first.map(String.init) ?? ""
        return allCases.first { $0.rawValue.lowercased() == base }
    }
    static func resolve(preference: String, appLanguage: String, systemLanguages: [String]) -> Self {
        let requested = preference == "app" ? appLanguage : (preference == "system" ? systemLanguages.first ?? "en" : preference)
        return from(requested) ?? .english
    }
    func acceptsVoice(_ tag: String) -> Bool {
        Self.from(tag) == self
    }
}

enum CameraAlertSpeech {
    static func text(for camera: TrafficCamera?, format: CameraSpeechFormat = .full,
                     speedKmh: Double? = nil, includeSlowDown: Bool = true,
                     announceRedLight: Bool = true, language: CameraSpeechLanguage = .english) -> String {
        guard format != .beepOnly else { return "" }
        let phrases = phrases(language)
        if camera?.kind == "rlc" { return announceRedLight ? phrases.redLight : "" }
        let limit = camera?.displayedSpeedLimitKmh ?? 80
        if format == .number { return "\(limit)" }
        let warning = includeSlowDown && speedKmh.map { $0.isFinite && $0 > Double(limit) } == true
            ? phrases.slowDown + " " : ""
        let sentence = format == .full ? phrases.full : phrases.short
        return warning + sentence.replacingOccurrences(of: "{limit}", with: String(limit))
    }
    private struct Phrases { let short: String; let full: String; let slowDown: String; let redLight: String }
    private static func phrases(_ language: CameraSpeechLanguage) -> Phrases {
        let values: (String, String, String, String)
        switch language {
        case .english: values = ("Speed limit is {limit}.", "Speed limit is {limit} kilometers per hour.", "Slow down.", "Red-light camera ahead.")
        case .cantonese: values = ("限速{limit}。", "限速每小時{limit}公里。", "請減速。", "前面有衝紅燈相機。")
        case .traditionalChinese: values = ("限速{limit}。", "速限每小時{limit}公里。", "請減速。", "前方有闖紅燈照相機。")
        case .simplifiedChinese: values = ("限速{limit}。", "限速每小时{limit}公里。", "请减速。", "前方有闯红灯摄像头。")
        case .japanese: values = ("制限速度は{limit}です。", "制限速度は時速{limit}キロメートルです。", "速度を落としてください。", "この先に信号無視取締カメラがあります。")
        case .korean: values = ("제한 속도는 {limit}입니다.", "제한 속도는 시속 {limit}킬로미터입니다.", "속도를 줄이세요.", "전방에 신호 위반 단속 카메라가 있습니다.")
        case .french: values = ("Vitesse limitée à {limit}.", "Vitesse limitée à {limit} kilomètres par heure.", "Ralentissez.", "Radar de feu rouge à venir.")
        case .german: values = ("Tempolimit {limit}.", "Tempolimit {limit} Kilometer pro Stunde.", "Bitte langsamer fahren.", "Rotlichtkamera voraus.")
        case .spanish: values = ("El límite de velocidad es {limit}.", "El límite de velocidad es {limit} kilómetros por hora.", "Reduzca la velocidad.", "Cámara de semáforo en rojo más adelante.")
        case .portuguese: values = ("O limite de velocidade é {limit}.", "O limite de velocidade é {limit} quilómetros por hora.", "Reduza a velocidade.", "Câmara de controlo de semáforo à frente.")
        case .italian: values = ("Il limite di velocità è {limit}.", "Il limite di velocità è {limit} chilometri orari.", "Rallentare.", "Telecamera per il controllo del semaforo rosso più avanti.")
        case .dutch: values = ("De maximumsnelheid is {limit}.", "De maximumsnelheid is {limit} kilometer per uur.", "Verminder uw snelheid.", "Roodlichtcamera verderop.")
        case .polish: values = ("Ograniczenie prędkości do {limit}.", "Ograniczenie prędkości do {limit} kilometrów na godzinę.", "Zwolnij.", "Przed tobą kamera rejestrująca przejazd na czerwonym świetle.")
        case .turkish: values = ("Hız sınırı {limit}.", "Hız sınırı saatte {limit} kilometre.", "Yavaşlayın.", "İleride kırmızı ışık kamerası var.")
        case .russian: values = ("Ограничение скорости {limit}.", "Ограничение скорости {limit} километров в час.", "Снизьте скорость.", "Впереди камера контроля проезда на красный свет.")
        case .ukrainian: values = ("Обмеження швидкості {limit}.", "Обмеження швидкості {limit} кілометрів на годину.", "Зменште швидкість.", "Попереду камера контролю проїзду на червоне світло.")
        case .indonesian: values = ("Batas kecepatan {limit}.", "Batas kecepatan {limit} kilometer per jam.", "Kurangi kecepatan.", "Ada kamera lampu merah di depan.")
        case .malay: values = ("Had laju {limit}.", "Had laju {limit} kilometer sejam.", "Kurangkan kelajuan.", "Kamera lampu isyarat merah di hadapan.")
        case .thai: values = ("จำกัดความเร็ว {limit}", "จำกัดความเร็ว {limit} กิโลเมตรต่อชั่วโมง", "กรุณาลดความเร็ว", "ข้างหน้ามีกล้องตรวจจับการฝ่าไฟแดง")
        case .vietnamese: values = ("Giới hạn tốc độ là {limit}.", "Giới hạn tốc độ là {limit} ki lô mét mỗi giờ.", "Hãy giảm tốc độ.", "Phía trước có camera ghi hình vượt đèn đỏ.")
        }
        return Phrases(short: values.0, full: values.1, slowDown: values.2, redLight: values.3)
    }
}

struct CameraMarkerPolicy {
    static func visible(_ cameras: [TrafficCamera], enabled: Bool, location: CLLocation?,
                        mode: MapMarkerOverviewMode) -> [TrafficCamera] {
        if mode == .meters || mode == .landmarks || mode == .airport { return [] }
        if mode == .cameras { return cameras }
        guard enabled, let location, location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return [] }
        return cameras.filter {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 1000
        }
    }
}

@MainActor
final class MapMarkerOverviewState: ObservableObject {
    static let shared = MapMarkerOverviewState()
    @Published var mode: MapMarkerOverviewMode = .nearby
    @Published var airportTarget: AirportDropOffCatalog.Zone?
    @Published var airportWaitingForLocation = false
    var airportAnimateEntry = false
}

struct MapMarkerOverviewMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    let choose: (MapMarkerOverviewMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("地圖瀏覽").font(.headline).padding(.horizontal, 12).padding(.vertical, 8)
            option("衝紅燈及測速相機", symbol: "camera.fill", color: .orange, mode: .cameras)
            option("全港咪錶位", symbol: "parkingsign.circle", color: Color(red: 70/255, green: 173/255, blue: 184/255), mode: .meters)
            option("全港標點", symbol: "mappin.and.ellipse", color: .yellow, mode: .landmarks)
            option("機場落客指南", symbol: "airplane.departure", color: .cyan, mode: .airport)
        }
        .padding(8).frame(width: 280)
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
        .presentationCompactAdaptation(.popover)
    }

    private func option(_ title: LocalizedStringKey, symbol: String, color: Color, mode: MapMarkerOverviewMode) -> some View {
        Button { choose(mode) } label: {
            Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(color) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class TrafficCameraStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private struct Catalog: Decodable { let cameras: [TrafficCamera] }
    static let shared = TrafficCameraStore()
    let cameras: [TrafficCamera]
    @Published private(set) var nearby: TrafficCamera?
    @Published private(set) var distance = 0
    @Published var selected: TrafficCamera?
    private var policy = CameraApproachPolicy()
    private var player: AVAudioPlayer?
    private let speaker = AVSpeechSynthesizer()
    private var pendingSpeech: AVSpeechUtterance?
    private var expiry: Task<Void, Never>?

    override init() {
        if let url = Bundle.main.url(forResource: "traffic_cameras", withExtension: "json"),
           let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Catalog.self, from: data) {
            cameras = catalog.cameras
        } else { cameras = [] }
        super.init()
        speaker.usesApplicationAudioSession = true
    }

    func update(_ location: CLLocation, driving: Bool) {
        guard UserDefaults.standard.object(forKey: "trafficCameraEnabled") as? Bool ?? true,
              UIApplication.shared.applicationState == .active else { clear(); return }
        guard let result = policy.update(location: location, cameras: cameras, driving: driving, now: Date()) else {
            clear(); return
        }
        nearby = result.camera
        distance = Int(result.distance / 10) * 10
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
        if result.shouldSound && (UserDefaults.standard.object(forKey: "trafficCameraSound") as? Bool ?? true) {
            playSound(for: result.camera, speedKmh: location.speed * 3.6)
        }
    }

    func clear() { nearby = nil; expiry?.cancel(); expiry = nil }

    func playSound(for camera: TrafficCamera? = nil, speedKmh: Double? = nil) {
        stopAudio()
        let defaults = UserDefaults.standard
        let format = CameraSpeechFormat(rawValue: defaults.string(forKey: CameraSpeechFormat.preferenceKey) ?? "") ?? .full
        if format != .beepOnly {
            let requested = CameraSpeechLanguage.resolve(
                preference: defaults.string(forKey: CameraSpeechLanguage.preferenceKey) ?? "app",
                appLanguage: LanguageManager.languageCode, systemLanguages: Locale.preferredLanguages)
            let plan = CameraSystemVoice.resolve(requested)
            let text = CameraAlertSpeech.text(for: camera, format: format, speedKmh: speedKmh,
                includeSlowDown: defaults.object(forKey: "trafficCameraSlowDown") as? Bool ?? true,
                announceRedLight: defaults.object(forKey: "trafficCameraRedLightSpeech") as? Bool ?? true,
                language: plan.language)
            if !text.isEmpty, let voice = plan.voice {
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                pendingSpeech = utterance
            }
        }
        // Match the app's ambient session: respect silent mode, mix with music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let url = Bundle.main.url(forResource: "camera_alert", withExtension: "wav"),
              let audio = try? AVAudioPlayer(contentsOf: url) else { speakPendingAlert(); return }
        player = audio
        audio.delegate = self
        player?.volume = 0.8
        if !audio.play() { speakPendingAlert() }
    }

    func stopAudio() {
        pendingSpeech = nil
        player?.stop()
        player = nil
        speaker.stopSpeaking(at: .immediate)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identifier else { return }
            self.speakPendingAlert()
        }
    }

    private func speakPendingAlert() {
        guard let utterance = pendingSpeech else { return }
        pendingSpeech = nil
        speaker.speak(utterance)
    }
}

/// Ask iOS for its preferred available voice; do not pin a gender/model or Siri ID.
enum CameraSystemVoice {
    struct Plan { let language: CameraSpeechLanguage; let voice: AVSpeechSynthesisVoice? }
    static func resolve(_ language: CameraSpeechLanguage) -> Plan {
        if let voice = availableVoice(language) { return Plan(language: language, voice: voice) }
        return Plan(language: .english, voice: availableVoice(.english))
    }
    private static func availableVoice(_ language: CameraSpeechLanguage) -> AVSpeechSynthesisVoice? {
        if let preferred = AVSpeechSynthesisVoice(language: nil), language.acceptsVoice(preferred.language),
           !preferred.voiceTraits.contains(.isNoveltyVoice), !preferred.voiceTraits.contains(.isPersonalVoice) { return preferred }
        for tag in language.voiceTags {
            if let voice = AVSpeechSynthesisVoice(language: tag), language.acceptsVoice(voice.language),
               !voice.voiceTraits.contains(.isNoveltyVoice), !voice.voiceTraits.contains(.isPersonalVoice) { return voice }
        }
        return AVSpeechSynthesisVoice.speechVoices().filter {
            language.acceptsVoice($0.language) && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }.sorted { $0.quality.rawValue > $1.quality.rawValue }.first
    }
}

final class TrafficCameraAnnotation: NSObject, MKAnnotation {
    let camera: TrafficCamera
    var coordinate: CLLocationCoordinate2D { camera.coordinate.wgs84ToGCJ02 }
    var title: String? { camera.title }
    var subtitle: String? { camera.localizedName }
    init(_ camera: TrafficCamera) { self.camera = camera }
}

@MainActor
final class TrafficCameraMapLayer {
    private var annotations: [String: TrafficCameraAnnotation] = [:]
    func sync(_ map: MKMapView, enabled: Bool, location: CLLocation? = nil,
              mode: MapMarkerOverviewMode = .nearby) {
        let cameras = CameraMarkerPolicy.visible(TrafficCameraStore.shared.cameras,
                                                enabled: enabled, location: location, mode: mode)
        let wanted = Set(cameras.map(\.id))
        let removed = annotations.values.filter { !wanted.contains($0.camera.id) }
        for point in removed { annotations.removeValue(forKey: point.camera.id) }
        if !removed.isEmpty { map.removeAnnotations(removed) }
        let added = cameras.filter { annotations[$0.id] == nil }.map(TrafficCameraAnnotation.init)
        for point in added { annotations[point.camera.id] = point }
        if !added.isEmpty { map.addAnnotations(added) }
    }

    static func view(_ map: MKMapView, annotation: MKAnnotation) -> MKAnnotationView? {
        guard let point = annotation as? TrafficCameraAnnotation else { return nil }
        let key = "TrafficCamera"
        let view = (map.dequeueReusableAnnotationView(withIdentifier: key) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: key)
        view.annotation = annotation
        view.accessibilityIdentifier = "trafficCamera.\(point.camera.id)"
        view.glyphImage = UIImage(systemName: point.camera.symbol)
        view.markerTintColor = point.camera.kind == "sec" ? .systemOrange : .systemRed
        view.glyphTintColor = .white
        view.canShowCallout = false
        view.titleVisibility = .hidden
        view.displayPriority = .defaultLow
        return view
    }
}

struct TrafficCameraWarningView: View {
    @ObservedObject private var store = TrafficCameraStore.shared
    var body: some View {
        if let camera = store.nearby {
            HStack(spacing: 10) {
                Image(systemName: camera.symbol).foregroundStyle(.orange)
                Text(camera.title).fontWeight(.semibold)
                Text("\(store.distance) m").monospacedDigit()
            }
            .font(.subheadline).padding(.horizontal, 18).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
}

private struct CameraPopupTransitionModifier: ViewModifier {
    var blur: CGFloat
    var y: CGFloat
    var scale: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: blur).offset(y: y).scaleEffect(scale)
    }
}

struct TrafficCameraDetailOverlay: View {
    @ObservedObject private var store = TrafficCameraStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var detailHeight: CGFloat = 0
    var body: some View {
        if let camera = store.selected {
            GeometryReader { geometry in
                let landscape = geometry.size.width > geometry.size.height
                ZStack {
                    Color.black.opacity(0.001).ignoresSafeArea()
                        .onTapGesture { dismiss() }
                    Group {
                        if geometry.size.height < 450 {
                            ScrollView {
                                detail(camera)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailHeight = $0 }
                            }
                                .scrollIndicators(.hidden)
                                .frame(height: min(detailHeight > 0 ? detailHeight : geometry.size.height - 80,
                                                   max(120, geometry.size.height - 80)))
                        } else {
                            detail(camera).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: 196)
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                    .tint(colorScheme == .dark ? .white : .accentColor)
                    .padding(.horizontal, 28)
                    .offset(y: landscape ? 0 : 56)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: landscape ? .trailing : .center)
                    .accessibilityIdentifier("trafficCameraDetail")
                }
            }
            .transition(.asymmetric(
                insertion: .modifier(
                    active: CameraPopupTransitionModifier(blur: 28, y: 10, scale: 0.985),
                    identity: CameraPopupTransitionModifier(blur: 0, y: 0, scale: 1)),
                removal: .modifier(
                    active: CameraPopupTransitionModifier(blur: 28, y: 0, scale: 0.985),
                    identity: CameraPopupTransitionModifier(blur: 0, y: 0, scale: 1))
            ).combined(with: .opacity))
        }
    }

    private func detail(_ camera: TrafficCamera) -> some View {
        VStack(spacing: 12) {
                        HStack {
                            Image(systemName: camera.symbol)
                                .foregroundStyle(camera.kind == "sec" ? .orange : .red)
                            Text(camera.title).font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        Text(camera.localizedName)
                            .font(.system(size: 14, weight: .medium))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        if camera.kind == "sec" {
                        Divider()
                        Text("道路參考限速").font(.caption).foregroundStyle(.secondary)
                            VStack(spacing: 2) {
                                Text("\(camera.displayedSpeedLimitKmh)").font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text("km/h").font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        if camera.roadSpeedLimitKmh == nil {
                            Text("預設限速（未配對路段資料）")
                                .font(.caption2).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Text("道路資料配對僅供參考，非相機執法設定；以現場限速牌為準。")
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Link("限速資料來源", destination: URL(string: "https://data.gov.hk/en-data/dataset/hk-td-tis_15-road-network-v2/resource/1c00e10b-f213-4d88-a3c4-202222f6639e")!)
                            .font(.caption)
                        }
                    }
                    .foregroundStyle(.primary)
    }

    private func dismiss() { withAnimation(.smooth(duration: 0.25)) { store.selected = nil } }
}

struct TrafficCameraSettingsView: View {
    @AppStorage("trafficCameraEnabled") private var enabled = true
    @AppStorage("trafficCameraSound") private var sound = true
    @AppStorage(CameraSpeechFormat.preferenceKey) private var speechFormat = CameraSpeechFormat.full.rawValue
    @AppStorage(CameraSpeechLanguage.preferenceKey) private var speechLanguage = "app"
    @AppStorage("trafficCameraSlowDown") private var slowDown = true
    @AppStorage("trafficCameraRedLightSpeech") private var redLightSpeech = true
    var body: some View {
        Form {
            Section {
                Toggle("交通相機標點及接近提醒", isOn: $enabled)
                Toggle("相機提醒音效", isOn: $sound).disabled(!enabled)
                Picker("朗讀內容", selection: $speechFormat) {
                    ForEach(CameraSpeechFormat.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .disabled(!enabled || !sound)
                if speechFormat != CameraSpeechFormat.beepOnly.rawValue {
                    Picker("朗讀語言", selection: $speechLanguage) {
                        Text("跟隨 App 語言").tag("app")
                        Text("跟隨系統語言").tag("system")
                        ForEach(CameraSpeechLanguage.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
                    }
                    .accessibilityIdentifier("cameraSpeechLanguage")
                    .disabled(!enabled || !sound)
                    if speechFormat != CameraSpeechFormat.number.rawValue {
                        Toggle("超速時加讀減速提醒", isOn: $slowDown)
                            .disabled(!enabled || !sound)
                    }
                    Toggle("朗讀衝紅燈相機提醒", isOn: $redLightSpeech)
                        .disabled(!enabled || !sound)
                }
                Button("試聽相機提醒", systemImage: "speaker.wave.2") { TrafficCameraStore.shared.playSound() }
                NavigationLink { CameraVoiceHelpView() } label: {
                    Label("聲線與下載", systemImage: "person.wave.2")
                }.accessibilityIdentifier("cameraVoiceHelp")
            } footer: {
                Text("App 開啟並偵測到開車時，約提前 8 秒車程提醒前方固定相機（距離約 30–300 米）。先播放兩聲提示音，再按所選語言朗讀；只有超速才會加讀減速提醒。沒有該語言聲線時改用英文。音效遵從 iPhone 靜音設定。")
            }
            Section {
                NavigationLink { TrafficDataSourcesView() } label: {
                    Label("資料來源與使用條款", systemImage: "doc.text")
                }
            } footer: {
                Text("香港特別行政區政府運輸署／DATA.GOV.HK")
            }
        }
        .navigationTitle("交通相機")
        .onChange(of: enabled) { _, value in
            if !value {
                TrafficCameraStore.shared.clear(); TrafficCameraStore.shared.selected = nil
                TrafficCameraStore.shared.stopAudio()
            }
        }
        .onChange(of: sound) { _, value in if !value { TrafficCameraStore.shared.stopAudio() } }
    }
}

struct CameraVoiceHelpView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CameraSpeechLanguage.preferenceKey) private var speechLanguage = "app"
    @State private var plan: CameraSystemVoice.Plan?
    private var requested: CameraSpeechLanguage {
        CameraSpeechLanguage.resolve(preference: speechLanguage, appLanguage: LanguageManager.languageCode,
                                     systemLanguages: Locale.preferredLanguages)
    }
    var body: some View {
        List {
            Section("自動聲線") {
                LabeledContent("朗讀語言", value: requested.title)
                    .accessibilityIdentifier("cameraVoiceLanguage")
                    .accessibilityValue(requested.title)
                if let plan {
                    LabeledContent("目前聲線", value: plan.voice?.name ?? String(localized: "只有提示音"))
                    if plan.language != requested {
                        Text("此裝置未提供所選語言的可用聲線，會改用英文朗讀。")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Gorilla 按朗讀語言自動使用 iOS 提供的聲線，無需手動選擇模型。部分 Siri 聲線不開放給第三方 App，屆時會使用同語言的可用聲線。")
            }
            Section("下載聲線") {
                Text("iPhone「設定」→「輔助使用」→「閱讀與朗讀」（舊版本為「朗讀內容」）→「聲音」，再選擇朗讀語言。")
                Text("按聲線旁的下載圖標取得增強或優質版本，無需開啟 VoiceOver。App 不會自動下載聲線。")
                Link("Apple 聲線下載說明", destination: URL(string: "https://support.apple.com/en-ie/111798")!)
                Text("下載後返回 App，再按「試聽相機提醒」。沒有可用英文聲線時，只播放兩聲提示音。")
            }
        }
        .navigationTitle("聲線與下載")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            plan = CameraSystemVoice.resolve(requested)
        }
    }
}

struct TrafficDataSourcesView: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        List {
            Section("資料署名") {
                Text("香港特別行政區政府運輸署／DATA.GOV.HK")
                Text("交通相機、道路限速及咪錶資料由香港特別行政區政府運輸署提供，經 DATA.GOV.HK 發布。相關資料的知識產權屬香港特別行政區政府及有關資料提供者所有。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("離線資料下載：2026-10-26")
                LabeledContent("測速相機", value: "\(TrafficCameraStore.shared.cameras.filter { $0.kind == "sec" }.count)")
                LabeledContent("衝紅燈相機", value: "\(TrafficCameraStore.shared.cameras.filter { $0.kind == "rlc" }.count)")
                Link("測速相機資料", destination: URL(string: "https://data.gov.hk/en-data/dataset/hk-td-tis_26-locations-of-sec")!)
                Link("衝紅燈相機資料", destination: URL(string: "https://data.gov.hk/en-data/dataset/hk-td-tis_25-junctions-with-rlc")!)
                Link("道路限速資料", destination: URL(string: "https://data.gov.hk/en-data/dataset/hk-td-tis_15-road-network-v2")!)
            } header: {
                Text("交通相機")
            } footer: {
                Text("固定相機外殼位置不代表正在執法；不包含流動測速，部分隧道及管制區不在資料範圍。平行道路、高架橋及 GPS 誤差可能造成漏報或誤報。請始終依現場路牌及交通燈駕駛。")
            }
            Section {
                Link("咪錶位置及佔用狀態資料", destination: URL(string: "https://data.gov.hk/en-data/dataset/hk-td-msd_1-metered-parking-spaces-data")!)
            } header: {
                Text("咪錶資料")
            } footer: {
                Text("咪錶位置及佔用狀態可能有更新延遲或缺漏；請以現場標示、咪錶及實際泊位狀況為準。")
            }
            Section {
                Link("Sunrise-Sunset.org", destination: URL(string: "https://sunrise-sunset.org/")!)
                Link("日出日落 API 說明及使用要求", destination: URL(string: "https://sunrise-sunset.org/api")!)
            } header: {
                Text("日出日落")
            } footer: {
                Text("日出、日落及晨昏時間由 Sunrise-Sunset.org 提供，用於時情動畫。未能取得資料時會沿用快取或預設時間。")
            }
            Section {
                Link("政府開放資料使用條款", destination: URL(string: "https://data.gov.hk/en/terms-and-conditions")!)
            } header: {
                Text("資料使用條款")
            } footer: {
                Text("Gorilla Leading 並非政府官方應用程式。引用政府資料不代表政府認可本應用程式；資料按原樣提供，可能並非最新或完整。")
            }
        }
        .navigationTitle("資料來源與使用條款")
        .navigationBarTitleDisplayMode(.inline)
        .tint(colorScheme == .dark ? .white : .accentColor)
    }
}
