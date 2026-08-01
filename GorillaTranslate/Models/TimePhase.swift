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
        case .afternoon: return 12
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
        // 太阳轨迹：左下 → 左上 → 右上 → 右下
        // 5:00-7:00: 左下升起
        // 7:00-12:00: 左上到右上
        // 12:00-17:00: 右上到右下
        // 17:00-19:00: 右下落下
        
        let visible: Bool
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat
        let blur: CGFloat
        
        if hour < 5 {
            // 深夜，太阳不可见
            visible = false
            x = 0.2
            y = 1.2
            scale = 0.5
            blur = 120
        } else if hour < 7 {
            // 日出：从左下升起
            visible = true
            let t = (hour - 5) / 2.0  // 0-1
            x = 0.15
            y = 1.0 - t * 0.6  // 1.0 → 0.4
            scale = 0.6 + t * 0.4
            blur = 80 - t * 20
        } else if hour < 12 {
            // 上午：左上到右上
            visible = true
            let t = (hour - 7) / 5.0  // 0-1
            x = 0.15 + t * 0.7  // 0.15 → 0.85
            y = 0.4 - t * 0.25  // 0.4 → 0.15
            scale = 1.0
            blur = 60
        } else if hour < 17 {
            // 下午：右上
            visible = true
            let t = (hour - 12) / 5.0  // 0-1
            x = 0.85 - t * 0.1  // 0.85 → 0.75
            y = 0.15 + t * 0.15  // 0.15 → 0.3
            scale = 1.0 - t * 0.1
            blur = 60 + t * 10
        } else if hour < 19 {
            // 日落：右下
            visible = true
            let t = (hour - 17) / 2.0  // 0-1
            x = 0.75 + t * 0.1  // 0.75 → 0.85
            y = 0.3 + t * 0.7  // 0.3 → 1.0
            scale = 0.9 - t * 0.4
            blur = 70 + t * 30
        } else {
            // 黄昏后，太阳不可见
            visible = false
            x = 0.85
            y = 1.2
            scale = 0.5
            blur = 120
        }
        
        return SunPosition(x: x, y: y, visible: visible, scale: scale, blur: blur)
    }
}

// MARK: - Time Phase Manager

class TimePhaseManager: ObservableObject {
    @Published var currentPhase: TimePhase = .deepNight
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
    
    @objc private func tick(_ link: CADisplayLink) {
        update()
    }
    
    // 根据日出日落时间计算动态阶段起始时间
    private func updateDynamicTimes() {
        let sunTimes = weatherService.getCurrentSunTimes()
        
        let dawn = sunTimes.civilDawnHour       // 黎明前
        let sunrise = sunTimes.sunriseHour       // 日出
        let sunriseEnd = sunrise + 2.0           // 日出后（日出后2小时）
        let noon = 12.0                          // 中午（固定）
        let sunsetStart = sunTimes.sunsetHour - 0.5  // 日落前30分钟
        let sunset = sunTimes.sunsetHour         // 日落时分
        let nightStart = min(sunset + 1.0, 21.0) // 日落后1小时进入深夜，最晚21:00
        
        dynamicStartHours = [
            nightStart,     // 深夜（日落后1.5小时开始）
            dawn,           // 黎明前
            sunrise,        // 日出
            sunriseEnd,     // 日出后（蓝天）
            noon,           // 接近下午
            sunsetStart,    // 黄昏后
            sunset          // 日落时分
        ]
    }
    
    private func update() {
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
            // 默认值：日落18:00，深夜从19:30开始
            dynamicStartHours = [19.5, 4, 5, 7, 12, 17, 18]
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
                    // 前80%保持纯色，后20%快速过渡
                    if rawProgress < 0.8 {
                        progress = 0
                    } else {
                        progress = (rawProgress - 0.8) / 0.2
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
                    // 前80%保持纯色，后20%快速过渡
                    if rawProgress < 0.8 {
                        progress = 0
                    } else {
                        progress = (rawProgress - 0.8) / 0.2
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
    }
}
