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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var destinationManager = DestinationManager.shared
    @StateObject private var locationManager = LocationManager()
    @StateObject private var parkingFloorStore = ParkingFloorStore.shared
    @State private var bootstrapped = false
    @State private var showSplash = true
    @State private var splashDone = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(destinationManager)
                    .environmentObject(locationManager)
                    .environmentObject(parkingFloorStore)
                    .blur(radius: splashDone ? 0 : 30)
                    .opacity(splashDone ? 1 : 0.6)
                    .animation(.easeOut(duration: 1.5), value: splashDone)
                    .onAppear {
                        guard !bootstrapped else { return }
                        bootstrapped = true

                        // 套用語言設定
                        LanguageManager.shared.applyLanguage()

                        // 通知權限 + 前台 delegate
                        let center = UNUserNotificationCenter.current()
                        center.delegate = appDelegate
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

                        Task { @MainActor in
                            // 啟動音效（延遲確保音頻系統就緒）
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
            }
        }
    }
}
