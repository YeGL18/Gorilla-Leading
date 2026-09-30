import Foundation
import CoreLocation
import Combine

// MARK: - TimeSlot (4個 time bucket)
enum TripTimeSlot: Int, Codable, Hashable, CaseIterable, CustomStringConvertible {
    case morning     // 06-11
    case noon        // 11-14
    case afternoon   // 14-18
    case evening     // 18-22
    case lateNight   // 22-06

    var description: String {
        switch self {
        case .morning: return "朝早"
        case .noon: return "午間"
        case .afternoon: return "下午"
        case .evening: return "黃昏"
        case .lateNight: return "深夜"
        }
    }

    init(date: Date) {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        switch h {
        case 6..<11: self = .morning
        case 11..<14: self = .noon
        case 14..<18: self = .afternoon
        case 18..<22: self = .evening
        default: self = .lateNight
        }
    }
}

// MARK: - PlaceKind (named lot vs unnamed cluster)
enum PlaceKind: Int, Codable, Hashable {
    case namedLot   // 用戶改過名嘅停車場（最可靠）
    case addressCluster // 冇命名但 address + latlng 200m cluster
}

// MARK: - PlaceInfo (canonical 地點單位：named lot 優先)
struct PlaceInfo: Codable, Hashable, Identifiable, CustomStringConvertible {
    let key: String       // namedLot: "lot:\(lotID)"；addressCluster: "addr:\(lat4):\(lng4):\(streetPrefix)"
    var kind: PlaceKind
    var displayName: String    // named lot → lot name；addressCluster → address first line
    let latitude: Double
    let longitude: Double
    var lotID: UUID?      // named lot 先有
    var updatedAt: Date

    var id: String { key }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var description: String {
        let prefix = kind == .namedLot ? "[Lot] " : "[Addr] "
        return "\(prefix)\(displayName)"
    }
}

// MARK: - TripPatternKey (from → weekday → timeSlot)
struct TripPatternKey: Codable, Hashable {
    let fromKey: String?       // 第一次出發冇 from place，nil
    let weekday: Int            // 1=Sun ... 7=Sat (Calendar.component(.weekday))
    let timeSlot: TripTimeSlot
    let twoGramFromFromKey: String? // 2-gram: 上上一個 place key，處理 multi-stop 路線
}

// MARK: - TripNextCandidate (counter + weight)
struct TripNextCandidate: Codable, Hashable {
    var toPlaceKey: String
    var hitCount: Int                // 實際真實次數
    var correctFeedbackCount: Int    // user confirm 「係」次數 (weight 1.2)
    var denyCount: Int               // user 「唔係」次數 (penalty)

    var effectiveScore: Double {
        return max(0.0,
                   Double(hitCount) * 1.0 +
                   Double(correctFeedbackCount) * 1.2 -
                   Double(denyCount) * 1.8)
    }
}

// MARK: - TripPatternRecord (儲存 pattern，俾 Settings 學習記錄 page 顯示)
struct TripPatternRecord: Codable, Hashable, Identifiable {
    var id: String { "\(key.fromKey ?? "")-\(key.weekday)-\(key.timeSlot)-\(key.twoGramFromFromKey ?? "")" }
    var key: TripPatternKey
    var candidates: [String: TripNextCandidate]
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - TripPredictionLevel (action decision)
enum TripPredictionAction: Equatable {
    case ignore
    case askConfirm(place: PlaceInfo, confidence: Double, totalSamples: Int, twoStepAhead: PlaceInfo?)
    case autoSwitchToast(place: PlaceInfo, confidence: Double, totalSamples: Int, twoStepAhead: PlaceInfo?)
}

// MARK: - TripPredictionResult
struct TripPredictionResult: Hashable {
    var place: PlaceInfo
    var confidence: Double          // top.score / sum(scores)
    var totalSamples: Int           // all candidates.hitCount 合計
    var twoStepAheadPlace: PlaceInfo?   // 複雜路線：再下一個大概率目的地（例如港島→屯門office→家 會預測最終家）
}

// MARK: - PendingPrediction (UI 用)
struct PendingTripPrediction: Identifiable, Equatable {
    let id = UUID()
    var action: TripPredictionAction
    var predicted: PlaceInfo
    var confidence: Double
    var totalSamples: Int
    var twoStepAhead: PlaceInfo?
    var createdAt: Date
}

// MARK: - TripPredictor (main ObservableObject)
@MainActor
final class TripPredictor: ObservableObject {
    nonisolated(unsafe) static let shared = TripPredictor()

