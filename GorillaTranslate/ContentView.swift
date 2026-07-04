import SwiftUI
import FoundationModels
import Speech
import Accelerate
import MapKit

struct ContentView: View {
    @StateObject private var viewModel = TranslationViewModel()
    @StateObject private var historyManager = HistoryManager()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var animationClock = AnimationClock()
    @StateObject private var locationManager = LocationManager()
    
    @State private var showingLanguagePicker = false
    @State private var selectingSource = true
    @State private var isRecording = false
    @State private var selectedTab: Int = 1
    @State private var hasPlayedEntrance = false
    @State private var isVoiceRecording = false
    @State private var revealedCount = 0
    @State private var sparklePhase = false
    @FocusState private var isInputFocused: Bool
    @State private var isKeyboardVisible = false
    @State private var showMap = false
    @State private var mapRegion: MKCoordinateRegion?
    @State private var hasShownMapFirstTime = false
    @State private var firstMapFlyTrigger = 0
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("outputAnimationStyle") private var outputAnimationStyle: Int = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .dark
        case 2: return .light
        default: return nil
        }
    }

    private var effectiveColorScheme: ColorScheme {
        switch appearanceMode {
        case 1: return .dark
        case 2: return .light
        default:
            let phase = UITraitCollection.current.userInterfaceStyle
            return phase == .dark ? .dark : .light
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SpeedView()
                .environment(\.colorScheme, effectiveColorScheme)
                .tabItem {
                    Label("Speed", systemImage: "speedometer")
                }
                .tag(0)
            
            NavigationStack {
                homeContent
                    .animation(.easeInOut(duration: 0.25), value: isKeyboardVisible)
                    .environment(\.colorScheme, effectiveColorScheme)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isKeyboardVisible = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isKeyboardVisible = false
                        }
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(1)
            .onAppear {
                animationClock.start()
                guard !hasPlayedEntrance else { return }
                hasPlayedEntrance = true
                triggerEntranceEffect()
            }
            
            SettingsView()
                .environment(\.colorScheme, effectiveColorScheme)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        .preferredColorScheme(resolvedColorScheme)
    }
    
    // MARK: - Home Content
    var homeContent: some View {
        ZStack {
            // 地图页：一直存在，不销毁
            VignetteMapView(savedRegion: $mapRegion, firstFlyTrigger: $firstMapFlyTrigger)
                .ignoresSafeArea()

            // 光球页：在地图页上方，切换时只是隐藏/显示
            AnimatedBackground(clock: animationClock, colorSchemeIndex: colorSchemeIndex, isVoiceRecording: isVoiceRecording)
                .ignoresSafeArea()
                .opacity(showMap ? 0 : 1)  // 切换时只是改变透明度，不销毁视图

            // 上层 UI：标题、按钮等，永远存在
            VStack(spacing: 16) {
                // Header
                HStack(alignment: .center) {
                    Text("Gorilla Leading")
                        .font(.largeTitle.bold())
                    Spacer()
                    gpsStatusBadge
                }
                .padding(.horizontal, 16)
                .padding(.top, 30)
                .frame(height: 44)

                Spacer()

                // Left Side Buttons
                HStack {
                    VStack(spacing: 10) {
                        Button(action: {}) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showMap.toggle()
                            }
                        }) {
                            Image(systemName: showMap ? "map.fill" : "map")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 60)
                    Spacer()
                }
            }

            // Address bar：放在底部，TabView 导航栏上方，永远显示
            if !locationManager.currentAddress.isEmpty {
                VStack {
                    Spacer()
                    ZStack {
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            let t = animationClock.elapsed

                            ZStack {
                                Color.black.opacity(0.4) // 黑色背景 40% 透明度
                                
                                Circle()
                                    .fill(Color(hex: "BEBC3F").opacity(0.3))
                                    .blur(radius: 20)
                                    .frame(width: 200, height: 200)
                                    .offset(
                                        x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.4 - 100,
                                        y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.4 - 100
                                    )
                                Circle()
                                    .fill(Color(hex: "5CAEB7").opacity(0.3))
                                    .blur(radius: 20)
                                    .frame(width: 220, height: 220)
                                    .offset(
                                        x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.35 - 110,
                                        y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.35 - 110
                                    )
                                Circle()
                                    .fill(Color(hex: "0098FF").opacity(0.3))
                                    .blur(radius: 20)
                                    .frame(width: 180, height: 180)
                                    .offset(
                                        x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.38 - 90,
                                        y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.38 - 90
                                    )
                            }
                        }
                        .clipShape(.rect(cornerRadius: 22))

                        Text(locationManager.currentAddress)
                            .font(.body.bold())
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .frame(maxWidth: 270)
                    .padding(.bottom, 8)
                }
            }
        }
        .onChange(of: showMap) { _, newValue in
            if newValue && !hasShownMapFirstTime {
                hasShownMapFirstTime = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    firstMapFlyTrigger += 1
                }
            }
        }
        .sheet(isPresented: $showingLanguagePicker) {
            LanguagePickerView(
                languages: Language.allCases,
                selectedLanguage: selectingSource ? viewModel.sourceLanguage : viewModel.targetLanguage,
                onSelect: { language in
                    if selectingSource {
                        viewModel.sourceLanguage = language
                    } else {
                        viewModel.targetLanguage = language
                    }
                    showingLanguagePicker = false
                },
                isPresented: $showingLanguagePicker
            )
        }
    }
    
    // MARK: - GPS Status Badge
    private var gpsStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 8, height: 8)
                .phaseAnimator([false, true]) { content, phase in
                    content
                        .scaleEffect(phase ? 0.9 : 0.8)
                } animation: { _ in
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                }
            
            ZStack {
                Text("VADY").hidden()
                    .font(.system(size: 12, weight: .medium))
                Text(gpsLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: locationManager.gpsQuality)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var gpsColor: Color {
        switch locationManager.gpsQuality {
        case .good: return .green
        case .poor: return .yellow
        case .bad: return .red
        case .unknown: return .gray
        }
    }

    private var gpsLabel: String {
        switch locationManager.gpsQuality {
        case .good: return "GPS Ready"
        case .poor: return "GPS Weak"
        case .bad: return "GPS Lost"
        case .unknown: return "GPS Waiting"
        }
    }
    
    // MARK: - Entrance Effect
    private func triggerEntranceEffect() {
        let startTime = Date()
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                let duration: Double = 3.0
                if t < duration {
                    let u = t / duration
                    animationClock.speedMultiplier = 1 + (5.0 - 1) * pow(1 - u, 2)
                } else {
                    animationClock.speedMultiplier = 1.0
                    timer.invalidate()
                }
            }
        }
    }
    
    // MARK: - Translate + Save
    func translate() {
        if isRecording {
            speechRecognizer.stopRecording()
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6)) {
                isRecording = false
                isVoiceRecording = false
            }
            triggerVoiceStopEffect()
            if !speechRecognizer.transcribedText.isEmpty {
                viewModel.inputText = speechRecognizer.transcribedText
            }
        }
        let input = viewModel.inputText
        isInputFocused = false
        viewModel.translate()
        triggerTranslateStartEffect()
        
        Task {
            for await _ in viewModel.$isTranslating.values {
                if !viewModel.isTranslating {
                    triggerTranslateStopEffect()
                    guard !viewModel.outputText.isEmpty else { break }
                    historyManager.add(
                        inputText: input,
                        outputText: viewModel.outputText,
                        sourceLanguage: viewModel.sourceLanguage.displayName,
                        targetLanguage: viewModel.targetLanguage.displayName
                    )
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    break
                }
            }
        }
    }
    
    // MARK: - Speed Effects
    @State private var translateSpeedTimer: Timer?
    
    private func triggerTranslateStartEffect() {
        translateSpeedTimer?.invalidate()
        voiceSpeedTimer?.invalidate()
        let startTime = Date()
        translateSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 1.4 {
                    let u = t / 1.4
                    animationClock.speedMultiplier = 1 + (4.0 - 1) * (1 - pow(1 - u, 2))
                } else {
                    animationClock.speedMultiplier = 4.0
                    timer.invalidate()
                }
            }
        }
    }
    
    private func triggerTranslateStopEffect() {
        translateSpeedTimer?.invalidate()
        let startSpeed = animationClock.speedMultiplier
        let startTime = Date()
        translateSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 2.0 {
                    let u = t / 2.0
                    animationClock.speedMultiplier = startSpeed + (1.0 - startSpeed) * pow(u, 1.5)
                } else {
                    animationClock.speedMultiplier = 1.0
                    timer.invalidate()
                }
            }
        }
    }
    
    @State private var voiceSpeedTimer: Timer?

    private func triggerVoiceStartEffect() {
        voiceSpeedTimer?.invalidate()
        translateSpeedTimer?.invalidate()
        let startTime = Date()
        voiceSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 0.8 {
                    let u = t / 0.8
                    animationClock.speedMultiplier = 1 + (0.5 - 1) * pow(u, 1.5)
                } else if self.isRecording {
                    let level = self.speechRecognizer.audioLevel
                    animationClock.speedMultiplier = 0.5 + level * 7.5
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func triggerVoiceStopEffect() {
        voiceSpeedTimer?.invalidate()
        let startSpeed = animationClock.speedMultiplier
        let startTime = Date()
        voiceSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 2.0 {
                    let u = t / 2.0
                    animationClock.speedMultiplier = startSpeed + (1.0 - startSpeed) * pow(u, 1.5)
                } else {
                    animationClock.speedMultiplier = 1.0
                    timer.invalidate()
                }
            }
        }
    }
    
    // MARK: - Speech Recognition
    func toggleRecording() {
        if isRecording {
            speechRecognizer.stopRecording()
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6)) {
                isRecording = false
                isVoiceRecording = false
            }
            triggerVoiceStopEffect()
            if !speechRecognizer.transcribedText.isEmpty {
                viewModel.inputText = speechRecognizer.transcribedText
            }
        } else {
            isInputFocused = false
            speechRecognizer.startRecording(locale: viewModel.sourceLanguage.speechLocale) { text in
                viewModel.inputText = text
            }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6)) {
                isRecording = true
                isVoiceRecording = true
            }
            triggerVoiceStartEffect()
        }
    }
}

