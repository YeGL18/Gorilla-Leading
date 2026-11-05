import SwiftUI

struct AirportDropOffGuide: View {
    var maximumHeight: CGFloat = 520
    var maximumWidth: CGFloat = 420
    var onSearch: (AirportDropOffCatalog.Airline) -> Void = { _ in }
    var routeDistanceMeters: Double?
    var routeMessage: String?
    var waitingForLocation: Bool = false
    enum Stage { case button, input, result }
    @Binding var stage: Stage
    private let catalog = AirportDropOffCatalog.bundled
    @State private var flight = ""
    @State private var searchedFlight = ""
    @State private var page: Int? = 0
    @State private var scrolling = false
    @State private var showPageDots = false
    @State private var dotsTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    @GestureState private var touching = false
    @AppStorage("capsuleDarkGlassEnabled") private var darkGlass = true
    @Environment(\.colorScheme) private var colorScheme

    private var matches: [AirportDropOffCatalog.Airline] { catalog.lookup(searchedFlight) }
    private var validInput: Bool { AirportDropOffCatalog.airlineCode(from: flight) != nil }
    private var cardHeight: CGFloat { min(340, max(180, maximumHeight - 48)) }
    private var contentWidth: CGFloat { min(420, maximumWidth) }
    private var interacting: Bool { touching || scrolling }
    private var backingScale: CGFloat { interacting ? 1.045 : 1 }
    private var entryAnimation: Animation { .spring(response: 0.48, dampingFraction: 0.86) }
    private var airlineColor: Color { Color(hex: matches.first?.brandColorHex ?? "12D2C2") ?? .cyan }

