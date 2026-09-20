import SwiftUI

/// 預測目的地測試頁
struct PredictionTestView: View {
    @ObservedObject private var predictor = TripPredictor.shared
    @EnvironmentObject private var destinationManager: DestinationManager

    var body: some View {
        List {
            // MARK: - 閾值說明
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.cyan)
                        Text("預測閾值")
                            .font(.headline)
                    }
                    Divider()
                    HStack {
                        Text("彈出確認卡")
                            .font(.subheadline.bold())
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("≥ 3 次樣本")
                            Text("≥ 60% 信心度")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("自動切換（Toast）")
                            .font(.subheadline.bold())
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("≥ 6 次樣本")
                            Text("≥ 85% 信心度")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("觸發條件")
            }

            // MARK: - 最近預測結果
            Section {
                if let pending = predictor.pendingConfirm {
                    predictionRow(title: "確認卡待確認", prediction: pending)
                } else if let toast = predictor.pendingToast {
                    predictionRow(title: "自動切換 Toast", prediction: toast)
                } else {
                    Text("暫無待確認嘅預測")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("最近預測")
            } footer: {
                if let summary = predictor.lastPredictionSummary {
                    Text(summary)
                }
            }

            // MARK: - 地點目錄
            Section {
                if predictor.placeCatalog.isEmpty {
                    Text("暫無學習到嘅地點")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(predictor.placeCatalog.values.sorted(by: { $0.displayName < $1.displayName })), id: \.key) { place in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: place.kind == .namedLot ? "tag.fill" : "mappin.circle.fill")
                                    .foregroundColor(place.kind == .namedLot ? .orange : .blue)
                                    .font(.caption)
                                Text(place.displayName)
                                    .font(.subheadline.bold())
                            }
                            Text("類型: \(place.kind == .namedLot ? "命名停車場" : "地址群組") • \(place.key)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("地點目錄")
                    Spacer()
                    Text("\(predictor.placeCatalog.count) 個")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - 學習模式
            Section {
                if predictor.patterns.isEmpty {
                    Text("暫無學習到嘅模式")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(predictor.patterns.values.sorted(by: { $0.updatedAt > $1.updatedAt })), id: \.id) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            // Pattern key
                            HStack {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundColor(.purple)
                                    .font(.caption)
                                Text(patternKeyDescription(record.key))
                                    .font(.subheadline.bold())
                            }

                            // Candidates
                            ForEach(Array(record.candidates.values.sorted(by: { $0.effectiveScore > $1.effectiveScore })), id: \.toPlaceKey) { candidate in
                                HStack {
                                    Text("→ \(placeName(for: candidate.toPlaceKey))")
                                        .font(.caption)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("有效分: \(String(format: "%.1f", candidate.effectiveScore))")
                                            .font(.caption2.bold())
                                        Text("命中\(candidate.hitCount) 確認\(candidate.correctFeedbackCount) 否認\(candidate.denyCount)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                HStack {
                    Text("學習模式")
                    Spacer()
                    Text("\(predictor.patterns.count) 條")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - 最近歷史
            Section {
                if predictor.recentPlaceHistory.isEmpty {
                    Text("暫無最近歷史")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(predictor.recentPlaceHistory.prefix(20), id: \.key) { place in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.displayName)
                                    .font(.subheadline)
                                Text(place.kind == .namedLot ? "命名停車場" : "地址群組")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("最近歷史")
            }

            // MARK: - 當前目的地
            Section {
                if let dest = destinationManager.selectedDestination {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(dest.name)
                                .font(.subheadline.bold())
                            Text("\(dest.coordinate.latitude), \(dest.coordinate.longitude)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } else {
                    Text("未選擇目的地")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("當前目的地")
            }
        }
        .navigationTitle("預測目的地測試")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helper Views
    private func predictionRow(title: String, prediction: PendingTripPrediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text("確認")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cyan.opacity(0.2)))
            }

            HStack {
                Text("預測: \(prediction.predicted.displayName)")
                    .font(.subheadline)
                Spacer()
                confidenceBadge(prediction.confidence)
            }

            HStack {
                Text("樣本數: \(prediction.totalSamples)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(prediction.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let ahead = prediction.twoStepAhead {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("再下一步: \(ahead.displayName)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        let percent = Int(confidence * 100)
        let color: Color = percent >= 85 ? .green : (percent >= 60 ? .orange : .red)
        return Text("\(percent)%")
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Helpers
    private func patternKeyDescription(_ key: TripPatternKey) -> String {
        let from = key.fromKey.map { placeName(for: $0) } ?? "（起點未知）"
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][max(0, key.weekday - 1)]
        let slot = key.timeSlot.description
        var desc = "\(from) → [週\(weekday) \(slot)]"
        if let twoGram = key.twoGramFromFromKey {
            desc = "\(placeName(for: twoGram)) → \(desc)"
        }
        return desc
    }

    private func placeName(for key: String) -> String {
        predictor.placeCatalog[key]?.displayName ?? key
    }
}
