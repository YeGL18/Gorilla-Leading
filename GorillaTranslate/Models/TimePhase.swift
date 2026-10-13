import SwiftUI
import CoreLocation
import Combine

enum GorillaColorGroup: Int, CaseIterable {
    case normal = 0, darkKnight = 1, m3Concept = 2

    static func resolve(raw: Int, legacyDarkKnight: Bool) -> Self {
        Self(rawValue: raw) ?? (legacyDarkKnight ? .darkKnight : .normal)
    }

    static func load(_ defaults: UserDefaults = .standard) -> Self {
        resolve(raw: defaults.object(forKey: "colorGroupMode") as? Int ?? -1,
                legacyDarkKnight: defaults.bool(forKey: "darkKnightMode"))
    }

    var titleKey: String {
        switch self {
        case .normal: return "Normal Mode"
        case .darkKnight: return "黑武士模式"
        case .m3Concept: return "M3 Concept"
        }
    }

    var showsOrbControls: Bool { self == .normal }
    var usesSpecialMap: Bool { self == .darkKnight }

    func dotColorHex(speed: Double, preset: Int) -> String {
        let speed = speed.isFinite ? max(0, speed) : 0
        if self == .m3Concept { return "#" + M3ConceptPalette.orange }
        if self == .darkKnight {
            let amount = min(1, max(0, (speed - 100) / 100))
            return String(format: "#%02X%02X%02X", 255,
                          Int(196 * (1 - amount) + 69 * amount), Int(109 * (1 - amount)))
        }
        switch preset {
        case 1:
            let amount = min(1, max(0, (speed - 30) / 90))
            let green = amount < 0.5 ? 140 - 66 * amount : 107 - 76 * (amount - 0.5)
            return String(format: "#%02X%02X%02X", 255, Int(green), 0)
        case 2: return "#9BF783"
        case 3: return "#99E695"
        case 4: return "#97D5AB"
        default: return "#ffd700"
        }
    }
}

enum M3ConceptPalette {
    // Decode the PNG's Display P3 pixels before converting to sRGB.
    static let orange = "EF363B"
    static let yellow = "DDD11B"
    static let paper = "E6EFEA"
    static let gray = "5C575D"
    static let black = "0D0B0E"
    static let all = [orange, yellow, paper, gray, black]
    static let homeIndigo = "00172D"
    static let homeOrbMixing = true
    static let homeOrbs: [(hex: String, opacity: Double)] = [(orange, 0.75), (yellow, 0.7), (homeIndigo, 0.85)]
}

// MARK: - Time Phase Model

struct TimePhaseColors {
    let background1: Color  // 顶部
    let background2: Color  // 中间
    let background3: Color  // 底部
    let sunColor: Color     // 太阳/阳光颜色
    let sunIndex: Int       // 哪个是太阳颜色 (0=顶部, 1=中间, 2=底部)
}

enum TimePhase: Int, CaseIterable {
    case deepNight = 0      // 深夜
    case preDawn = 1        // 黎明前
    case sunrise = 2        // 日出时刻
    case morning = 3        // 日出后（蓝天）
    case afternoon = 4      // 接近下午
    case postSunset = 5     // 黄昏后
    case sunset = 6         // 日落时分
    
