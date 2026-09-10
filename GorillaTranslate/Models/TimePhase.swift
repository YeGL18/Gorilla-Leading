import SwiftUI
import CoreLocation

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

// MARK: - Blended Colors

struct BlendedPhaseColors {
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
            sunOpacity: p < 0.5 ? (from.sunIndex >= 0 ? 1 : 0) : (to.sunIndex >= 0 ? 1 : 0),
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

struct SunPosition {
    let x: CGFloat  // 0-1, 0=左, 1=右
    let y: CGFloat  // 0-1, 0=上, 1=下
    let visible: Bool
    let scale: CGFloat
    let blur: CGFloat
    
    static func calculate(hour: Double) -> SunPosition {
        // 太陽軌跡：平滑拋物線，左邊升起 → 頂部中央 → 右邊落下
        // 可見時間：5:00 ~ 19:00（14 小時）

        guard hour >= 5, hour <= 19 else {
            return SunPosition(x: hour < 12 ? 0.1 : 0.9, y: 1.2, visible: false, scale: 0.5, blur: 120)
        }

        // t: 0 = 日出 (5:00), 1 = 日落 (19:00)
        let t = (hour - 5.0) / 14.0

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
    
    private var displayLink: CADisplayLink?
    private var lastTimestamp: TimeInterval = 0
    private var previewHour: Double? = nil  // 预览模式
    private let weatherService = WeatherService.shared
    
    // 动态阶段起始时间（基于真实日出日落）
    private var dynamicStartHours: [Double] = []
    
    init() {
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
    }
    
    @objc private func handlePreviewChanged(_ notification: Notification) {
        if let hour = notification.userInfo?["hour"] as? Double {
            setPreviewHour(hour)
        }
    }
    
    func start() {
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
        update()
    }

    /// 啟動時先顯示上一個階段，再用非線性動畫轉變到當前階段（顏色 + 太陽位置）
    func startWithEntranceAnimation() {
        // 先正常計算當前目標（唔啟動 displayLink）
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
        let prevSun = SunPosition.calculate(hour: prevSunHour)

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
                // 入場動畫完成後啟動 displayLink 保持實時更新
                self.displayLink?.invalidate()
                self.displayLink = CADisplayLink(target: self, selector: #selector(self.tick))
                self.displayLink?.add(to: .main, forMode: .common)
            }
        }
        RunLoop.main.add(entranceTimer!, forMode: .common)
    }

    private var entranceTimer: Timer?
    private var isEntranceAnimating = false
    
    func fetchSunTimes(for location: CLLocationCoordinate2D) {
        weatherService.fetchSunTimes(for: location) { [weak self] _ in
            self?.updateDynamicTimes()
        }
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
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
    
    @objc private func tick(_ link: CADisplayLink) {
        update()
    }
    
    // 根据日出日落时间计算动态阶段起始时间
    private func updateDynamicTimes() {
        let sunTimes = weatherService.getCurrentSunTimes()
        
        // 关键：深夜拉長，日出漸變推遲，夜晚感受更長
        let deepNightEnd = sunTimes.civilDawnHour + 0.75   // 黎明前仍保留深黑夜色多 45 分鐘
        let preDawn = deepNightEnd                          // 黎明前（微亮）
        let sunrise = sunTimes.sunriseHour - 0.15          // 日出略為提前進入
        let sunriseEnd = sunrise + 2.0                      // 日出后（日出后2小時）
        let afternoon = 16.5                                   // 下午 4:30 才切換（拉長日出後藍天）
        let sunsetStart = sunTimes.sunsetHour - 0.5
        let sunset = sunTimes.sunsetHour
        let nightStart = 20.0                                   // 深夜 8 點才開始（拉長傍晚）
        
        dynamicStartHours = [
            nightStart,     // 0 深夜（日落後0.5h開始，拉長深夜）
            preDawn,        // 1 黎明前（dawn+45min，之前係 dawn）
            sunrise,        // 2 日出
            sunriseEnd,     // 3 日出后（藍天）
            afternoon,      // 4 接近下午（15:00）
            sunsetStart,    // 5 黃昏後
            sunset          // 6 日落時分
        ]
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
        
        // 如果动态时间还没准备好，使用默认值
        if dynamicStartHours.isEmpty {
            // 默认值：日落18:00，深夜從18:30開始，preDawn 4:45，日出 4:51
            dynamicStartHours = [20.0, 4.75, 4.85, 6.85, 16.5, 17, 18]
        }
        
        // 找到当前和下一个阶段
        let phases = TimePhase.allCases
        var currentPhaseIndex = 0
        var nextPhaseIndex = 0
        var progress: Double = 0
        
        for i in 0..<phases.count {
            let nextIndex = (i + 1) % phases.count
            let startHour = dynamicStartHours[i]
            let endHour = dynamicStartHours[nextIndex]
            
            if endHour > startHour {
                // 正常范围
                if hour >= startHour && hour < endHour {
                    currentPhaseIndex = i
                    nextPhaseIndex = nextIndex
                    let rawProgress = (hour - startHour) / (endHour - startHour)
                    // 不同階段用唔同 hold/transition split：
                    // - 深夜 → 黎明前（i==0）+ 黎明前 → 日出（i==1）：90/10，壓縮漸變，夜晚更長
                    // - 日出 → 早上（i==2）：65/35，漸變更平滑
                    // - 其他（下午/日落等）：保留 80/20
                    let (holdFraction, _): (Double, Double) = {
                        switch i {
                        case 0: return (0.85, 0.15)  // 深夜 → 黎明前
                        case 1: return (0.80, 0.20)  // 黎明前 → 日出
                        case 2: return (0.60, 0.40)  // 日出 → 日出後
                        case 3: return (0.70, 0.30)  // 日出後 → 下午
                        case 4: return (0.65, 0.35)  // 下午 → 傍晚
                        case 5: return (0.60, 0.40)  // 傍晚 → 日落
                        case 6: return (0.65, 0.35)  // 日落 → 深夜
                        default: return (0.80, 0.20)
                        }
                    }()
                    if rawProgress < holdFraction {
                        progress = 0
                    } else {
                        progress = (rawProgress - holdFraction) / (1 - holdFraction)
                    }
                    break
                }
            } else {
                // 跨越午夜
                if hour >= startHour || hour < endHour {
                    currentPhaseIndex = i
                    nextPhaseIndex = nextIndex
                    var rawProgress: Double
                    if hour >= startHour {
                        rawProgress = (hour - startHour) / (24 - startHour + endHour)
                    } else {
                        rawProgress = (24 - startHour + hour) / (24 - startHour + endHour)
                    }
                    // 深夜跨午夜段（i==6, sunset→deepNight）亦採用 92/8 壓縮漸變
                    let holdFraction: Double = (i == 6) ? 0.92 : 0.80
                    if rawProgress < holdFraction {
                        progress = 0
                    } else {
                        progress = (rawProgress - holdFraction) / (1 - holdFraction)
                    }
                    break
                }
            }
        }
        
        let fromPhase = phases[currentPhaseIndex]
        let toPhase = phases[nextPhaseIndex]
        
        // 平滑混合颜色
        blendedColors = BlendedPhaseColors.blend(
            from: fromPhase.colors,
            to: toPhase.colors,
            progress: progress
        )
        
        // 更新太阳位置
        sunPosition = SunPosition.calculate(hour: hour)
        
        currentPhase = fromPhase
        phaseTransitionProgress = progress
    }
}
