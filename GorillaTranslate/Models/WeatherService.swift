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
    static let shared = WeatherService()
    
    @Published var sunTimes: SunTimes?
    @Published var isLoading = false
    
    private var lastFetchDate: Date?
    private var lastLocation: CLLocationCoordinate2D?
    
    private init() {}
    
    func fetchSunTimes(for location: CLLocationCoordinate2D, completion: @escaping (SunTimes?) -> Void) {
        // 如果是同一天同一个位置（±0.1度），不重复请求
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = lastFetchDate,
           let lastLoc = lastLocation,
           Calendar.current.isDate(lastDate, inSameDayAs: today),
           abs(lastLoc.latitude - location.latitude) < 0.1,
           abs(lastLoc.longitude - location.longitude) < 0.1,
           let cached = sunTimes {
            completion(cached)
            return
        }
        
        isLoading = true
        
        let lat = location.latitude
        let lng = location.longitude
        let urlString = "https://api.sunrise-sunset.org/json?lat=\(lat)&lng=\(lng)&formatted=0"
        
        guard let url = URL(string: urlString) else {
            isLoading = false
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                guard let data = data,
                      let response = try? JSONDecoder().decode(SunriseSunsetResponse.self, from: data),
                      response.status == "OK" else {
                    completion(nil)
                    return
                }
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                guard let sunrise = formatter.date(from: response.results.sunrise),
                      let sunset = formatter.date(from: response.results.sunset),
                      let civilDawn = formatter.date(from: response.results.civil_twilight_begin),
                      let civilDusk = formatter.date(from: response.results.civil_twilight_end) else {
                    completion(nil)
                    return
                }
                
                let sunTimes = SunTimes(
                    sunrise: sunrise,
                    sunset: sunset,
                    civilDawn: civilDawn,
                    civilDusk: civilDusk
                )
                
                self?.sunTimes = sunTimes
                self?.lastFetchDate = Date()
                self?.lastLocation = location
                completion(sunTimes)
            }
        }
        task.resume()
    }
    
    // 获取当前缓存的日出日落时间，或返回默认值
    func getCurrentSunTimes() -> SunTimes {
        if let cached = sunTimes {
            return cached
        }
        
        // 返回默认值（大约是春秋分的时间）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
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
