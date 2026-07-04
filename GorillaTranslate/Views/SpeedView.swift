import SwiftUI

struct SpeedView: View {
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DotMatrixWebView(speed: Binding(
                get: { locationManager.speed },
                set: { _ in }
            ))
            .ignoresSafeArea(edges: .all)

            VStack(spacing: 4) {
                Spacer()
                Text("\(Int(locationManager.speed))")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: Int(locationManager.speed))
                Text("km/h")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .statusBarHidden(true)
    }
}
