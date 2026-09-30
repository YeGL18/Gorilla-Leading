import SwiftUI
import QuartzCore

/// 逐格滾動數字插值器：用 CADisplayLink（螢幕最高刷新率，ProMotion 即 120Hz）
/// 將顯示值平滑推向目標值，時速／距離數字就會逐個整數咁連續滾動
/// （1,2,3,4,5…一個都唔跳），同「卡爾曼濾波測試」頁嘅滾動效果一致。
///
/// 設計要點：獨立物件＋葉子 View 觀察，滾動時只有數字 Text 重繪，
/// 唔會令成個 SpeedView / ContentView body 每幀重算。
@MainActor
final class NumberRoller: ObservableObject {
    /// 當前顯示值（每幀更新）
    @Published private(set) var display: Double = 0

    /// 動態目標源（例如時速用卡爾曼速度外推，每次 tick 重新取值）；
    /// 回傳 nil = 保持當前顯示值（例如 GPS 失聯時凍結）。
    var targetProvider: (() -> Double?)? = nil
    /// 外推模式（距離倒數用）：兩次目標更新之間按當前車速持續遞減，
    /// 令數字一路連續滾動而唔會喺更新之間停下來。車速為 0 就保持唔變。
    /// 設咗呢個優先於 `targetProvider`。
    var extrapolation: (base: Double, at: Date, speedKmh: () -> Double)? = nil

    /// 時間常數（秒）：約 0.14s —— 同卡爾曼測試 20Hz×0.3 lerp 嘅收斂手感一致，
    /// 任何刷新率下數字滾動速度都一樣。
    private let tau: TimeInterval = 0.14
    private var link: CADisplayLink?
    private var lastTick: TimeInterval = 0
    private var interpolated: Double = 0

    func start() {
        guard link == nil else { return }
        lastTick = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // 唔限制幀率：用螢幕最高刷新率（ProMotion = 120Hz）
        let maxHz = Float(max(UIScreen.main.maximumFramesPerSecond, 60))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30, maximum: maxHz, preferred: maxHz
        )
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// 強制重建 display link（回前景用）：app 懸停之後舊 link 可能已經
    /// 失效但仲存緊，start() 嘅 guard 會誤判「已經喺度」唔重起。
    func restart() {
        stop()
        start()
    }

    /// 直接同步顯示值（例如初次顯示時唔想由零滾起）
    func setDisplay(_ value: Double) {
        interpolated = value
        display = value
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick > 0 ? min(max(now - lastTick, 0.001), 0.1) : 1.0 / 120.0
        lastTick = now

        let resolved: Double?
        if let ext = extrapolation {
            // 剩餘距離按車速遞減（沿路線行緊，剩餘距離就係以車速減少）
            let elapsed = max(0, Date().timeIntervalSince(ext.at))
            resolved = max(0, ext.base - max(0, ext.speedKmh()) / 3.6 * elapsed)
        } else if let provider = targetProvider {
            resolved = provider()
        } else {
            return
        }
        guard let t = resolved else { return }

        // 幀率無關嘅指數平滑：60Hz 同 120Hz 手感一致
        let alpha = 1 - exp(-dt / tau)
        interpolated += (t - interpolated) * alpha
        // Consumers only render Int(display). Keep interpolation at display rate,
        // but avoid invalidating SwiftUI when the visible digit has not changed.
        if Int(interpolated) != Int(display) {
            display = interpolated
        }
    }

    deinit {
        link?.invalidate()
    }
}

/// 主頁膠囊嘅「離目的地距離」：剩餘距離係米數時逐格連續滾動
/// （兩次路線更新之間按車速持續倒數，同卡爾曼開關綁定），公里時直接顯示文字。
/// 獨立葉子 View，滾動時唔會重算成個 ContentView。
struct RollingDistanceText: View {
    /// 最近一次路線計算回報嘅剩餘距離（米）
    let targetMeters: Double?
    /// 回報時間（外推基準）
    let updatedAt: Date?
    /// 當前車速（km/h）來源
    let speedKmh: () -> Double
    /// 公里顯示文字（>= 1000m 時用）
    let displayText: String?
    let rolling: Bool

    @StateObject private var roller = NumberRoller()

    /// 米數時用滾動值顯示；公里（>= 1000m）時直接用文字
    private var currentText: String {
        guard rolling, let m = targetMeters, m < 1000 else {
            return displayText ?? "--"
        }
        return "\(Int(roller.display)) m"
    }

    var body: some View {
        Text(currentText)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: rolling ? 0.05 : 0.3), value: currentText)
            .monospacedDigit()
            .onAppear { sync() }
            .onChange(of: targetMeters) { _, _ in sync() }
            .onChange(of: updatedAt) { _, _ in sync() }
            .onChange(of: rolling) { _, _ in sync() }
            .onDisappear { roller.stop() }
    }

    private func sync() {
        let metersMode = rolling && targetMeters != nil && (targetMeters ?? 0) < 1000
        if metersMode, let m = targetMeters {
            // 首次直接同步顯示值（唔會由零滾起），之後每次更新就連續滾動過去
            if roller.extrapolation == nil {
                roller.setDisplay(m)
            }
            roller.extrapolation = (base: m, at: updatedAt ?? Date(), speedKmh: speedKmh)
            roller.start()
        } else {
            roller.extrapolation = nil
            roller.stop()
        }
    }
}
