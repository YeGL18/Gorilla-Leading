import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .all
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
                    Task { @MainActor in
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
