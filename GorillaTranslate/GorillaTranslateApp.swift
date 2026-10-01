import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
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

@main
struct GorillaTranslateApp: App {
    init() {
        LanguageManager.migrateLegacyOverride()
        let defaults = UserDefaults.standard
        let onboardingKey = "hasCompletedLeadingOnboarding"
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gorilla.translation"
        let persistedDomain = defaults.persistentDomain(forName: bundleID) ?? [:]

        // Existing installs already contain app preferences or saved state. Mark only
        // those installs as complete so the new tour remains exclusive to fresh installs.
        if persistedDomain[onboardingKey] == nil {
            defaults.set(!persistedDomain.isEmpty, forKey: onboardingKey)
        }

        UserDefaults.standard.register(defaults: [
            "capsuleAnimationStyle": 1,
            "mapTrackingAnimation": 1,
            "kalmanSmoothingEnabled": true,
            "sfxAccelerationEnabled": false,
            "orbCapsule": false,
            "orbExpanded": false,
            "orbParkingMemory": false
        ])
    }

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var destinationManager = DestinationManager.shared
    @StateObject private var locationManager = LocationManager()
    @StateObject private var parkingFloorStore = ParkingFloorStore.shared
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

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if !shouldShowOnboarding {
                        ContentView()
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
            .onAppear {
                guard !bootstrapped else { return }
                bootstrapped = true

                AMapConfig.shared.configure()

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
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    parkingFloorStore.prepare()
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    destinationManager.prepare()
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    TripPredictor.shared.prepare()
                }
            }
        }
    }
}
