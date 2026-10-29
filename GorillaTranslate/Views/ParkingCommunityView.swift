import SwiftUI
import VisionKit
import AVFoundation
import UserNotifications

struct ParkingCommunityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("parkingCommunity.didOnboard.v1") private var didOnboard = false
    @StateObject private var store = ParkingCommunityStore()
    @State private var settings = false
    @State private var manual = false
    @State private var target: String?
    @State private var cameraAllowed = false
    @State private var cameraError: String?

    var body: some View {
        NavigationStack {
            Group {
                if !didOnboard {
                    CommunityPlateSettings(store: store, introductory: true) { didOnboard = true }
                } else {
                    scanner
                }
            }
            .navigationTitle("泊車互助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                if didOnboard {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { settings = true } label: { Image(systemName: "car.side.and.exclamationmark") }
                            .accessibilityLabel("車牌與提醒設定")
                    }
                }
            }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    CommunityPlateSettings(store: store, introductory: false) {}
                        .navigationTitle("車牌與提醒")
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { settings = false } } }
                }
            }
            .sheet(isPresented: $manual) {
                NavigationStack {
                    CommunityPlateEntry(title: "輸入對方車牌") { plate in
                        manual = false
                        target = plate
                    }
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { manual = false } } }
                }
            }
            .navigationDestination(isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
                if let target { CommunityMessageComposer(plate: target) }
            }
            .task(id: didOnboard) { if didOnboard { await prepareCamera() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && didOnboard { Task { await prepareCamera() } }
            }
        }
    }

    private var scanner: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                if cameraAllowed && DataScannerViewController.isSupported && DataScannerViewController.isAvailable && scenePhase == .active && !settings && !manual && target == nil {
                    CommunityPlateScanner(onPlate: { target = $0 }, onError: { cameraError = $0; cameraAllowed = false })
                } else {
                    Rectangle().fill(.quaternary)
                    ContentUnavailableView("掃描車牌", systemImage: "viewfinder", description: Text(cameraError ?? "相機未開啟或此裝置不支援即時辨識，仍可手動輸入。"))
                }
                Text("將標準車牌放入鏡頭，點選辨識結果確認")
                    .font(.footnote).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .frame(maxHeight: .infinity)
            if cameraError != nil {
                Button("開啟系統設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button { manual = true } label: {
                Label("手動輸入車牌", systemImage: "keyboard").frame(maxWidth: .infinity).padding(8)
            }.buttonStyle(.borderedProminent)
            Text("自訂車牌請手動輸入。辨識後仍需確認車牌。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("服務準備中：目前可掃牌及預覽訊息，尚未連接帳號或遠端通知。")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding()
    }

    @MainActor private func prepareCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraAllowed = true; cameraError = nil
        case .notDetermined:
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
            cameraError = cameraAllowed ? nil : "相機權限未開啟，可在設定啟用或手動輸入車牌。"
        default: cameraAllowed = false; cameraError = "相機權限未開啟，可在設定啟用或手動輸入車牌。"
        }
    }
}

private struct CommunityPlateSettings: View {
    @ObservedObject var store: ParkingCommunityStore
    let introductory: Bool
    let onContinue: () -> Void
    @State private var adding = false
    @State private var notificationStatus = "尚未檢查"

