import SwiftUI

struct SettingsView: View {
    @State private var simSpeed: Double = 0
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            List {
                // Appearance Section
                Section {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag(0)
                        Text("Dark").tag(1)
                        Text("Light").tag(2)
                    }

                    Picker("Color Scheme", selection: $colorSchemeIndex) {
                        Text("Default").tag(0)
                        Text("27").tag(1)
                    }
                } header: {
                    Label("Appearance", systemImage: "paintpalette")
                }

                // Visit Events Section
                Section {
                    if locationManager.visits.isEmpty {
                        Text("No visits recorded yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(locationManager.visits) { visit in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: transportIcon(visit.transportType))
                                        .foregroundStyle(.orange)
                                    Text(visit.transportType)
                                        .font(.headline)
                                    Spacer()
                                    Text(visit.duration)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text(visit.address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(visit.arrivalDate, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    if let departure = visit.departureDate {
                                        Text(" → ")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        Text(departure, style: .time)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Label("Visit Events", systemImage: "mappin.and.ellipse")
                }

                // Speed Simulation Section
                Section {
                    DotMatrixView(speed: $simSpeed)
                        .frame(minHeight: 400)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Label("Speed Simulation", systemImage: "speedometer")
                }
            }
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 36)
            .listRowSpacing(0)
            .navigationTitle("Settings")
        }
    }

    private func transportIcon(_ type: String) -> String {
        switch type {
        case "Walking": return "figure.walk"
        case "Driving": return "car.fill"
        case "Train": return "tram.fill"
        case "Airplane": return "airplane"
        case "Cycling": return "bicycle"
        default: return "mappin.circle.fill"
        }
    }
}

#Preview {
    SettingsView()
}