    var colors: TimePhaseColors {
        switch self {
        case .deepNight:
            return TimePhaseColors(
                background1: Color(hex: "1A1E2E"),
                background2: Color(hex: "1B2234"),
                background3: Color(hex: "252D40"),
                sunColor: Color(hex: "1A1E2E"),  // 无太阳
                sunIndex: -1
            )
        case .preDawn:
            return TimePhaseColors(
                background1: Color(hex: "474A4F"),
                background2: Color(hex: "5B595B"),
                background3: Color(hex: "927F6B"),
                sunColor: Color(hex: "927F6B"),  // 微弱光芒
                sunIndex: 2
            )
        case .sunrise:
            return TimePhaseColors(
                background1: Color(hex: "706D68"),
                background2: Color(hex: "827869"),
                background3: Color(hex: "DCAC70"),  // 阳光在底部
                sunColor: Color(hex: "DCAC70"),
                sunIndex: 2
            )
        case .morning:
            return TimePhaseColors(
                background1: Color(hex: "83A3C3"),
                background2: Color(hex: "D7C4AF"),
                background3: Color(hex: "EEDFAD"),  // 太阳
                sunColor: Color(hex: "EEDFAD"),
                sunIndex: 2
            )
        case .afternoon:
            return TimePhaseColors(
                background1: Color(hex: "87A3C7"),
                background2: Color(hex: "E6A77B"),  // 太阳
                background3: Color(hex: "E7D3CA"),
                sunColor: Color(hex: "E6A77B"),
                sunIndex: 1
            )
        case .postSunset:
            return TimePhaseColors(
                background1: Color(hex: "9D809A"),
                background2: Color(hex: "F79D6C"),  // 太阳
                background3: Color(hex: "F0D6CA"),
                sunColor: Color(hex: "F79D6C"),
                sunIndex: 1
            )
        case .sunset:
            return TimePhaseColors(
                background1: Color(hex: "453948"),
                background2: Color(hex: "5C4552"),
                background3: Color(hex: "926361"),
                sunColor: Color(hex: "926361"),  // 余晖
                sunIndex: 2
            )
        }
    }
    
    // 每个阶段的起始时间（小时）
    var startHour: Double {
        switch self {
        case .deepNight: return 0
        case .preDawn: return 4
        case .sunrise: return 5
        case .morning: return 7
        case .afternoon: return 16
        case .postSunset: return 17
        case .sunset: return 18
        }
    }
    
    // 太阳是否可见
    var sunVisible: Bool {
        switch self {
        case .deepNight: return false
        case .preDawn: return true
        case .sunrise: return true
        case .morning: return true
        case .afternoon: return true
        case .postSunset: return true
        case .sunset: return true
        }
    }
}

struct TimePhaseSchedule: Equatable {
    struct Segment: Equatable {
        let phase: TimePhase
        let start: Double
        let end: Double
    }

    let startHours: [Double]
    let sunriseHour: Double
    let sunsetHour: Double

    init(civilDawn: Double, sunrise: Double, sunset: Double) {
        let valid = civilDawn.isFinite && sunrise.isFinite && sunset.isFinite &&
            civilDawn >= 0 && civilDawn < sunrise && sunrise >= 0.25 &&
            sunset <= 24 && sunset - sunrise >= 4
        let rise = valid ? sunrise : 6
        let set = valid ? sunset : 18
        let dawn = valid ? civilDawn : 5.5
        sunriseHour = rise
        sunsetHour = set
        let sunriseStart = rise - 0.15
        let morning = sunriseStart + min(2, (set - sunriseStart) * 0.25)
        let evening = set - 1.5
        let afternoon = max(morning + 0.25, min(16.5, evening - 1))
        // Only deep night crosses midnight. Dawn must precede the sunrise palette.
        startHours = [set, min(dawn, sunriseStart - 0.1), sunriseStart,
                      morning, afternoon, evening, set - 0.5]
    }

    var segments: [Segment] {
        let phases = TimePhase.allCases
        var result = [Segment(phase: .deepNight, start: 0, end: startHours[1])]
        for index in 1..<phases.count {
            result.append(Segment(phase: phases[index], start: startHours[index],
                                  end: index == phases.count - 1 ? sunsetHour : startHours[index + 1]))
        }
        result.append(Segment(phase: .deepNight, start: sunsetHour, end: 24))
        return result
    }

