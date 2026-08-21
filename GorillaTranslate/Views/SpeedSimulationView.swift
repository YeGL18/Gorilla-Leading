import SwiftUI

struct SpeedSimulationView: View {
    @Binding var speed: Double
    let triggerSpeed: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.8))

            VStack(spacing: 8) {
                Text(String(localized: "SU7 Ultra 时速模拟"))
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(Int(speed))")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundColor(.orange)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: Int(speed))

                Text("km/h")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                ProgressView(value: min(speed / triggerSpeed, 1.0))
                    .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                    .padding(.horizontal)
                    .scaleEffect(x: 1, y: 2.5, anchor: .center)
            }
        }
    }
}
