import SwiftUI
import VisionKit
import Vision
import ImageIO
import AVFoundation
import UserNotifications

struct ParkingCommunityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("parkingCommunity.didOnboard.v1") private var didOnboard = false
    @StateObject private var store = ParkingCommunityStore()
    @ObservedObject private var push = CommunityPushCoordinator.shared
    @State private var settings = false
    @State private var inbox = false
    @State private var manual = false
    @State private var target: String?
    @State private var cameraAllowed = false
    @State private var scannerUnavailable = false
    @State private var cameraError: String?
    @State private var plateCandidates: [String] = []
    @State private var scannerHint = "對準完整車牌，辨識結果會顯示喺下方。"
    @State private var photograph = false
    @State private var photoBusy = false
    @State private var photoPreview: UIImage?

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
                        Menu {
                            Button("提醒對話", systemImage: "bubble.left.and.bubble.right") { inbox = true }
                            Button("車牌與提醒設定", systemImage: "car.side") { settings = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("泊車互助選單")
                    }
                }
            }
            .sheet(isPresented: $inbox) {
                NavigationStack {
                    CommunityInbox(store: store)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { inbox = false } } }
                }
            }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    CommunityPlateSettings(store: store, introductory: false) {}
                        .navigationTitle("車牌與提醒")
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { settings = false } } }
                }
            }
            .sheet(isPresented: $photograph) {
                CommunityPlatePhotoCamera { image in
                    photograph = false
                    guard let image else { return }
                    photoBusy = true
                    photoPreview = image
                    plateCandidates = []
                    Task { await recognisePhoto(image) }
                }.ignoresSafeArea()
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
                if let target { CommunityMessageComposer(plate: target, store: store) }
            }
            .onReceive(NotificationCenter.default.publisher(for: CommunityPushCoordinator.openThread)) { note in
                if note.object is String { inbox = true }
            }
            .task(id: didOnboard) {
                if push.pendingThreadID != nil { inbox = true }
                if didOnboard { await prepareCamera() }; await store.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && didOnboard { Task { await prepareCamera() } }
            }
        }
    }

    private var scanner: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                if let photoPreview {
                    Image(uiImage: photoPreview).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                } else if cameraAllowed && !scannerUnavailable && DataScannerViewController.isSupported && DataScannerViewController.isAvailable && scenePhase == .active && !settings && !inbox && !manual && !photograph && !photoBusy && target == nil {
                    CommunityPlateScanner(onPlate: { target = $0 }, onError: { cameraError = $0; scannerUnavailable = true },
                        onCandidates: { plateCandidates = $0 }, onHint: { scannerHint = $0 })
                } else {
                    Rectangle().fill(.quaternary)
                    ContentUnavailableView("掃描車牌", systemImage: "viewfinder", description: Text(cameraError ?? "相機未開啟或此裝置不支援即時辨識，仍可手動輸入。"))
                }
                Text(photoBusy ? "正在辨識相片…" : scannerHint)
                    .font(.footnote).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .frame(maxHeight: .infinity)
            if !plateCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(plateCandidates, id: \.self) { plate in
                            Button { target = plate } label: {
                                Label(plate, systemImage: "checkmark.circle")
                                    .font(.system(.title3, design: .monospaced).bold()).padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                Text("撳車牌結果確認；即時結果會保留約 4 秒。").font(.caption).foregroundStyle(.secondary)
            }
            if photoPreview != nil {
                Button("返回即時掃描") { photoPreview = nil; plateCandidates = []; scannerHint = "對準完整車牌。" }.disabled(photoBusy)
            }
            if scannerUnavailable && cameraAllowed {
                Button("重新啟動即時掃描") { scannerUnavailable = false; cameraError = nil }
            }
            if !cameraAllowed && cameraError != nil {
                Button("開啟系統設定") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { photograph = true } label: { Label("拍照辨識", systemImage: "camera") }
                        .disabled(photoBusy || !cameraAllowed)
                }
                Button { manual = true } label: { Label("手動輸入", systemImage: "keyboard") }
            }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            Text("自訂車牌請手動輸入。辨識後仍需確認車牌。")
                .font(.footnote).foregroundStyle(.secondary)
            Text(store.configured ? push.status : "服務尚未設定：目前可掃牌及預覽訊息，未能查詢或發送提醒。")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding()
    }

    @MainActor private func recognisePhoto(_ image: UIImage) async {
        defer { photoBusy = false }
        guard let cgImage = image.cgImage else { scannerHint = "無法讀取相片，請重新拍照。"; return }
        let orientation = CommunityPhotoOCR.orientation(image.imageOrientation)
        do {
            plateCandidates = try await Task.detached(priority: .userInitiated) {
                try CommunityPhotoOCR.read(cgImage, orientation: orientation)
            }.value
            scannerHint = plateCandidates.isEmpty ? "未能讀到完整車牌，請拉近重拍或手動輸入。" : "相片辨識完成，請揀選並核對車牌。"
        } catch { scannerHint = "相片辨識未完成，請重拍或手動輸入。" }
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
    @ObservedObject private var push = CommunityPushCoordinator.shared
    let introductory: Bool
    let onContinue: () -> Void
    @State private var adding = false
    @State private var login = false
    @State private var deleting = false
    @State private var notificationStatus = "尚未檢查"
    @State private var serverAddress = ""
    @State private var serverNote = ""

    var body: some View {
        List {
            Section {
                Label("掃牌、一撳，提醒車主", systemImage: "bubble.left.and.text.bubble.right")
                Text("先設定自己駕駛的車牌，亦可略過，直接幫其他車主發提醒。相同車牌可以多人綁定，所有綁定者共用提醒對話。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("帳號") {
                if store.signedIn {
                    Label("已登入泊車互助", systemImage: "person.crop.circle.badge.checkmark")
                    Button("登出") { Task { await store.logout() } }
                    Button("刪除帳號與資料", role: .destructive) { deleting = true }
                } else {
                    Button("登入／註冊") { login = true }.disabled(!store.configured)
                    if !store.configured { Text("提醒服務尚未設定，請稍後再試。").font(.footnote) }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            #if DEBUG
            Section("測試伺服器網址") {
                TextField("https://xxx.trycloudflare.com/v1/parking-community", text: $serverAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote)
                LabeledContent("目前連線", value: CommunityHTTPClient.configuredURL?.absoluteString ?? "未設定")
                    .font(.footnote)
                Button("儲存網址") {
                    let value = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        UserDefaults.standard.removeObject(forKey: CommunityHTTPClient.overrideKey)
                        serverNote = "已回復預設網址。"
                    } else {
                        guard CommunityHTTPClient.validated(value) != nil else {
                            serverNote = "網址格式不正確，須為 https 完整網址。"
                            return
                        }
                        UserDefaults.standard.set(value, forKey: CommunityHTTPClient.overrideKey)
                        serverNote = "已儲存。更換網址後請重新登入。"
                    }
                    Task { await store.refresh() }
                }
                Button("清除並回復預設", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: CommunityHTTPClient.overrideKey)
                    serverAddress = ""
                    serverNote = "已回復預設網址。"
                    Task { await store.refresh() }
                }
                if !serverNote.isEmpty { Text(serverNote).font(.footnote).foregroundStyle(.secondary) }
                Text("tunnel 網址變更時在此貼上新網址即可，不需重新安裝 App；換網址後需重新登入。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            #endif
            if !store.boundPlates.isEmpty {
                Section("已綁定車牌") {
                    ForEach(store.boundPlates) { binding in
                        HStack {
                            Text(binding.plate).font(.system(.title3, design: .monospaced).bold())
                            Spacer()
                            Text("已綁定").font(.caption).foregroundStyle(.secondary)
                        }.swipeActions {
                            Button("解除綁定", role: .destructive) { Task { await store.unbind(binding.plate) } }
                        }
                    }
                    Text("同一車牌可以多人綁定，共同接收提醒。解除綁定後不能再查看該車牌過往收到的對話。").font(.footnote)
                }
            }
            Section("我的車牌（本機草稿）") {
                ForEach(store.drafts) { draft in
                    HStack {
                        Text(draft.plate).font(.system(.title3, design: .monospaced).bold())
                        Spacer()
                        if store.signedIn {
                            Button("綁定") { Task { await store.bindDraft(draft) } }
                        } else {
                            Text("待登入綁定").font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions {
                        Button("刪除", role: .destructive) { store.remove(draft.id) }
                    }
                }
                Button("新增車牌", systemImage: "plus") { adding = true }
                Text("草稿只儲存在此裝置，需登入後按「綁定」同步至服務。可向左掃刪除。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("推送通知") {
                LabeledContent("系統權限", value: notificationStatus)
                Button("開啟提醒權限") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                        await refreshNotifications()
                        await push.sync()
                    }
                }
                Text(push.status)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("私隱與使用說明") {
                Text("只用於自願泊車互助；不是抄牌預警工具，不保證資訊準確。不得騷擾、起底或爭執。")
                Text("本 App 不提供咪錶付款或代繳。墊款、還錢與酬謝屬雙方自願私人安排，平台不介入金錢糾紛。")
                Text("對話於建立後 7 日到期，回覆不會延長期限；不在手機永久儲存對話。車牌只用於泊車提醒，不作出售用途。")
            }.font(.footnote)
            if introductory {
                Section {
                    Button(store.drafts.isEmpty ? "略過，開始掃牌" : "儲存草稿，開始掃牌", action: onContinue)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .task {
            if serverAddress.isEmpty { serverAddress = UserDefaults.standard.string(forKey: CommunityHTTPClient.overrideKey) ?? "" }
            await refreshNotifications(); await store.refresh()
        }
        .refreshable { await store.refresh(); await refreshNotifications() }
        .confirmationDialog("刪除帳號、車牌綁定及訊息？此操作無法復原。", isPresented: $deleting, titleVisibility: .visible) {
            Button("永久刪除", role: .destructive) { Task { await store.deleteAccount() } }
        }
        .sheet(isPresented: $login) { CommunityLoginView(store: store) }
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
    @ObservedObject var store: ParkingCommunityStore
    @ObservedObject private var push = CommunityPushCoordinator.shared
    @State private var login = false
    @State private var busy = false
    @State private var result: CommunitySendResult?
    @State private var error: String?
    @State private var requestKey = UUID()
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
                if let result {
                    Label(result.pushStatus == "queued" ? "提醒已儲存並加入推送佇列" : "提醒已儲存，推送尚未設定", systemImage: "checkmark.circle")
                    NavigationLink("查看提醒對話") { CommunityThreadDetail(store: store, threadID: result.threadId, plate: plate) }
                } else {
                    Button(store.signedIn ? "發送提醒" : "登入後發送") {
                        if !store.signedIn { login = true }
                        else { Task { await send() } }
                    }.disabled(!store.configured || busy || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if busy { ProgressView() }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if !store.configured { Text("提醒服務尚未設定，暫時無法查詢或發送。").font(.footnote) }
                Text("所有已綁定者共用同一條對話。推送不代表對方已閱讀，仍可在對話內查看。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("「我幫你墊錢入咗咪錶」只代表發送者的陳述，並非平台核實付款。所有咪錶操作由用戶在 App 外獨立完成。")
            }.font(.footnote)
        }.navigationTitle("發送提醒")
        .sheet(isPresented: $login) { CommunityLoginView(store: store) }
        .onChange(of: selected) { _, _ in requestKey = UUID(); result = nil; error = nil }
        .onChange(of: custom) { _, _ in requestKey = UUID(); result = nil; error = nil }
        .disabled(busy)
    }
    private var message: String { selected == "自由輸入文字" ? custom : selected }
    @MainActor private func send() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            result = try await store.api.send(plate: plate, text: message, key: requestKey)
            await store.refresh()
        } catch { self.error = error.localizedDescription; store.handle(error) }
    }
}

/// Live observations are combined spatially and surfaced as persistent buttons.
/// No result sends automatically, and ambiguous characters are never substituted.
private struct CommunityPlateScanner: UIViewControllerRepresentable {
    let onPlate: (String) -> Void
    let onError: (String) -> Void
    let onCandidates: ([String]) -> Void
    let onHint: (String) -> Void
    func makeCoordinator() -> Coordinator {
        Coordinator(onPlate: onPlate, onError: onError, onCandidates: onCandidates, onHint: onHint)
    }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text(languages: ["en-US"])], qualityLevel: .accurate,
            recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: false)
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        // Start after the view has been attached, rather than during construction.
        DispatchQueue.main.async {
            guard context.coordinator.active else { return }
            do { try scanner.startScanning(); context.coordinator.startExpiryTimer() }
            catch { onError("相機辨識未能啟動，請使用拍照辨識或手動輸入。") }
        }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        coordinator.active = false
        coordinator.timer?.invalidate()
        controller.stopScanning()
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPlate: (String) -> Void
        let onError: (String) -> Void
        let onCandidates: ([String]) -> Void
        let onHint: (String) -> Void
        weak var scanner: DataScannerViewController?
        var active = true
        var timer: Timer?
        var held = CommunityOCRHold()
        var displayed: [String] = []
        var lastProcessed = Date.distantPast
        var overlays: [String: UIButton] = [:]
        var overlayLastSeen: [String: Date] = [:]
        init(onPlate: @escaping (String) -> Void, onError: @escaping (String) -> Void,
             onCandidates: @escaping ([String]) -> Void, onHint: @escaping (String) -> Void) {
            self.onPlate = onPlate; self.onError = onError
            self.onCandidates = onCandidates; self.onHint = onHint
        }
        func startExpiryTimer() {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.publish([]) }
            }
        }
        func publish(_ current: [String]) {
            guard active else { return }
            let result = held.update(current, now: Date())
            if result != displayed { displayed = result; onCandidates(result) }
            for plate in Array(overlays.keys) {
                if !result.contains(plate) || Date().timeIntervalSince(overlayLastSeen[plate] ?? .distantPast) > 0.8 {
                    overlays.removeValue(forKey: plate)?.removeFromSuperview()
                    overlayLastSeen.removeValue(forKey: plate)
                }
            }
        }
        func process(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard active, Date().timeIntervalSince(lastProcessed) >= 0.15 else { return }
            lastProcessed = Date()
            let segments: [CommunityOCRSegment] = items.compactMap { item in
                guard case .text(let text) = item else { return nil }
                let points = [text.bounds.topLeft, text.bounds.topRight, text.bounds.bottomLeft, text.bounds.bottomRight]
                let xs = points.map(\.x), ys = points.map(\.y)
                let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                return .init(text: text.transcript, bounds: rect)
            }
            let candidates = CommunityPlateOCR.candidates(segments)
            publish(candidates.map(\.plate))
            onHint(candidates.isEmpty ? "對準完整車牌；可拉近鏡頭，或按「拍照辨識」。" : "已找到候選車牌，撳下方按鈕確認。")
            for candidate in candidates {
                overlayLastSeen[candidate.plate] = Date()
                let button: UIButton
                if let existing = overlays[candidate.plate] { button = existing }
                else {
                    button = UIButton(type: .custom)
                    button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.3)
                    button.layer.cornerRadius = 10
                    button.layer.borderWidth = 2
                    button.layer.borderColor = scanner.view.tintColor.resolvedColor(with: scanner.traitCollection).cgColor
                    button.accessibilityLabel = "確認車牌 \(candidate.plate)"
                    button.addAction(UIAction { [weak self] _ in self?.onPlate(candidate.plate) }, for: .touchUpInside)
                    scanner.overlayContainerView.addSubview(button)
                    overlays[candidate.plate] = button
                }
                UIView.animate(withDuration: 0.12) { button.frame = candidate.bounds.insetBy(dx: -6, dy: -6) }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { process(allItems, scanner: dataScanner) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { process(allItems, scanner: dataScanner) }
        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) { process(allItems, scanner: dataScanner) }
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let text) = item else { return }
            if let plate = HKCommunityPlate.standardCandidate(text.transcript) { onPlate(plate) }
            else { onHint("未讀到完整車牌，請選下方候選結果，或拍照／手動輸入。") }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError("即時辨識暫時不可用，請拍照辨識或手動輸入。")
        }
    }
}

private struct CommunityPlatePhotoCamera: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { onImage(info[.originalImage] as? UIImage) }
    }
}
private enum CommunityPhotoOCR {
    static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let width = CGFloat(rotated ? image.height : image.width)
        let height = CGFloat(rotated ? image.width : image.height)
        let segments: [CommunityOCRSegment] = (request.results ?? []).prefix(60).flatMap { observation in
            let box = observation.boundingBox
            let rect = CGRect(x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width, height: box.height * height)
            return observation.topCandidates(3).map { CommunityOCRSegment(text: $0.string, bounds: rect) }
        }
        return CommunityPlateOCR.candidates(segments).map(\.plate)
    }
}