    func state(at hour: Double) -> (phase: TimePhase, next: TimePhase, progress: Double) {
        let normalized = Self.hourInDay(hour)
        let phases = TimePhase.allCases
        let holds = [0.85, 0.80, 0.60, 0.70, 0.65, 0.60, 0.0]
        for index in phases.indices {
            let nextIndex = (index + 1) % phases.count
            let start = startHours[index]
            let end = startHours[nextIndex] + (index == 0 ? 24 : 0)
            let time = index == 0 && normalized < start ? normalized + 24 : normalized
            guard time >= start, time < end else { continue }
            let raw = (time - start) / (end - start)
            let progress = min(1, max(0, (raw - holds[index]) / (1 - holds[index])))
            return (phases[index], phases[nextIndex], progress)
        }
        return (.deepNight, .preDawn, 0)
    }

    static func hourInDay(_ hour: Double) -> Double {
        guard hour.isFinite else { return 0 }
        // Preserve exact boundaries already in today's range (no rounding via +24).
        let remainder = hour.truncatingRemainder(dividingBy: 24)
        return remainder < 0 ? remainder + 24 : remainder
    }
}

// MARK: - Blended Colors

struct BlendedPhaseColors: Equatable {
    var background1: Color
    var background2: Color
    var background3: Color
    var sunColor: Color
    var sunOpacity: Double
    var sunIndex: Int
    
    static func blend(from: TimePhaseColors, to: TimePhaseColors, progress: Double) -> BlendedPhaseColors {
        let p = min(max(progress, 0), 1)
        return BlendedPhaseColors(
            background1: Color.blend(from: from.background1, to: to.background1, amount: p),
            background2: Color.blend(from: from.background2, to: to.background2, amount: p),
            background3: Color.blend(from: from.background3, to: to.background3, amount: p),
            sunColor: Color.blend(from: from.sunColor, to: to.sunColor, amount: p),
            sunOpacity: (from.sunIndex >= 0 ? 1 - p : 0) + (to.sunIndex >= 0 ? p : 0),
            sunIndex: p < 0.5 ? from.sunIndex : to.sunIndex
        )
    }
}

// MARK: - Color Extension

extension Color {
    static func blend(from: Color, to: Color, amount: Double) -> Color {
        let fromUIColor = UIColor(from)
        let toUIColor = UIColor(to)
        
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0
        
        fromUIColor.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        toUIColor.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)
        
        let r = fromR + (toR - fromR) * amount
        let g = fromG + (toG - fromG) * amount
        let b = fromB + (toB - fromB) * amount
        let a = fromA + (toA - fromA) * amount
        
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Sun Position

struct SunPosition: Equatable {
    let x: CGFloat  // 0-1, 0=左, 1=右
    let y: CGFloat  // 0-1, 0=上, 1=下
    let visible: Bool
    let scale: CGFloat
    let blur: CGFloat
    
    static func calculate(hour: Double, sunrise: Double = 5, sunset: Double = 19) -> SunPosition {
        // Keep the same parabolic path, stretched between actual sunrise and sunset.

        guard sunset > sunrise, hour >= sunrise, hour <= sunset else {
            return SunPosition(x: hour < 12 ? 0.1 : 0.9, y: 1.2, visible: false, scale: 0.5, blur: 120)
        }

        // t: 0 = sunrise, 1 = sunset.
        let t = (hour - sunrise) / (sunset - sunrise)

        // x: 線性左→右
        let x: CGFloat = 0.1 + 0.8 * t

        // y: 拋物線，頂部在 t=0.5（正午 12:00），y=0.15
        // y = 2.8 * (t - 0.5)² + 0.15
        // t=0 → y=0.85, t=0.5 → y=0.15, t=1 → y=0.85
        let y: CGFloat = 2.8 * (t - 0.5) * (t - 0.5) + 0.15

        // scale: 正午最大，日出日落最小
        let noonFactor = 1.0 - 4.0 * (t - 0.5) * (t - 0.5)  // 0 at edges, 1 at noon
        let scale: CGFloat = 0.6 + 0.4 * noonFactor

        // blur: 正午最清晰，日出日落最模糊
        let blur: CGFloat = 60 + 20 * (1.0 - noonFactor)

        return SunPosition(x: x, y: y, visible: true, scale: scale, blur: blur)
    }
}

// MARK: - Time Phase Manager

class TimePhaseManager: ObservableObject {
    @Published var currentPhase: TimePhase = .deepNight
    @Published var phaseTransitionProgress: Double = 0
    @Published var blendedColors: BlendedPhaseColors
    @Published var sunPosition: SunPosition = SunPosition(x: 0.5, y: 0.5, visible: false, scale: 0.5, blur: 80)
    
