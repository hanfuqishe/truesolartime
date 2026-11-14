import Foundation

/// 把 Open-Meteo 的天气读进缓存，供首页卡片使用。
///
/// 与 Android / 鸿蒙 1.4.39 一致：
/// - 正常情况缓存 30 分钟，位置移动超过 5 km 才重新取数；
/// - **取数失败时保留旧数据 24 小时**（不再像 1.4.38 之前那样 6 小时就清空）；
/// - 失败后按 **5 分钟**节流重试，避免网络异常时每秒打接口；
/// - 命中缓存时立刻回调，不阻塞界面。
final class WeatherStore {

    static let shared = WeatherStore()

    private enum Key {
        static let temperature = "weather.temperature"
        static let code = "weather.code"
        static let hourly = "weather.hourly"
        static let fetchedAt = "weather.fetched_at"
        static let attemptAt = "weather.attempt_at"
        static let latitude = "weather.latitude"
        static let longitude = "weather.longitude"
    }

    private let defaults = UserDefaults.standard
    /// 正常刷新间隔。
    private let ttlSeconds: TimeInterval = 30 * 60
    /// 小时预报与旧数据的兜底时限（对齐 1.4.39 的 24 小时）。
    private let hourlyMaxAgeSeconds: TimeInterval = 24 * 60 * 60
    /// 取数失败后的重试间隔（对齐 1.4.39 的 5 分钟）。
    private let retryAfterFailureSeconds: TimeInterval = 5 * 60
    private var inFlight = false

    private init() {}

    /// 缓存里的快照；已过期或从未取过时返回 nil。
    ///
    /// 注意：即便「当前天气」已过 30 分钟，只要还没超过 24 小时的兜底时限，
    /// 仍会把旧数据交出去（离线/接口故障时不至于白屏）。
    func cached() -> WeatherSnapshot? {
        guard defaults.object(forKey: Key.temperature) != nil else { return nil }
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt)
        guard age >= 0, age <= hourlyMaxAgeSeconds else { return nil }
        return WeatherSnapshot(
            temperatureC: defaults.integer(forKey: Key.temperature),
            code: defaults.integer(forKey: Key.code),
            hourly: decodeHourly()
        )
    }

    /// 小时预报，与当前天气共用同一个兜底时限。
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
        markAttempt()
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
        let now = Date().timeIntervalSince1970
        guard defaults.object(forKey: Key.temperature) != nil else { return true }

        let age = now - defaults.double(forKey: Key.fetchedAt)
        // 数据已经超过兜底时限，直接重取。
        if age < 0 || age > hourlyMaxAgeSeconds { return true }

        let lat = defaults.double(forKey: Key.latitude)
        let lon = defaults.double(forKey: Key.longitude)
        let moved = DistrictNaming.distanceKm(lat, lon, place.latitude, place.longitude)
        if moved > DistrictNaming.moveThresholdKm { return true }

        if age > ttlSeconds {
            // 超过正常刷新间隔：距上次「尝试」不到 5 分钟就先等等，避免失败后反复打接口。
            let sinceAttempt = now - defaults.double(forKey: Key.attemptAt)
            return sinceAttempt >= retryAfterFailureSeconds
        }
        return false
    }

    private func markAttempt() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.attemptAt)
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