    var body: some View {
        ZStack {
            if stage == .result {
                resultStack
                    .transition(.scale(scale: 0.93).combined(with: .opacity))
            } else {
                entryCapsule
                    .offset(y: 44)
                    .transition(.opacity)
            }
        }
        .frame(width: contentWidth)
        .foregroundStyle(.primary)
        .tint(darkGlass || colorScheme == .dark ? .white : .accentColor)
        .environment(\.colorScheme, darkGlass ? .dark : colorScheme)
        .padding(24)
        .overlay(alignment: .bottom) {
            if waitingForLocation && stage != .result {
                Text("正在取得目前位置…")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: .capsule)
                    .offset(y: 84)
                    .allowsHitTesting(false)
            }
        }
        .onDisappear { focused = false }
        .onChange(of: stage) { _, stage in
            if stage != .input { focused = false }
            if stage == .button { page = 0 }
        }
        .task(id: stage) {
            guard stage == .input else { return }
            // Keep keyboard presentation out of the capsule's initial layout transaction.
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            focused = true
        }
    }

    // One persistent shell changes width. Replacing two differently sized glass
    // views only matched the material; the input itself previously jumped in.
    private var entryCapsule: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 24, weight: .semibold))
            ZStack(alignment: .leading) {
                if stage == .input {
                    TextField("", text: $flight)
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .keyboardType(.asciiCapable).submitLabel(.search).focused($focused)
                        .onSubmit(search).accessibilityLabel(Text("航班編號"))
                        .accessibilityIdentifier("airportFlightNumber")
                        .transition(.opacity)
                } else {
                    Text("輸入航班").font(.system(size: 25, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.65).transition(.opacity)
                }
            }
            if stage == .input {
                HStack(spacing: 4) {
                    Button(action: search) {
                        Image(systemName: "magnifyingglass").font(.title3.weight(.semibold))
                            .frame(width: 44, height: 48)
                    }
                    .disabled(!validInput).accessibilityLabel(Text("搜尋"))
                    Button { collapse() } label: {
                        Image(systemName: "xmark").font(.headline).frame(width: 44, height: 48)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text("關閉"))
                }.fixedSize().transition(.opacity)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .frame(width: min(contentWidth, stage == .input ? 390 : 252), height: 84)
        .clipShape(.capsule)
        .background {
            Capsule().fill(.clear).glassEffect(.regular.interactive(), in: .capsule)
                .allowsHitTesting(false)
        }
        .overlay {
            if stage == .button {
                Button {
                    withAnimation(entryAnimation) { stage = .input }
                } label: {
                    Color.clear.contentShape(.capsule)
                }
                .buttonStyle(.plain).accessibilityLabel(Text("輸入航班"))
                .allowsHitTesting(stage == .button)
                .transition(.identity)
            }
        }
        .animation(entryAnimation, value: stage)
    }

    private var resultStack: some View {
        ZStack {
            ZStack {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(0..<2) { index in
                            card(index)
                                .frame(maxWidth: .infinity)
                                .frame(height: cardHeight, alignment: .topLeading)
                                .background {
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill((index == 0 ? airlineColor : Color.indigo).opacity(darkGlass ? 0.14 : 0.1))
                                }
                                .overlay { glowBorder(index == 0 ? airlineColor : .indigo) }
                                .clipShape(.rect(cornerRadius: 28))
                                .id(index)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .onScrollPhaseChange { _, phase in
                    scrolling = phase != .idle
                    revealPageDots()
                }
                .frame(height: cardHeight)
                .clipShape(.rect(cornerRadius: 28))
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .updating($touching) { _, value, _ in value = true })
            }
            .frame(height: cardHeight)
            .background {
                // Isolate the backing glass from the pager's foreground content.
                // A shared GlassEffectContainer can composite its glass over sibling cards.
                RoundedRectangle(cornerRadius: 30)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
                    .scaleEffect(backingScale)
                    .allowsHitTesting(false)
            }
            .offset(y: interacting ? -5 : 0)
            .overlay(alignment: .trailing) {
                VStack(spacing: 6) {
                    ForEach(0..<2) { index in
                        Circle().fill(.primary).frame(width: 6, height: 6)
                            .opacity(page == index ? 0.95 : 0.25)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 12)
                .background {
                    Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                }
                // Reserve the backing's entire outward travel before adding lag,
                // so a delayed indicator can never be caught by the growing edge.
                .offset(x: 24 + 12 + contentWidth * 0.045 / 2 + contentWidth * (backingScale - 1) / 2,
                        y: interacting ? -5 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 1).delay(0.06), value: interacting)
                .opacity(showPageDots ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: interacting)
            .animation(.easeInOut(duration: 0.22), value: showPageDots)
            .onChange(of: touching) { _, _ in revealPageDots() }
            Button { collapse() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .accessibilityLabel(Text("關閉"))
            .offset(y: cardHeight / 2 + 40)
        }
        .frame(maxWidth: 420)
        .onDisappear { dotsTask?.cancel() }
    }

    private func glowBorder(_ tint: Color) -> some View {
        let reflection = AngularGradient(stops: [
            .init(color: .white.opacity(0.95), location: 0),
            .init(color: tint.opacity(0.35), location: 0.18),
            .init(color: .white.opacity(0.18), location: 0.37),
            .init(color: .white.opacity(0.95), location: 0.53),
            .init(color: tint.opacity(0.8), location: 0.68),
            .init(color: .white.opacity(0.25), location: 0.84),
            .init(color: .white, location: 1)
        ], center: .center, startAngle: .degrees(-120), endAngle: .degrees(240))
        return ZStack {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(reflection, lineWidth: 1.1)
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(reflection, lineWidth: 3)
                .blur(radius: 2.5)
                .opacity(0.45)
                .mask(RoundedRectangle(cornerRadius: 28).strokeBorder(lineWidth: 6))
        }.allowsHitTesting(false)
    }

    private func revealPageDots() {
        dotsTask?.cancel()
        showPageDots = true
        guard !touching, !scrolling else { return }
        dotsTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            withAnimation(.easeOut(duration: 0.25)) { showPageDots = false }
        }
    }

    private func card(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(index == 0 ? "機場落客指南" : "詳細說明")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if index == 0 {
                if let airline = matches.first {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(airline.name(language: LanguageManager.languageCode)).font(.title2.bold())
                        if (LanguageManager.languageCode.hasPrefix("zh") || LanguageManager.languageCode.hasPrefix("yue")) {
                            Text(airline.nameEnglish).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(airline.terminal).font(.system(size: 38, weight: .bold, design: .rounded))
                        Spacer()
                        if !airline.dropOffZones.isEmpty {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Zone " + airline.dropOffZones.map(String.init).joined(separator: " / "))
                                    .font(.title2.bold()).foregroundStyle(.orange)
                                Text("落客區大約位置").font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("暫未提供落客區").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("值機櫃位", value: airline.checkInAisles.joined(separator: " / "))
                        .font(.headline)
                    if let distance = routeDistanceMeters.flatMap(AirportDropOffCatalog.formattedDistance) {
                        Text(distance).font(.title3.monospacedDigit().bold())
                    } else if let routeMessage {
                        Text(routeMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("未有這間航司的落客資料，請查看機場或航司指示。")
                        .font(.headline).padding(.vertical, 16)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("按航司代碼提供一般指引，並非航班即時資料；請以機場及航司當日安排為準。")
                        if matches.first?.dropOffZones.isEmpty == true {
                            Text("原表未涵蓋此櫃位的落客區配對。")
                        }
                        Text("落客區按櫃位配對提供；地圖標點按落客道路及區域排列估算，代表大約位置。請以現場標誌為準。")
                        if let updated = catalog.updatedAt { Text(updated).font(.caption).foregroundStyle(.secondary) }
                        Link("香港機場官方資料", destination: URL(string: (LanguageManager.languageCode.hasPrefix("zh") || LanguageManager.languageCode.hasPrefix("yue"))
                            ? "https://www.hongkongairport.com/tc/flights/airlines-information/airlines.page"
                            : "https://www.hongkongairport.com/en/flights/airlines-information/airlines.page")!)
                        Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    }.font(.subheadline)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(20)
    }

    private func collapse() {
        focused = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { stage = .button; page = 0 }
    }
    private func search() {
        guard validInput else { return }
        searchedFlight = flight
        if let airline = catalog.lookup(flight).first { onSearch(airline) }
        focused = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { page = 0; stage = .result }
    }
}