    private var updateTimer: Timer?
    private var previewHour: Double? = nil  // 预览模式
    private let weatherService: WeatherService
    private var sunTimesSubscription: AnyCancellable?
    @Published private(set) var hasActualSunTimes = false
    
    // 动态阶段起始时间（基于真实日出日落）
    @Published private(set) var schedule: TimePhaseSchedule
    private var dynamicStartHours: [Double] { schedule.startHours }
    
    init(weatherService: WeatherService = .shared) {
        self.weatherService = weatherService
        let times = weatherService.getCurrentSunTimes()
        schedule = TimePhaseSchedule(civilDawn: times.civilDawnHour,
                                     sunrise: times.sunriseHour, sunset: times.sunsetHour)
        let phase = TimePhase.deepNight
        self.blendedColors = BlendedPhaseColors(
            background1: phase.colors.background1,
            background2: phase.colors.background2,
            background3: phase.colors.background3,
            sunColor: phase.colors.sunColor,
            sunOpacity: 0,
            sunIndex: phase.colors.sunIndex
        )
        
        // 监听预览时间变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviewChanged(_:)),
            name: .timePhasePreviewChanged,
            object: nil
        )
        
        // 初始化动态时间
        updateDynamicTimes()
        hasActualSunTimes = weatherService.sunTimes != nil
        // Every preview shares the asynchronous result, not just the caller that fetched it.
        sunTimesSubscription = weatherService.$sunTimes.dropFirst().sink { [weak self] times in
            guard let self, let times else { return }
            self.updateDynamicTimes(times)
            if !self.hasActualSunTimes { self.hasActualSunTimes = true }
            self.update()
        }
    }
    
    @objc private func handlePreviewChanged(_ notification: Notification) {
        if let hour = notification.userInfo?["hour"] as? Double {
            setPreviewHour(hour)
        }
    }
    