    @Published var placeCatalog: [String: PlaceInfo] = [:]
    @Published var patterns: [String: TripPatternRecord] = [:]
    @Published var recentPlaceHistory: [PlaceInfo] = [] // 最近 N 個 place，2-gram 3-gram 用

    @Published var pendingConfirm: PendingTripPrediction?   // 等待 user confirm sheet
    @Published var pendingToast: PendingTripPrediction?     // 自動切換 toast
    @Published var lastPredictionSummary: String? = nil

    private let catalogKey = "trip_predict_place_catalog_v1"
    private let patternsKey = "trip_predict_patterns_v1"
    private let historyKey = "trip_predict_recent_history_v1"

    private let maxHistoryLength = 10
    private var hasLoaded = false

    private init() {}

    func prepare() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            loadState()
        }
    }

    // MARK: - Public APIs

    /// 有 CLVisit depatureDate 時（即「真係離開咗某個地點」），調用 learning + 將 history 更新
    func recordLearning(
        fromPlace: PlaceInfo?,
        toPlace: PlaceInfo,
        atDate: Date = Date()
    ) {
        // 1. 入 catalog
        upsertPlaceInCatalog(toPlace)
        if let from = fromPlace { upsertPlaceInCatalog(from) }

        // 2. push history (keep latest 10)
        if recentPlaceHistory.last?.key != toPlace.key {
            recentPlaceHistory.append(toPlace)
            if recentPlaceHistory.count > maxHistoryLength {
                recentPlaceHistory.removeFirst(recentPlaceHistory.count - maxHistoryLength)
            }
        }

        // 3. pattern learning：1-gram + 2-gram
        guard let from = fromPlace else {
            // 第一次冇 from，唔學 pattern
            saveState()
            return
        }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: atDate)
        let slot = TripTimeSlot(date: atDate)

        // 1-gram key
        let oneKey = TripPatternKey(
            fromKey: from.key,
            weekday: weekday,
            timeSlot: slot,
            twoGramFromFromKey: nil
        )
        incrementPattern(key: oneKey, to: toPlace.key)

        // 2-gram key（複雜路線：之前仲有一個 from-from）
        if recentPlaceHistory.count >= 3 {
            let fromFrom = recentPlaceHistory[recentPlaceHistory.count - 3]
            let twoKey = TripPatternKey(
                fromKey: from.key,
                weekday: weekday,
                timeSlot: slot,
                twoGramFromFromKey: fromFrom.key
            )
            incrementPattern(key: twoKey, to: toPlace.key)
        }

        saveState()
    }

    /// 新到訪一個 place（CLVisit arrival）時 predict 下一站
    /// 返回 prediction level：ignore / ask confirm / auto toast
    func predictNext(
        currentPlace: PlaceInfo,
        atDate: Date = Date()
    ) -> TripPredictionAction {
        upsertPlaceInCatalog(currentPlace)

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: atDate)
        let slot = TripTimeSlot(date: atDate)

        // 先 try 2-gram（更準），冇命中就用 1-gram
        var patternKey: TripPatternKey? = nil
        if recentPlaceHistory.count >= 2 {
            let fromFrom = recentPlaceHistory[recentPlaceHistory.count - 2]
            let tk = TripPatternKey(
                fromKey: currentPlace.key,
                weekday: weekday,
                timeSlot: slot,
                twoGramFromFromKey: fromFrom.key
            )
            if let rec = patterns[patternID(tk)], rec.candidates.values.reduce(0, { $0 + $1.hitCount }) >= 3 {
                patternKey = tk
            }
        }
        if patternKey == nil {
            patternKey = TripPatternKey(
                fromKey: currentPlace.key,
                weekday: weekday,
                timeSlot: slot,
                twoGramFromFromKey: nil
            )
        }
        guard let key = patternKey else { return .ignore }
        guard let rec = patterns[patternID(key)] else { return .ignore }

        let candidates = Array(rec.candidates.values)
        let totalHits = candidates.reduce(0) { $0 + $1.hitCount }
        guard totalHits > 0 else { return .ignore }
        let scored = candidates
            .map { (key: $0.toPlaceKey, score: $0.effectiveScore) }
            .sorted { $0.score > $1.score }
        guard let best = scored.first, best.score > 0 else { return .ignore }
        let sum = scored.reduce(0.0) { $0 + max(0, $1.score) }
        guard sum > 0 else { return .ignore }
        let conf = best.score / sum

        guard let bestPlace = placeCatalog[best.key] else { return .ignore }

        // 2-step ahead predict 處理多目的地行程
        // 例：港島 → 屯門 office → 家；當前 position 港島，1-step predict office，2-step 再預測家
        var twoStepAhead: PlaceInfo? = nil
        if let nextRec = patterns[patternID(
            TripPatternKey(
                fromKey: bestPlace.key,
                weekday: weekday,
                timeSlot: slot,
                twoGramFromFromKey: currentPlace.key
            )
        )] {
            let candidates2 = Array(nextRec.candidates.values)
            let hits2 = candidates2.reduce(0) { $0 + $1.hitCount }
            if hits2 >= 3 {
                let scored2 = candidates2
                    .map { (key: $0.toPlaceKey, score: $0.effectiveScore) }
                    .sorted { $0.score > $1.score }
                if let best2 = scored2.first, best2.score > 0,
                   let p2 = placeCatalog[best2.key] {
                    let sum2 = scored2.reduce(0.0) { $0 + max(0, $1.score) }
                    if sum2 > 0 && (best2.score / sum2) >= 0.7 && p2.key != bestPlace.key {
                        twoStepAhead = p2
                    }
                }
            }
        }

        // thresholds：≥3 樣本 && 信心 ≥85% 自動切換；≥1 樣本 && 信心 ≥60% 彈確認卡
        var action: TripPredictionAction = .ignore
        if totalHits >= 3 && conf >= 0.85 {
            action = .autoSwitchToast(place: bestPlace, confidence: conf, totalSamples: totalHits, twoStepAhead: twoStepAhead)
        } else if totalHits >= 1 && conf >= 0.6 {
            action = .askConfirm(place: bestPlace, confidence: conf, totalSamples: totalHits, twoStepAhead: twoStepAhead)
        }

        // Queue UI pending items
        if case .askConfirm(let p, let c, let s, let ahead) = action {
            pendingConfirm = PendingTripPrediction(
                action: action,
                predicted: p,
                confidence: c,
                totalSamples: s,
                twoStepAhead: ahead,
                createdAt: Date()
            )
            pendingToast = nil
        } else if case .autoSwitchToast(let p, let c, let s, let ahead) = action {
            pendingToast = PendingTripPrediction(
                action: action,
                predicted: p,
                confidence: c,
                totalSamples: s,
                twoStepAhead: ahead,
                createdAt: Date()
            )
            pendingConfirm = nil
        } else {
            pendingConfirm = nil
            pendingToast = nil
        }

        var summary = "預測：\(bestPlace.displayName) 信心 \(Int(conf*100))% (樣本 \(totalHits))"
        if let ahead = twoStepAhead { summary += " 再下一步: \(ahead.displayName)" }
        lastPredictionSummary = summary

        return action
    }

    /// User 對 confirm sheet / toast 嘅 yes/no 反饋，加權學習
    func applyUserFeedback(prediction: PendingTripPrediction,
                           actualNextPlaceKey: String?,
                           confirmed: Bool) {
        // 對應 pattern 入面的 candidate 加權
        let predictedKey = prediction.predicted.key
        // 搵最近一條 match 咗嘅 pattern key 嚟反饋
        var targetKey: TripPatternKey? = nil
        if recentPlaceHistory.count >= 1 {
            let cal = Calendar.current
            let wd = cal.component(.weekday, from: Date())
            let slot = TripTimeSlot(date: Date())
            let last = recentPlaceHistory[recentPlaceHistory.count - 1]
            if recentPlaceHistory.count >= 2 {
                let fromFrom = recentPlaceHistory[recentPlaceHistory.count - 2]
                let tk = TripPatternKey(
                    fromKey: last.key,
                    weekday: wd, timeSlot: slot,
                    twoGramFromFromKey: fromFrom.key
                )
                if patterns[patternID(tk)]?.candidates[predictedKey] != nil {
                    targetKey = tk
                }
            }
            if targetKey == nil {
                targetKey = TripPatternKey(
                    fromKey: last.key, weekday: wd, timeSlot: slot,
                    twoGramFromFromKey: nil
                )
            }
        }
        if let k = targetKey, var rec = patterns[patternID(k)] {
            if confirmed {
                if rec.candidates[predictedKey] != nil {
                    rec.candidates[predictedKey]!.correctFeedbackCount += 1
                } else {
                    rec.candidates[predictedKey] = TripNextCandidate(
                        toPlaceKey: predictedKey,
                        hitCount: 1, correctFeedbackCount: 1, denyCount: 0
                    )
                }
            } else {
                if rec.candidates[predictedKey] != nil {
                    rec.candidates[predictedKey]!.denyCount += 1
                }
                if let actual = actualNextPlaceKey {
                    if rec.candidates[actual] != nil {
                        rec.candidates[actual]!.hitCount += 1
                    } else {
                        rec.candidates[actual] = TripNextCandidate(
                            toPlaceKey: actual,
                            hitCount: 1, correctFeedbackCount: 0, denyCount: 0
                        )
                    }
                }
            }
            rec.updatedAt = Date()
            patterns[patternID(k)] = rec
            saveState()
        }

        pendingConfirm = nil
        pendingToast = nil
    }

    // MARK: - Place Resolution helpers

    /// 根據 latlng / named lot / address 解析 PlaceInfo
    /// named lot 優先（if lot 在 180m 半徑內有 name）；否則 address cluster（200m grid + street prefix）
    func resolvePlace(
        coordinate: CLLocationCoordinate2D,
        address: String,
        parkingLots: [ParkingLotRecord]
    ) -> PlaceInfo {
        // 1) named lot nearby?
        let named = parkingLots.first(where: {
            $0.name?.isEmpty == false &&
            $0.centerDistance(to: coordinate) <= ParkingFloorStore.defaultRadiusMeters
        })
        if let n = named, let name = n.name {
            let key = "lot:\(n.id.uuidString)"
            let now = Date()
            if var existing = placeCatalog[key] {
                if existing.displayName != name {
                    existing.displayName = name
                    existing.updatedAt = now
                    placeCatalog[key] = existing
                }
                return PlaceInfo(
                    key: key, kind: .namedLot,
                    displayName: name,
                    latitude: n.centerLatitude ?? coordinate.latitude,
                    longitude: n.centerLongitude ?? coordinate.longitude,
                    lotID: n.id, updatedAt: now
                )
            }
            return PlaceInfo(
                key: key, kind: .namedLot,
                displayName: name,
                latitude: n.centerLatitude ?? coordinate.latitude,
                longitude: n.centerLongitude ?? coordinate.longitude,
                lotID: n.id, updatedAt: Date()
            )
        }
        // 2) address cluster
        let lat4 = round(coordinate.latitude * 10000) / 10000
        let lng4 = round(coordinate.longitude * 10000) / 10000
        let prefix = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? String(format: "%.4f,%.4f", lat4, lng4)
        let clusterKey = String(format: "addr:%.4f:%.4f:\(prefix)", lat4, lng4)
        let display = address.isEmpty ? prefix : address
        return PlaceInfo(
            key: clusterKey, kind: .addressCluster,
            displayName: display,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            lotID: nil, updatedAt: Date()
        )
    }

    // MARK: - Internal

    private func patternID(_ k: TripPatternKey) -> String {
        let w = k.weekday
        let t = k.timeSlot.rawValue
        let f = k.fromKey ?? "nil"
        let ff = k.twoGramFromFromKey ?? "nil"
        return "\(f)|\(ff)|\(w)|\(t)"
    }

    private func incrementPattern(key: TripPatternKey, to placeKey: String) {
        let pid = patternID(key)
        let now = Date()
        if var rec = patterns[pid] {
            if rec.candidates[placeKey] != nil {
                rec.candidates[placeKey]!.hitCount += 1
            } else {
                rec.candidates[placeKey] = TripNextCandidate(
                    toPlaceKey: placeKey,
                    hitCount: 1, correctFeedbackCount: 0, denyCount: 0
                )
            }
            rec.updatedAt = now
            patterns[pid] = rec
        } else {
            patterns[pid] = TripPatternRecord(
                key: key,
                candidates: [
                    placeKey: TripNextCandidate(
                        toPlaceKey: placeKey,
                        hitCount: 1, correctFeedbackCount: 0, denyCount: 0
                    )
                ],
                createdAt: now, updatedAt: now
            )
        }
    }

    private func upsertPlaceInCatalog(_ p: PlaceInfo) {
        if var existing = placeCatalog[p.key] {
            existing.updatedAt = Date()
            if existing.displayName.isEmpty && !p.displayName.isEmpty {
                existing.displayName = p.displayName
            }
            if p.lotID != nil && existing.lotID == nil {
                existing.lotID = p.lotID
            }
            placeCatalog[p.key] = existing
        } else {
            placeCatalog[p.key] = p
        }
    }

    // MARK: - Place Rename

    /// 統一改名：更新 placeCatalog 中的 displayName
    /// 同步更新對應嘅 ParkingLotRecord（如果存在）
    func renamePlace(key: String, newName: String) {
        guard var place = placeCatalog[key] else { return }
        place.displayName = newName
        place.updatedAt = Date()
        placeCatalog[key] = place
        saveState()
        // 如果係地址叢集，同步更新對應嘅停車場
        if key.hasPrefix("addr:") {
            let coord = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            ParkingFloorStore.shared.syncLotName(near: coord, newName: newName)
        }
    }

    /// 根據 lotID 更新 placeCatalog 中對應的 displayName
    func renameLotPlace(lotID: UUID, newName: String) {
        let key = "lot:\(lotID.uuidString)"
        if var place = placeCatalog[key] {
            place.displayName = newName
            place.updatedAt = Date()
            placeCatalog[key] = place
            saveState()
        }
    }

    /// 刪除學習地點（移出 placeCatalog）—— soft delete，記錄由 ParkingFloorStore 回收桶保存
    func removePlace(key: String) {
        guard placeCatalog.removeValue(forKey: key) != nil else { return }
        saveState()
    }

    /// 還原學習地點（放返入 placeCatalog，key／預測記錄引用都會跟返）
    func restorePlace(_ place: PlaceInfo) {
        placeCatalog[place.key] = place
        saveState()
    }

    /// 同步地址叢集名稱：搵到同一位置嘅 addr: 記錄並更新 displayName
    func syncClusterName(nearLatitude lat: Double, longitude lng: Double, newName: String?) {
        let loc = CLLocation(latitude: lat, longitude: lng)
        for (key, place) in placeCatalog {
            guard key.hasPrefix("addr:") else { continue }
            let placeLoc = CLLocation(latitude: place.latitude, longitude: place.longitude)
            if placeLoc.distance(from: loc) <= 180 {
                var updated = place
                updated.displayName = newName ?? place.displayName
                updated.updatedAt = Date()
                placeCatalog[key] = updated
            }
        }
        saveState()
    }

    // MARK: - Persistence

    private func saveState() {
        if let d = try? JSONEncoder().encode(placeCatalog) {
            UserDefaults.standard.set(d, forKey: catalogKey)
        }
        if let d = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(d, forKey: patternsKey)
        }
        if let d = try? JSONEncoder().encode(recentPlaceHistory) {
            UserDefaults.standard.set(d, forKey: historyKey)
        }
        UserDefaults.standard.synchronize()
    }

    private func loadState() {
        if let d = UserDefaults.standard.data(forKey: catalogKey),
           let v = try? JSONDecoder().decode([String: PlaceInfo].self, from: d) {
            placeCatalog = v
        }
        if let d = UserDefaults.standard.data(forKey: patternsKey),
           let v = try? JSONDecoder().decode([String: TripPatternRecord].self, from: d) {
            patterns = v
        }
        if let d = UserDefaults.standard.data(forKey: historyKey),
           let v = try? JSONDecoder().decode([PlaceInfo].self, from: d) {
            recentPlaceHistory = v
        }
        reconcilePlaceNames(with: ParkingFloorStore.shared.lots)
    }

    /// 舊資料有機會將同一位置分別保存成 POI 停車點及地區地址叢集。
    /// 載入時以停車點使用的名稱為準，令地圖與「地點管理」保持一致。
    func reconcilePlaceNames(with parkingLots: [ParkingLotRecord]) {
        var changed = false
        for (key, place) in placeCatalog where place.kind == .addressCluster {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let nearbyLots = parkingLots.compactMap { lot -> (ParkingLotRecord, CLLocationDistance)? in
                guard lot.preferredDisplayName != nil else { return nil }
                let lotLocation = CLLocation(latitude: lot.centerLatitude, longitude: lot.centerLongitude)
                let distance = placeLocation.distance(from: lotLocation)
                return distance <= ParkingFloorStore.defaultRadiusMeters ? (lot, distance) : nil
            }
            guard let matched = nearbyLots.min(by: { $0.1 < $1.1 }),
                  let preferredName = matched.0.preferredDisplayName,
                  place.displayName != preferredName else { continue }

            var updated = place
            updated.displayName = preferredName
            updated.updatedAt = max(updated.updatedAt, matched.0.updatedAt)
            placeCatalog[key] = updated
            changed = true
        }
        if changed { saveState() }
    }
}
