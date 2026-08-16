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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(destinationManager)
                .environmentObject(locationManager)
                .environmentObject(parkingFloorStore)
                .onAppear {
                    guard !bootstrapped else { return }
                    bootstrapped = true

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
        }
    }
}