    func start() {
        guard updateTimer == nil, !isEntranceAnimating else { return }
        updateDynamicTimes()
        update()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    /// 啟動時先顯示上一個階段，再用非線性動畫轉變到當前階段（顏色 + 太陽位置）
    func startWithEntranceAnimation() {
        stop()
        // 先正常計算當前目標（唔啟動定期更新）
        let savedPreview = previewHour
        update()
        let targetColors = blendedColors
        let targetPhase = currentPhase
        let targetProgress = phaseTransitionProgress
        let targetSun = sunPosition
        previewHour = savedPreview

        // 計算上一個階段嘅顏色同太陽位置
        let phases = TimePhase.allCases
        let prevIndex = (targetPhase.rawValue - 1 + phases.count) % phases.count
        let prevPhase = phases[prevIndex]
        // 上一個階段嘅太陽位置：用上一個階段嘅起始小時計算
        let prevSunHour = dynamicStartHours.isEmpty ? prevPhase.startHour : dynamicStartHours[prevIndex]
        let prevSun = SunPosition.calculate(hour: prevSunHour, sunrise: schedule.sunriseHour, sunset: schedule.sunsetHour)

        // 瞬間切到上一個階段
        isEntranceAnimating = true
        blendedColors = BlendedPhaseColors(
            background1: prevPhase.colors.background1,
            background2: prevPhase.colors.background2,
            background3: prevPhase.colors.background3,
            sunColor: prevPhase.colors.sunColor,
            sunOpacity: prevPhase.colors.sunIndex >= 0 ? 1 : 0,
            sunIndex: prevPhase.colors.sunIndex
        )
        sunPosition = prevSun

        // 用非線性動畫（easeOut cubic）過渡到當前階段
        // 時長 5 秒：前 4 秒被 blur 蓋住，最後 1 秒 blur 淡入時見到漸變尾段
        let duration: TimeInterval = 5.0
        let startTime = Date()

        entranceTimer?.invalidate()
        entranceTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startTime)
            let rawT = min(elapsed / duration, 1.0)
            // easeOut cubic: 1 - (1 - t)^3
            let t = 1.0 - pow(1.0 - rawT, 3.0)

            // 顏色漸變
            let fromColors = prevPhase.colors
            let toColors = targetPhase.colors
            self.blendedColors = BlendedPhaseColors.blend(from: fromColors, to: toColors, progress: t)

            // 太陽位置漸變（x, y, scale, blur）
            self.sunPosition = SunPosition(
                x: prevSun.x + (targetSun.x - prevSun.x) * t,
                y: prevSun.y + (targetSun.y - prevSun.y) * t,
                visible: prevSun.visible || targetSun.visible,
                scale: prevSun.scale + (targetSun.scale - prevSun.scale) * t,
                blur: prevSun.blur + (targetSun.blur - prevSun.blur) * t
            )

            if rawT >= 1.0 {
                timer.invalidate()
                self.entranceTimer = nil
                self.isEntranceAnimating = false
                self.blendedColors = targetColors
                self.sunPosition = targetSun
                self.currentPhase = targetPhase
                self.phaseTransitionProgress = targetProgress
                // 入場動畫完成後恢復每秒更新日夜資料
                self.start()
            }
        }
        RunLoop.main.add(entranceTimer!, forMode: .common)
    }

    private var entranceTimer: Timer?
    private var isEntranceAnimating = false
    
    func fetchSunTimes(for location: CLLocationCoordinate2D) {
        weatherService.fetchSunTimes(for: location) { [weak self] _ in
            self?.updateDynamicTimes()
            self?.update()
        }
    }
    
    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
        entranceTimer?.invalidate()
        entranceTimer = nil
        isEntranceAnimating = false
    }
    
    func setPreviewHour(_ hour: Double) {
        previewHour = hour
        update()
    }
    
    func clearPreview() {
        previewHour = nil
        update()
    }

    /// 當前小時（預覽模式用預覽值，否則用真實時間）
    var currentHour: Double {
        if let preview = previewHour {
            return preview
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0
    }
    
    // 根据日出日落时间计算动态阶段起始时间
    private func updateDynamicTimes(_ times: SunTimes? = nil) {
        // @Published emits before storage changes; use its emitted value in the subscription.
        let sunTimes = times ?? weatherService.getCurrentSunTimes()
        let updated = TimePhaseSchedule(civilDawn: sunTimes.civilDawnHour,
                                        sunrise: sunTimes.sunriseHour, sunset: sunTimes.sunsetHour)
        if schedule != updated { schedule = updated }
    }
    
    private func update() {
        // 入場動畫期間唔更新，避免覆蓋漸變
        guard !isEntranceAnimating else { return }
        let hour: Double
        if let preview = previewHour {
            hour = preview
        } else {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute, .second], from: Date())
            hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60.0 + Double(components.second ?? 0) / 3600.0
        }
        
        let state = schedule.state(at: hour)
        let fromPhase = state.phase
        let toPhase = state.next
        let progress = state.progress
        
        // 平滑混合颜色
        let colors = BlendedPhaseColors.blend(
            from: fromPhase.colors,
            to: toPhase.colors,
            progress: progress
        )
        
        // 更新太阳位置
        let normalizedHour = TimePhaseSchedule.hourInDay(hour)
        let sun = SunPosition.calculate(hour: normalizedHour, sunrise: schedule.sunriseHour, sunset: schedule.sunsetHour)
        if blendedColors != colors { blendedColors = colors }
        if sunPosition != sun { sunPosition = sun }
        if currentPhase != fromPhase { currentPhase = fromPhase }
        if phaseTransitionProgress != progress { phaseTransitionProgress = progress }
    }
}
