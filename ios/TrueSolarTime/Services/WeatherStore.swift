import Foundation

/// 把 Open-Meteo 的天气读进缓存，供首页卡片使用。
///
/// 与 Android / 鸿蒙 1.4.39 一致：
/// - 正常情况缓存 30 分钟，位置移动超过 5 km 才重新取数；
/// - **取数失败时保留旧数据 24 小时**（不再像 1.4.38 之前那样 6 小时就清空）；
/// - 失败后按 **5 分钟**节流重试，避免网络异常时每秒打接口；
/// - 命中缓存时立刻回调，不阻塞界面。
///
/// 失败原因（超时 / HTTP 状态码 / 解析失败）会记在 `lastErrorDescription` 里，
/// 设置页的「诊断」分组会把它显示出来——否则界面上只能看到 `--`，没法判断问题在哪。
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
    /// 单次请求超时。
    private let requestTimeoutSeconds: TimeInterval = 15

    private var inFlight = false
    private var retriedOnce = false

    /// 最近一次失败原因（成功时为 nil）。
    private(set) var lastErrorDescription: String?
    /// 最近一次请求结束的时刻。
    private(set) var lastFinishedAt: Date?

    private init() {}

    /// 缓存里的快照；超过 24 小时才返回 nil。
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
        guard let url = WeatherParsing.url(latitude: place.latitude, longitude: place.longitude) else {
            lastErrorDescription = "坐标无法生成请求地址"
            lastFinishedAt = Date()
            return
        }

        inFlight = true
        retriedOnce = false
        markAttempt()
        fetch(url: url, place: place, completion: completion)
    }

    private func fetch(url: URL, place: Place, completion: ((WeatherSnapshot) -> Void)?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeoutSeconds
        // 网络在切换（Wi-Fi ↔ 蜂窝）时等一下，而不是立刻失败。
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode

            if let error {
                // 网络类错误：没有数据时重试一次（DNS/IPv6 抖动很常见）。
                let description = Self.describe(error: error)
                DispatchQueue.main.async {
                    self.inFlight = false
                    self.lastErrorDescription = description
                    self.lastFinishedAt = Date()
                    if !self.retriedOnce && self.cached() == nil {
                        self.retriedOnce = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            self.inFlight = true
                            self.fetch(url: url, place: place, completion: completion)
                        }
                    }
                }
                return
            }

            if let status, !(200..<300).contains(status) {
                DispatchQueue.main.async {
                    self.inFlight = false
                    self.lastErrorDescription = "HTTP \(status)"
                    self.lastFinishedAt = Date()
                }
                return
            }

            guard let data,
                  let json = String(data: data, encoding: .utf8),
                  let current = WeatherParsing.parseCurrent(json)
            else {
                DispatchQueue.main.async {
                    self.inFlight = false
                    self.lastErrorDescription = "返回内容无法解析"
                    self.lastFinishedAt = Date()
                }
                return
            }

            let snapshot = WeatherSnapshot(
                temperatureC: current.temperatureC,
                code: current.code,
                hourly: WeatherParsing.parseHourly(json)
            )
            DispatchQueue.main.async {
                self.inFlight = false
                self.lastErrorDescription = nil
                self.lastFinishedAt = Date()
                self.save(place: place, snapshot: snapshot)
                completion?(snapshot)
            }
        }.resume()
    }

    /// 人类可读的失败原因，直接显示在设置页里。
    private static func describe(error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorTimedOut:
            return "请求超时（15 秒）"
        case NSURLErrorNotConnectedToInternet:
            return "设备未联网"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "域名解析失败（api.open-meteo.com）"
        case NSURLErrorCannotConnectToHost:
            return "无法连接服务器"
        case NSURLErrorNetworkConnectionLost:
            return "连接中断"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "TLS 握手失败"
        default:
            return "网络错误（\(ns.domain) \(ns.code)）"
        }
    }

    /// 设置页「诊断」用的一行描述。
    func diagnosticsSummary() -> String {
        let now = Date()
        if let snapshot = cached() {
            let age = Int(now.timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt))
            let ageText = age < 60 ? "\(age) 秒前" : (age < 3600 ? "\(age / 60) 分钟前" : "\(age / 3600) 小时前")
            var text = "\(snapshot.temperatureC)° · \(snapshot.condition.label) · \(ageText)更新"
            if let lastErrorDescription {
                text += "（最近一次失败：\(lastErrorDescription)）"
            }
            return text
        }
        if let lastErrorDescription {
            return "无数据：\(lastErrorDescription)"
        }
        return inFlight ? "正在请求…" : "无数据：尚未请求成功"
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