private struct CommunityLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ParkingCommunityStore
    @ObservedObject private var push = CommunityPushCoordinator.shared
    @State private var email = ""
    @State private var code = ""
    @State private var requested = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("電郵登入／註冊") {
                    TextField("電郵地址", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: email) { _, _ in requested = false; code = "" }
                    Button(requested ? "重新寄出驗證碼" : "取得驗證碼") {
                        Task { await requestCode() }
                    }.disabled(busy || email.isEmpty)
                    if requested {
                        TextField("6 位驗證碼", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                        Button("登入") { Task { await verify() } }.disabled(busy || code.count != 6)
                        Text("驗證碼 10 分鐘內有效，重新寄出需相隔至少 60 秒。").font(.footnote)
                    }
                }
                Section {
                    Text("只為帳號驗證使用電郵。無需綁定車牌亦可發提醒。請勿與他人分享驗證碼。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                    if busy { ProgressView() }
                }
            }
            .disabled(busy)
            .navigationTitle("泊車互助帳號")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("關閉") { dismiss() } } }
        }
    }
    @MainActor private func requestCode() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await store.api.startLogin(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            requested = true
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func verify() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await store.api.verify(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), code: code)
            await store.refresh(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct CommunityInbox: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: ParkingCommunityStore
    @ObservedObject private var push = CommunityPushCoordinator.shared
    @State private var visible = false
    @State private var login = false
    @State private var notificationThread: String?
    var body: some View {
        List {
            Section {
                Text(push.status + " 向下拉可重新整理；顯示最近 100 條未過期對話，建立後 7 日刪除。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !store.signedIn {
                Button("登入查看提醒") { login = true }.disabled(!store.configured)
            } else if store.threads.isEmpty {
                ContentUnavailableView("暫時沒有提醒", systemImage: "bubble.left.and.bubble.right")
            }
            ForEach(store.threads) { thread in
                NavigationLink {
                    CommunityThreadDetail(store: store, threadID: thread.id, plate: thread.plate)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thread.plate).font(.system(.headline, design: .monospaced))
                        Text(thread.lastMessage?.text ?? "提醒對話").lineLimit(2).font(.subheadline)
                        Text("到期：\(Date(timeIntervalSince1970: thread.expiresAt).formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .navigationTitle("提醒對話")
        .navigationDestination(isPresented: Binding(get: { notificationThread != nil }, set: { if !$0 { notificationThread = nil } })) {
            if let id = notificationThread {
                CommunityThreadDetail(store: store, threadID: id, plate: store.threads.first(where: { $0.id == id })?.plate ?? "提醒對話")
            }
        }
        .task {
            await store.refresh()
            if let id = push.pendingThreadID, store.signedIn {
                notificationThread = id
                push.pendingThreadID = nil
            }
        }
        .onChange(of: push.pendingThreadID) { _, id in
            if let id, store.signedIn { notificationThread = id; push.pendingThreadID = nil }
        }
        .onChange(of: store.signedIn) { _, signedIn in
            if signedIn, let id = push.pendingThreadID { notificationThread = id; push.pendingThreadID = nil }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: visible && scenePhase == .active) {
            guard visible, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                await store.refreshThreads()
            }
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $login) { CommunityLoginView(store: store) }
    }
}

private struct CommunityThreadDetail: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: ParkingCommunityStore
    @ObservedObject private var push = CommunityPushCoordinator.shared
    let threadID: String
    let plate: String
    @State private var refreshGeneration = UUID()
    @State private var visible = false
    @State private var messages: [CommunityMessage] = []
    @State private var text = ""
    @State private var key = UUID()
    @State private var busy = false
    @State private var status: String?
    @State private var blockedUser: String?
    var body: some View {
        List {
            Section {
                Text("所有綁定者共用對話；顯示最近 200 則訊息。" + push.status)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("訊息") {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.text)
                        Text(Date(timeIntervalSince1970: message.createdAt).formatted())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("舉報不當訊息", role: .destructive) { Task { await report() } }
                        Button("封鎖此發送者", role: .destructive) { blockedUser = message.authorId }
                    }
                }
            }
        }
        .navigationTitle(plate)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["感謝師兄", "唔該", "多謝提醒"], id: \.self) { template in
                            Button(template) { text = template; status = nil }
                                .buttonStyle(.bordered)
                                .disabled(busy)
                        }
                    }
                }
                HStack(alignment: .bottom) {
                    TextField("輸入回覆，或揀上面快捷句", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: text) { _, value in text = String(value.prefix(200)); key = UUID() }
                        .disabled(busy)
                    Button { Task { await reply() } } label: {
                        if busy { ProgressView() }
                        else { Label("發送回覆", systemImage: "paperplane.fill") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("community.sendReply")
                }
                if let status { Text(status).font(.footnote).accessibilityIdentifier("community.replyStatus") }
                else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("已填入回覆，撳「發送回覆」先會送出。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding().background(.regularMaterial)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: visible && scenePhase == .active) {
            guard visible, scenePhase == .active else { return }
            while !Task.isCancelled {
                if !busy { await refresh() }
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .refreshable { await refresh() }
        .confirmationDialog("封鎖後不會再互相接收提醒。", isPresented: Binding(get: { blockedUser != nil }, set: { if !$0 { blockedUser = nil } }), titleVisibility: .visible) {
            Button("封鎖", role: .destructive) { if let user = blockedUser { Task { await block(user) } } }
        }
    }
    @MainActor private func refresh() async {
        let generation = UUID()
        refreshGeneration = generation
        do {
            let fetched = try await store.api.messages(threadID)
            guard !Task.isCancelled, refreshGeneration == generation else { return }
            messages = fetched
        }
        catch {
            guard !Task.isCancelled, refreshGeneration == generation else { return }
            status = error.localizedDescription; store.handle(error)
        }
    }
    @MainActor private func reply() async {
        guard !busy else { return }
        let outgoing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outgoing.isEmpty else { return }
        refreshGeneration = UUID()
        busy = true; status = nil
        defer { busy = false }
        do {
            try await store.api.reply(thread: threadID, text: outgoing, key: key)
            text = ""; key = UUID(); await refresh()
            status = "回覆已發送。"
        } catch { status = error.localizedDescription; store.handle(error) }
    }
    @MainActor private func report() async {
        do { try await store.api.report(thread: threadID); status = "舉報已記錄，等待處理。" }
        catch { status = error.localizedDescription }
    }
    @MainActor private func block(_ user: String) async {
        do { try await store.api.block(user: user); blockedUser = nil; messages = []; status = "已封鎖。"; await store.refresh() }
        catch { status = error.localizedDescription }
    }
}
