import Foundation
import CoreLocation

// MARK: - Sunrise/Sunset Times

struct SunTimes {
    let sunrise: Date
    let sunset: Date
    let civilDawn: Date    // 黎明前
    let civilDusk: Date    // 黄昏后
    
    // 计算各阶段的相对时间（小时偏移）
    var sunriseHour: Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: sunrise)
        return Double(components.hour ?? 6) + Double(components.minute ?? 0) / 60.0
    }
    
    var sunsetHour: Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: sunset)
        return Double(components.hour ?? 18) + Double(components.minute ?? 0) / 60.0
    }
    
    var civilDawnHour: Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: civilDawn)
        return Double(components.hour ?? 4) + Double(components.minute ?? 0) / 60.0
    }
    
    var civilDuskHour: Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: civilDusk)
        return Double(components.hour ?? 20) + Double(components.minute ?? 0) / 60.0
    }
}

// MARK: - API Response

private struct SunriseSunsetResponse: Codable {
    let results: SunriseSunsetResult
    let status: String
}

private struct SunriseSunsetResult: Codable {
    let sunrise: String
    let sunset: String
    let civil_twilight_begin: String
    let civil_twilight_end: String
}

// MARK: - Weather Service

class WeatherService: ObservableObject {
    nonisolated(unsafe) static let shared = WeatherService()
    
    @Published var sunTimes: SunTimes?
    @Published var isLoading = false
    
    private var lastFetchDate: Date?
    private var lastLocation: CLLocationCoordinate2D?
    private var lastAttemptDate: Date?
    private var pendingCompletions: [(SunTimes?) -> Void] = []
    private let now: () -> Date
    private let fetch: (URL, @escaping (Data?) -> Void) -> Void

    init(now: @escaping () -> Date = Date.init,
         fetch: @escaping (URL, @escaping (Data?) -> Void) -> Void = { url, completion in
             URLSession.shared.dataTask(with: url) { data, _, _ in completion(data) }.resume()
         }) {
        self.now = now
        self.fetch = fetch
    }
    
    func fetchSunTimes(for location: CLLocationCoordinate2D, completion: @escaping (SunTimes?) -> Void) {
        // 如果是同一天同一个位置（±0.1度），不重复请求
        let today = Calendar.current.startOfDay(for: now())
        if let lastDate = lastFetchDate,
           let lastLoc = lastLocation,
           Calendar.current.isDate(lastDate, inSameDayAs: today),
           abs(lastLoc.latitude - location.latitude) < 0.1,
           abs(lastLoc.longitude - location.longitude) < 0.1,
           let cached = sunTimes {
            completion(cached)
            return
        }
        if isLoading {
            pendingCompletions.append(completion)
            return
        }
        // A failed request must not be retried for every GPS fix.
        if let attempt = lastAttemptDate, now().timeIntervalSince(attempt) < 60 {
            completion(sunTimes)
            return
        }
        lastAttemptDate = now()
        pendingCompletions.append(completion)
        isLoading = true
        
        let lat = location.latitude
        let lng = location.longitude
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: today)
        let urlString = "https://api.sunrise-sunset.org/json?lat=\(lat)&lng=\(lng)&date=\(date)&formatted=0"
        
        guard let url = URL(string: urlString) else {
            finishFetch(nil, location: location)
            return
        }

        fetch(url) { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data = data,
                      let response = try? JSONDecoder().decode(SunriseSunsetResponse.self, from: data),
                      response.status == "OK" else {
                    self.finishFetch(nil, location: location)
                    return
                }

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let plainFormatter = ISO8601DateFormatter()
                plainFormatter.formatOptions = [.withInternetDateTime]
                func parse(_ value: String) -> Date? {
                    formatter.date(from: value) ?? plainFormatter.date(from: value)
                }
                guard let sunrise = parse(response.results.sunrise),
                      let sunset = parse(response.results.sunset),
                      let civilDawn = parse(response.results.civil_twilight_begin),
                      let civilDusk = parse(response.results.civil_twilight_end) else {
                    self.finishFetch(nil, location: location)
                    return
                }
                
                let sunTimes = SunTimes(
                    sunrise: sunrise,
                    sunset: sunset,
                    civilDawn: civilDawn,
                    civilDusk: civilDusk
                )
                
                self.finishFetch(sunTimes, location: location)
            }
        }
    }

    private func finishFetch(_ result: SunTimes?, location: CLLocationCoordinate2D) {
        isLoading = false
        if let result {
            sunTimes = result
            lastFetchDate = now()
            lastLocation = location
        }
        let callbacks = pendingCompletions
        pendingCompletions.removeAll()
        callbacks.forEach { $0(result ?? sunTimes) }
    }
    
    // 获取当前缓存的日出日落时间，或返回默认值
    func getCurrentSunTimes() -> SunTimes {
        if let cached = sunTimes {
            return cached
        }
        
        // 返回默认值（大约是春秋分的时间）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        
        let defaultSunrise = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: today)!
        let defaultSunset = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today)!
        let defaultDawn = calendar.date(bySettingHour: 4, minute: 30, second: 0, of: today)!
        let defaultDusk = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: today)!
        
        return SunTimes(
            sunrise: defaultSunrise,
            sunset: defaultSunset,
            civilDawn: defaultDawn,
            civilDusk: defaultDusk
        )
    }
}