    var body: some View {
        List {
            Section {
                Label("掃牌、一撳，提醒車主", systemImage: "bubble.left.and.text.bubble.right")
                Text("先設定自己駕駛的車牌，亦可略過，直接幫其他車主發提醒。相同車牌可以多人綁定，所有綁定者共用提醒對話。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("我的車牌（本機草稿）") {
                ForEach(store.drafts) { draft in
                    HStack {
                        Text(draft.plate).font(.system(.title3, design: .monospaced).bold())
                        Spacer()
                        Text("待連接帳號").font(.caption).foregroundStyle(.secondary)
                    }.swipeActions {
                        Button("刪除", role: .destructive) { store.remove(draft.id) }
                    }
                }
                Button("新增車牌", systemImage: "plus") { adding = true }
                Text("草稿只儲存在此裝置，尚未完成綁定，不能接收遠端提醒。可向左掃刪除。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("推送通知") {
                LabeledContent("系統權限", value: notificationStatus)
                Button("開啟提醒權限") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                        await refreshNotifications()
                    }
                }
                Text("開啟權限後，仍需完成帳號綁定及接通通知服務，才可收到提醒。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("私隱與使用說明") {
                Text("只用於自願泊車互助；不是抄牌預警工具，不保證資訊準確。不得騷擾、起底或爭執。")
                Text("本 App 不提供咪錶付款或代繳。墊款、還錢與酬謝屬雙方自願私人安排，平台不介入金錢糾紛。")
                Text("本機版本不儲存對話。正式服務的訊息將於 7 日後自動刪除；上線前需完成後端刪除機制。")
            }.font(.footnote)
            if introductory {
                Section {
                    Button(store.drafts.isEmpty ? "略過，開始掃牌" : "儲存草稿，開始掃牌", action: onContinue)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .task { await refreshNotifications() }
        .sheet(isPresented: $adding) {
            NavigationStack {
                CommunityPlateEntry(title: "新增我的車牌", requiresConsent: true) {
                    store.saveDraft($0); adding = false
                }
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { adding = false } } }
            }
        }
    }
    @MainActor private func refreshNotifications() async {
        let value = await UNUserNotificationCenter.current().notificationSettings()
        switch value.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationStatus = "已允許"
        case .denied: notificationStatus = "已關閉，請到系統設定開啟"
        default: notificationStatus = "未設定"
        }
    }
}

private struct CommunityPlateEntry: View {
    let title: String
    var requiresConsent = false
    let onConfirm: (String) -> Void
    @State private var plate = ""
    @State private var consent = false
    private let rows = [Array("1234567890"), Array("ABCDEFGH"), Array("JKLMNPRS"), Array("TUVWXYZ")]
    var body: some View {
        VStack(spacing: 20) {
            Text(plate.isEmpty ? "車牌號碼" : plate)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(plate.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("車牌：\(plate)")
            Text("最多 8 個字元，空格亦計算在內。不提供 I、O、Q。")
                .font(.footnote).foregroundStyle(.secondary)
            if requiresConsent {
                Toggle("我確認是車主或獲授權駕駛者，並同意使用此車牌接收泊車提醒。", isOn: $consent)
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { character in
                        Button(String(character)) { append(String(character)) }
                            .font(.system(.headline, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
                            .disabled(plate.count >= 8)
                    }
                }
            }
            HStack {
                Button("清除") { plate = "" }
                Spacer()
                Button("空格") { append(" ") }.disabled(plate.isEmpty || plate.hasSuffix(" ") || plate.count >= 8)
                Spacer()
                Button { if !plate.isEmpty { plate.removeLast() } } label: { Image(systemName: "delete.left") }
                    .accessibilityLabel("刪除上一個字元")
            }.buttonStyle(.bordered)
            Button(requiresConsent ? "儲存車牌草稿" : "確認車牌") { onConfirm(plate.trimmingCharacters(in: .whitespaces)) }
                .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                .disabled(!HKCommunityPlate.isValid(plate) || (requiresConsent && !consent))
        }.padding().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    private func append(_ value: String) { if plate.count < 8 { plate += value } }
}

private struct CommunityMessageComposer: View {
    let plate: String
    @State private var selected = "留意入返咪錶"
    @State private var custom = ""
    private let templates = ["小心違例泊車", "留意入返咪錶", "我幫你墊錢入咗咪錶", "自由輸入文字"]
    var body: some View {
        Form {
            Section("確認對方車牌") {
                Text(plate).font(.system(.largeTitle, design: .monospaced).bold())
                Text("請核對實際車牌，避免提醒錯人。").font(.footnote)
            }
            Section("提醒內容") {
                ForEach(templates, id: \.self) { text in
                    Button { selected = text } label: {
                        HStack { Text(text); Spacer(); if selected == text { Image(systemName: "checkmark") } }
                    }.foregroundStyle(.primary)
                }
                if selected == "自由輸入文字" {
                    TextField("輸入提醒（最多 200 字）", text: $custom, axis: .vertical)
                        .onChange(of: custom) { _, value in custom = String(value.prefix(200)) }
                }
            }
            Section("通知預覽") { Text(selected == "自由輸入文字" ? custom : selected) }
            Section {
                Label("帳號及通知服務尚未接通", systemImage: "network.slash")
                Text("目前無法查詢車牌是否已綁定，亦不會發出訊息。正式版首次發送前需要登入，無需綁定自己的車牌。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("登入後發送（尚未開放）") {}.disabled(true)
            }
            Section {
                Text("「我幫你墊錢入咗咪錶」只代表發送者的陳述，並非平台核實付款。所有咪錶操作由用戶在 App 外獨立完成。")
            }.font(.footnote)
        }.navigationTitle("發送提醒")
    }
}

/// On-device live OCR. Only standard plate candidates are accepted, and tapping
/// merely opens confirmation: recognition never sends a notification automatically.
private struct CommunityPlateScanner: UIViewControllerRepresentable {
    let onPlate: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPlate: onPlate, onError: onError) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text(languages: ["en-US"])], qualityLevel: .accurate,
            recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() } catch {
            DispatchQueue.main.async { onError("相機辨識未能啟動，請手動輸入車牌。") }
        }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPlate: (String) -> Void
        let onError: (String) -> Void
        init(onPlate: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.onPlate = onPlate; self.onError = onError }
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let text) = item, let plate = HKCommunityPlate.standardCandidate(text.transcript) else { return }
            dataScanner.stopScanning()
            onPlate(plate)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError("即時辨識暫時不可用，請使用手動輸入。")
        }
    }
}
