import WidgetKit
import SwiftUI

struct ParkingTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> ParkingTimerEntry {
        ParkingTimerEntry(date: Date(), entryTime: Date().addingTimeInterval(-3600), duration: 3600, location: "台北101")
    }

    func getSnapshot(in context: Context, completion: @escaping (ParkingTimerEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ParkingTimerEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: entry.date)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> ParkingTimerEntry {
        let defaults = UserDefaults(suiteName: "group.com.gorilla.translate") ?? .standard
        let departed = defaults.bool(forKey: "hasDeparted")

        guard !departed,
              let savedTime = defaults.object(forKey: "parkingStartTime") as? Date else {
            return ParkingTimerEntry(date: Date(), entryTime: nil, duration: 0, location: nil)
        }

        let duration = Date().timeIntervalSince(savedTime)
        let location = defaults.string(forKey: "parkingEntryLocation")
        return ParkingTimerEntry(date: Date(), entryTime: savedTime, duration: duration, location: location)
    }
}

struct ParkingTimerEntry: TimelineEntry {
    let date: Date
    let entryTime: Date?
    let duration: TimeInterval
    let location: String?
}

struct ParkingTimerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: ParkingTimerProvider.Entry

    var body: some View {
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline:
            ParkingTimerLockScreenView(entry: entry)
        default:
            parkingTimerHomeView
        }
    }

    @ViewBuilder private var parkingTimerHomeView: some View {
        if let entryTime = entry.entryTime {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 12))
                    Text("泊車計時")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.8))

                Text(formatTime(entryTime))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text(formatDuration(entry.duration))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                if let location = entry.location {
                    Text(location)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "car.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
                Text("未泊車")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval / 3600)
        let m = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        let s = Int(interval.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

struct ParkingTimerLockScreenView: View {
    var entry: ParkingTimerProvider.Entry

    @ViewBuilder var body: some View {
        if let entryTime = entry.entryTime {
            VStack(alignment: .leading, spacing: 2) {
                Text("泊車記憶")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text(formatDuration(entry.duration))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                if let location = entry.location {
                    Text(location)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        } else {
            Text("泊車記憶")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval / 3600)
        let m = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        let s = Int(interval.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

struct ParkingTimerWidget: Widget {
    let kind: String = "ParkingTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ParkingTimerProvider()) { entry in
            ParkingTimerWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("泊車計時")
        .description("顯示泊車入場時間與已計時時長")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemMedium) {
    ParkingTimerWidget()
} timeline: {
    ParkingTimerEntry(date: .now, entryTime: Date().addingTimeInterval(-3600), duration: 3600, location: "台北101")
    ParkingTimerEntry(date: .now, entryTime: nil, duration: 0, location: nil)
}
