import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // A visit can relaunch us while locked, before SwiftUI creates any foreground view.
        if !UIApplication.shared.isProtectedDataAvailable {
            // Locked background launches must still receive and queue native visits.
            _ = LocationManager.shared
        } else {
            _ = prepareAppStoresIfAvailable()
        }
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        prepareAppStoresIfAvailable()
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .all
    }

    /// App 在前台時都顯示通知 banner + 播放音效
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// Foreground UI and background location launches share the same protected-data gate.
@MainActor
private func prepareAppStoresIfAvailable() -> Bool {
    guard UIApplication.shared.isProtectedDataAvailable else { return false }
    LanguageManager.refresh()
    do { try BackupController.transaction.recoverIfNeeded() }
    catch { return false }
    // Never interpret inaccessible preferences as a fresh installation, or start
    // location callbacks that could save empty stores before hydration finishes.
    LanguageManager.migrateLegacyOverride()
    let defaults = UserDefaults.standard
    let onboardingKey = "hasCompletedLeadingOnboarding"
    let bundleID = Bundle.main.bundleIdentifier ?? "com.gorilla.translation"
    let persistedDomain = defaults.persistentDomain(forName: bundleID) ?? [:]
    if persistedDomain[onboardingKey] == nil {
        defaults.set(!persistedDomain.isEmpty, forKey: onboardingKey)
    }
    DestinationManager.shared.prepare()
    ParkingFloorStore.shared.prepare()
    TripPredictor.shared.prepare()
    LocationManager.shared.prepare()
    return true
}

@main
struct GorillaTranslateApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "capsuleAnimationStyle": 1,
            "mapTrackingAnimation": 1,
            "kalmanSmoothingEnabled": true,
            "sfxAccelerationEnabled": false,
            "orbCapsule": false,
            "orbExpanded": false,
            "orbParkingMemory": false,
            "orbCanvasDitherEnabled": true
        ])
    }

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ProtectedStartupView(appDelegate: appDelegate)
        }
    }
}

private struct ProtectedStartupView: View {
    let appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var ready = false
    @State private var recoveryFailed = false
    @State private var languageCode = "en"

    var body: some View {
        Group {
            if ready {
                GorillaRootView(appDelegate: appDelegate)
                    .environment(\.locale, Locale(identifier: languageCode))
                    .id(languageCode)
            } else {
                if recoveryFailed {
                    ContentUnavailableView {
                        Label("Restore Recovery", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Your records have not been opened. Retry recovery before using the app.")
                    } actions: { Button("Retry") { prepareIfAvailable() } }
                } else { Color(uiColor: .systemBackground).ignoresSafeArea() }
            }
        }
        .onAppear(perform: prepareIfAvailable)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            prepareIfAvailable()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { prepareIfAvailable() }
        }
    }

    private func prepareIfAvailable() {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        if ready {
            LanguageManager.refresh()
            languageCode = LanguageManager.languageCode
            return
        }
        guard prepareAppStoresIfAvailable() else { recoveryFailed = true; return }
        languageCode = LanguageManager.languageCode
        ready = true
    }
}

private struct GorillaRootView: View {
    let appDelegate: AppDelegate
    @StateObject private var destinationManager = DestinationManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var parkingFloorStore = ParkingFloorStore.shared
    @ObservedObject private var backupController = BackupController.shared
    @State private var bootstrapped = false
    @State private var showSplash = true
    @State private var splashDone = false
    @State private var forcedOnboardingDismissed = false
    @AppStorage("hasCompletedLeadingOnboarding") private var hasCompletedLeadingOnboarding = false

    private var forceOnboardingForDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-onboarding")
#else
        false
#endif
    }

    private var shouldShowOnboarding: Bool {
        (!hasCompletedLeadingOnboarding || forceOnboardingForDebug) && !forcedOnboardingDismissed
    }

    private var debugOnboardingPage: Int {
#if DEBUG
        let prefix = "--onboarding-page="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return 0
        }
        return Int(argument.dropFirst(prefix.count)) ?? 0
#else
        return 0
#endif
    }

    var body: some View {
            ZStack {
                Group {
                    if backupController.recoveryRequired {
                        ContentUnavailableView {
                            Label("Restore Recovery", systemImage: "externaldrive.badge.exclamationmark")
                        } description: {
                            Text("Your records have not been opened. Retry recovery before using the app.")
                        } actions: { Button("Retry") { backupController.retryRecovery() } }
                    } else if backupController.restoring {
                        ProgressView("Restoring Backup")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !shouldShowOnboarding {
                        ContentView()
                            .id(backupController.generation)
                            .environmentObject(destinationManager)
                            .environmentObject(locationManager)
                            .environmentObject(parkingFloorStore)
                            .transition(.opacity)
                    } else {
                        Color(uiColor: .systemGroupedBackground)
                            .ignoresSafeArea()
                    }
                }
                    .blur(radius: splashDone ? 0 : 30)
                    .opacity(splashDone ? 1 : 0.6)
                    .animation(.easeOut(duration: 1.5), value: splashDone)

                LaunchAnimationView(
                    onFadeOutStart: {
                        // 大猩猩開始淡出時，背景模糊同步漸降到 0
                        splashDone = true
                    },
                    onFinish: {
                        // 圖標淡出完成 → splash 漸隱
                        withAnimation(.easeOut(duration: 0.8)) {
                            showSplash = false
                        }
                    }
                )
                .opacity(showSplash ? 1 : 0)
                .zIndex(1)
                .allowsHitTesting(showSplash)

                if !showSplash && shouldShowOnboarding {
                    GorillaOnboardingView(initialPage: debugOnboardingPage) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            hasCompletedLeadingOnboarding = true
                            forcedOnboardingDismissed = true
                        }
                    }
                    .environmentObject(locationManager)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .alert("Backup & Restore", isPresented: Binding(get: { backupController.restoreMessage != nil },
                set: { if !$0 { backupController.restoreMessage = nil } })) {
                    Button("確定", role: .cancel) { backupController.restoreMessage = nil }
                } message: { Text(backupController.restoreMessage ?? "") }
            .onAppear {
                guard !bootstrapped else { return }
                bootstrapped = true

                let launchAnimEnabled = UserDefaults.standard.object(forKey: "launchAnimationEnabled") as? Bool ?? true
                if !launchAnimEnabled {
                    splashDone = true
                    showSplash = false
                }

                let center = UNUserNotificationCenter.current()
                center.delegate = appDelegate

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    SFXPlayer().playLaunchSound()
                }
            }
    }
}
