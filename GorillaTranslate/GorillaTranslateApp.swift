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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(destinationManager)
                .environmentObject(locationManager)
                .environmentObject(parkingFloorStore)
        }
    }
}