// MARK: - Speech Recognizer
class SpeechRecognizer: ObservableObject {
    @Published var transcribedText: String = ""
    @Published var audioLevel: Double = 0.0
    private var onPartialResult: ((String) -> Void)?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var recognitionGeneration = 0
    
    func startRecording(locale: Locale = Locale(identifier: "en-US"), onUpdate: @escaping (String) -> Void) {
        self.onPartialResult = onUpdate
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.startActualRecording(locale: locale)
                default:
                    print("Speech recognition not authorized")
                }
            }
        }
    }
    
    private func startActualRecording(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }
        
        self.speechRecognizer = recognizer
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        recognitionGeneration += 1
        let gen = recognitionGeneration
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            guard gen == self.recognitionGeneration else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = text
                    self.onPartialResult?(text)
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.stopRecording()
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            
            if let channelData = buffer.floatChannelData {
                let frames = UInt(buffer.frameLength)
                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, frames)
                let amplified = Double(min(rms * 50, 1.0))
                let smoothed = self.audioLevel * 0.6 + amplified * 0.4
                DispatchQueue.main.async {
                    self.audioLevel = smoothed
                }
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        onPartialResult = nil
    }
    
    func restartRecording(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            print("Speech recognizer not available for locale: \(locale)")
            return
        }
        
        recognitionGeneration += 1
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        recognitionRequest = newRequest
        
        let gen = recognitionGeneration
        recognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self = self else { return }
            guard gen == self.recognitionGeneration else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = text
                    self.onPartialResult?(text)
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.stopRecording()
            }
        }
        
        self.speechRecognizer = recognizer
    }
}

// MARK: - Custom TextView
struct EnterDismissTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        let isDark = context.environment.colorScheme == .dark
        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = isDark ? .white.withAlphaComponent(0.3) : .black.withAlphaComponent(0.3)
        } else {
            textView.textColor = isDark ? .white : .black
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let isDark = context.environment.colorScheme == .dark
        if !context.coordinator.isEditing {
            if text.isEmpty {
                uiView.text = placeholder
                uiView.textColor = isDark ? .white.withAlphaComponent(0.3) : .black.withAlphaComponent(0.3)
            } else {
                uiView.text = text
                uiView.textColor = isDark ? .white : .black
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: EnterDismissTextView
        var isEditing = false
        
        init(_ parent: EnterDismissTextView) {
            self.parent = parent
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            let isDark = textView.traitCollection.userInterfaceStyle == .dark
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = isDark ? .white : .black
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            let isDark = textView.traitCollection.userInterfaceStyle == .dark
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = isDark ? .white.withAlphaComponent(0.3) : .black.withAlphaComponent(0.3)
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                textView.resignFirstResponder()
                return false
            }
            return true
        }
    }
}

#Preview {
    ContentView()
}