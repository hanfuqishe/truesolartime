import Foundation

/// 把 Open-Meteo 的天气读进缓存，供首页卡片使用。
///
/// 与 Android 版一致：缓存 30 分钟，位置移动超过 5 km 才重新取数；
/// 命中缓存时立刻回调，不阻塞界面。
final class WeatherStore {

    static let shared = WeatherStore()

    private enum Key {
        static let temperature = "weather.temperature"
        static let code = "weather.code"
        static let hourly = "weather.hourly"
        static let fetchedAt = "weather.fetched_at"
        static let latitude = "weather.latitude"
        static let longitude = "weather.longitude"
    }

    private let defaults = UserDefaults.standard
    private let ttlSeconds: TimeInterval = 30 * 60
    private let hourlyMaxAgeSeconds: TimeInterval = 6 * 60 * 60
    private var inFlight = false

    private init() {}

    /// 缓存里的快照；已过期或从未取过时返回 nil。
    func cached() -> WeatherSnapshot? {
        guard defaults.object(forKey: Key.temperature) != nil else { return nil }
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt)
        guard age >= 0, age <= ttlSeconds else { return nil }
        let hourly = decodeHourly()
        return WeatherSnapshot(
            temperatureC: defaults.integer(forKey: Key.temperature),
            code: defaults.integer(forKey: Key.code),
            hourly: hourly
        )
    }

    /// 小时预报，可以比当前天气活得久一点（列表变化慢）。
    func hourly() -> [WeatherHour] {
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt)
        guard age >= 0, age <= hourlyMaxAgeSeconds else { return [] }
        return decodeHourly()
    }

    /// 需要时联网取一次；成功后在主线程回调最新快照。
    func requestRefresh(place: Place, force: Bool = false, completion: ((WeatherSnapshot) -> Void)? = nil) {
        guard !inFlight else { return }
        if !force && !needsRefresh(place) { return }
        guard let url = WeatherParsing.url(latitude: place.latitude, longitude: place.longitude) else { return }

        inFlight = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            defer { self.inFlight = false }
            guard
                let data,
                let json = String(data: data, encoding: .utf8),
                let current = WeatherParsing.parseCurrent(json)
            else { return }

            let snapshot = WeatherSnapshot(
                temperatureC: current.temperatureC,
                code: current.code,
                hourly: WeatherParsing.parseHourly(json)
            )
            DispatchQueue.main.async {
                self.save(place: place, snapshot: snapshot)
                completion?(snapshot)
            }
        }.resume()
    }

    private func decodeHourly() -> [WeatherHour] {
        guard let data = defaults.object(forKey: Key.hourly) as? Data else { return [] }
        return (try? JSONDecoder().decode([WeatherHour].self, from: data)) ?? []
    }

    private func needsRefresh(_ place: Place) -> Bool {
        guard defaults.object(forKey: Key.temperature) != nil else { return true }
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt)
        if age < 0 || age > ttlSeconds { return true }
        let lat = defaults.double(forKey: Key.latitude)
        let lon = defaults.double(forKey: Key.longitude)
        let moved = DistrictNaming.distanceKm(lat, lon, place.latitude, place.longitude)
        return moved > DistrictNaming.moveThresholdKm
    }

    private func save(place: Place, snapshot: WeatherSnapshot) {
        defaults.set(snapshot.temperatureC, forKey: Key.temperature)
        defaults.set(snapshot.code, forKey: Key.code)
        if let data = try? JSONEncoder().encode(snapshot.hourly) {
            defaults.set(data, forKey: Key.hourly)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Key.fetchedAt)
        defaults.set(place.latitude, forKey: Key.latitude)
        defaults.set(place.longitude, forKey: Key.longitude)
    }
}
