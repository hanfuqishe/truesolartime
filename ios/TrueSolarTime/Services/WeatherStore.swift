import Foundation

/// 天气取数：主源 Open-Meteo（**1 小时**粒度）+ 备用源 7Timer!（**3 小时**粒度）。
///
/// 与 Android `WeatherRepository` / 鸿蒙同一套策略：
/// 1. 主源失败（网络 / 超时 / 非 2xx / JSON 解析失败）→ **2 秒后重试一次**（只重试一次）；
/// 2. 仍失败且缓存 ≤30 分钟 → **保持现状不清空**，界面继续用缓存；
/// 3. 缓存过期（或根本没有缓存）→ 请求备用源 7Timer!，成功就整份换成 3 小时粒度；
/// 4. 两个源都失败 → **保留旧数据继续显示**（24 小时硬上限），诊断里标注「数据过期 N 分钟」。
///
/// 刷新触发（满足任意一条，判定见 `WeatherParsing.shouldRefresh`）：
/// - 数据已过期（30 分钟 TTL）；
/// - **当前是低精度数据**（7Timer! / 3 小时步长）—— 即使没过期也试一次，尽快升回 1 小时数据；
///   这一条最多每 10 分钟一次（时间戳落盘），但回到前台 / 切换地点可以立刻触发一次。
///
/// 缓存与地点绑定：存下来的坐标与当前地点相距超过 5 km 时，这份缓存**不属于**当前地点，
/// 一律当作没有数据（界面显示占位符），绝不能让 A 城市的气温出现在 B 城市下。
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
        /// 这份数据来自哪个源（`WeatherSource.rawValue`）；底部署名与诊断都跟着它切换。
        static let source = "weather.source"
        /// 逐时步长（小时）。与来源一起存，旧版本缓存没有这个键时要重取一次。
        static let step = "weather.step"
        /// 上一次「低精度触发刷新」的时刻：把 10 分钟节流也落盘，重启后不会立刻再打一次。
        static let lowPrecisionAttempt = "weather.low_precision_attempt"
    }

    private let defaults = UserDefaults.standard
    /// 正常刷新间隔：超过它就发起请求（不是「超过它就不显示」）。
    private let ttlSeconds: TimeInterval = TimeInterval(WeatherParsing.cacheTTLSeconds)
    /// 小时预报与旧数据的兜底时限（对齐 1.4.39 的 24 小时硬上限）。
    private let displayMaxAgeSeconds: TimeInterval = TimeInterval(WeatherParsing.displayMaxAgeSeconds)
    /// 取数失败后的重试间隔（对齐 1.4.39 的 5 分钟）。
    private let retryAfterFailureSeconds: TimeInterval = 5 * 60
    /// 主源失败后**立刻**重试一次前的等待：一次握手超时 / 一个坏节点不该让整张卡从
    /// 1 小时粒度掉到 3 小时粒度，但也不该为了主源把降级拖太久（用户可能正盯着 `--`）。
    private let primaryRetryDelaySeconds: TimeInterval = 2
    /// 单次请求超时。
    private let requestTimeoutSeconds: TimeInterval = 15

    private var inFlight = false
    /// 本次请求开始时刻，用于「已 N 秒」与卡死看门狗。
    private var attemptStartedAt: Date?

    /// 最近一次失败原因（成功时为 nil）。
    private(set) var lastErrorDescription: String?
    /// 最近一次取数的结果说明（诊断用：主源成功 / 沿用缓存 / 降到 7Timer! / 两个源都失败）。
    private(set) var lastResultDescription: String?
    /// 最近一次请求结束的时刻。
    private(set) var lastFinishedAt: Date?

    private init() {}

    // MARK: - 读缓存

    /// 缓存里的快照；不属于当前地点或超过 24 小时都返回 nil。
    ///
    /// 传入 `place` 时会核对缓存对应的坐标：换城市（> 5 km）就当没有缓存，
    /// 免得切到别的城市后还显示上一个城市的气温（新地点没有缓存时界面就是占位符）。
    func cached(for place: Place? = nil) -> WeatherSnapshot? {
        guard defaults.object(forKey: Key.temperature) != nil else { return nil }
        if let place, !belongsTo(place) { return nil }
        guard let age = ageSeconds(), WeatherParsing.isDisplayable(ageSeconds: age) else { return nil }
        // 不传 stepHours：`WeatherSnapshot.init` 按来源归一化，缓存里旧的 `weather.step`
        // （甚至旧版本留下的 0 / 1）不可能再把 7Timer! 的数据排成 1 小时一格。
        return WeatherSnapshot(
            temperatureC: defaults.integer(forKey: Key.temperature),
            code: defaults.integer(forKey: Key.code),
            hourly: decodeHourly(),
            source: source
        )
    }

    /// 小时预报，与当前天气共用同一个兜底时限（同样要求属于当前地点）。
    func hourly(for place: Place? = nil) -> [WeatherHour] {
        cached(for: place)?.hourly ?? []
    }

    /// 缓存数据的来源（底部署名与诊断都跟着它切换）；没有缓存时按主源算。
    var source: WeatherSource {
        WeatherSource.of(id: defaults.string(forKey: Key.source))
    }

    /// 缓存数据的步长（1 或 3 小时）——**永远由来源决定**。
    ///
    /// 不再读 `weather.step` 里存的值：那是一个可以被旧版本 / 半截写入搞脏的副本，
    /// 一旦它与 `weather.source` 不一致，就会出现「署名 7Timer!、逐时行却按 1 小时排」。
    /// `weather.step` 仍然会写（`needsRefresh` 用它的**存在性**判断「这份缓存知道自己的步长」），
    /// 但读的时候只信来源。
    var stepHours: Int {
        source.stepHours
    }

    /// 缓存有多旧（秒）；没有缓存时返回 nil。诊断里用它标注「数据过期 N 分钟」。
    func ageSeconds() -> Int? {
        guard defaults.object(forKey: Key.fetchedAt) != nil else { return nil }
        let age = Int(Date().timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt))
        return max(age, 0)
    }

    /// 缓存里的坐标是否属于当前地点（相距不超过 5 km）。
    private func belongsTo(_ place: Place) -> Bool {
        guard defaults.object(forKey: Key.latitude) != nil else { return false }
        let lat = defaults.double(forKey: Key.latitude)
        let lon = defaults.double(forKey: Key.longitude)
        let moved = DistrictNaming.distanceKm(lat, lon, place.latitude, place.longitude)
        return moved <= DistrictNaming.moveThresholdKm
    }

    // MARK: - 取数

    /// 需要时联网取一次；结束后在主线程回调（参数是按**当前地点**过滤后的快照，可能为 nil）。
    ///
    /// - Parameters:
    ///   - force: 忽略所有判定，立刻取（用户手工换了地点时用）。
    ///   - ignoreLowPrecisionThrottle: 本轮不受「低精度刷新每 10 分钟一次」的限制。
    ///     回到前台 / 切换地点时用 true —— 用户刚打开 App，值得立刻试着升级回 1 小时数据。
    /// - Returns: 是否真的发起了这次取数（被 30 分钟窗口 / 10 分钟节流 / in-flight 挡住时为 false）。
    @discardableResult
    func requestRefresh(
        place: Place,
        force: Bool = false,
        ignoreLowPrecisionThrottle: Bool = false,
        completion: ((WeatherSnapshot?) -> Void)? = nil
    ) -> Bool {
        guard !inFlight else { return false }
        if !force && !needsRefresh(place, ignoreLowPrecisionThrottle: ignoreLowPrecisionThrottle) {
            return false
        }
        guard let url = WeatherParsing.url(latitude: place.latitude, longitude: place.longitude) else {
            lastErrorDescription = L("diag.urlFailed")
            lastResultDescription = L("diag.urlFailed")
            lastFinishedAt = Date()
            completion?(cached(for: place))
            return false
        }

        inFlight = true
        attemptStartedAt = Date()
        markAttempt()
        // 当前拿的是低精度数据：记下这次「低精度触发」的时刻，10 分钟内不再重复试。
        if source.isLowPrecision || stepHours > 1 {
            markLowPrecisionAttempt()
        }
        fetchPrimary(place: place, url: url, attempt: 0, completion: completion)
        return true
    }

    /// ① 主源：失败后 2 秒重试一次，两次都失败才降级。
    private func fetchPrimary(
        place: Place,
        url: URL,
        attempt: Int,
        completion: ((WeatherSnapshot?) -> Void)?
    ) {
        get(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let json):
                if let payload = WeatherParsing.parsePrimary(json) {
                    self.finishPrimary(place: place, payload: payload, completion: completion)
                    return
                }
                self.retryOrFallback(
                    place: place,
                    url: url,
                    attempt: attempt,
                    failure: L("diag.parseFailed"),
                    completion: completion
                )
            case .failure(let reason):
                self.retryOrFallback(
                    place: place,
                    url: url,
                    attempt: attempt,
                    failure: reason,
                    completion: completion
                )
            }
        }
    }

    private func retryOrFallback(
        place: Place,
        url: URL,
        attempt: Int,
        failure: String,
        completion: ((WeatherSnapshot?) -> Void)?
    ) {
        lastErrorDescription = failure
        if attempt == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + primaryRetryDelaySeconds) { [weak self] in
                guard let self else { return }
                self.fetchPrimary(place: place, url: url, attempt: 1, completion: completion)
            }
            return
        }
        degrade(place: place, completion: completion)
    }

    /// 主源成功：整份换成 1 小时粒度。
    private func finishPrimary(
        place: Place,
        payload: (current: (temperatureC: Int, code: Int), hourly: [WeatherHour]),
        completion: ((WeatherSnapshot?) -> Void)?
    ) {
        let snapshot = WeatherSnapshot(
            temperatureC: payload.current.temperatureC,
            code: payload.current.code,
            hourly: payload.hourly,
            source: .openMeteo
        )
        save(place: place, snapshot: snapshot)
        lastErrorDescription = nil
        lastResultDescription = L("diag.primarySuccess")
        finish(place: place, completion: completion)
    }

    /// ②③④ 主源两次都失败之后的降级链。
    private func degrade(place: Place, completion: ((WeatherSnapshot?) -> Void)?) {
        let age = ageSeconds()
        let hasCache = defaults.object(forKey: Key.temperature) != nil && belongsTo(place)

        // ② 缓存还没过期（且属于当前地点）：什么都不动，界面继续显示缓存（不清空）。
        if hasCache,
           WeatherParsing.fallbackFor(hasCache: true, cacheAgeSeconds: age ?? 0) == .keepCache,
           let snapshot = cached(for: place) {
            lastResultDescription = L("diag.keepCache")
            finish(place: place, completion: completion, snapshot: snapshot)
            return
        }

        // ③ 缓存已过期（或根本没有 / 不属于这个地点）：问备用源 7Timer!。
        guard let url = WeatherParsing.sevenTimerURL(latitude: place.latitude, longitude: place.longitude) else {
            lastResultDescription = L("diag.urlFailed")
            finish(place: place, completion: completion)
            return
        }
        get(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let json):
                let points = WeatherParsing.parseSevenTimer(json)
                let now = Int(Date().timeIntervalSince1970)
                if let current = WeatherParsing.snapshotAt(points: points, nowEpochSeconds: now) {
                    // 步长不在这里传：`WeatherSnapshot.init` 会按 `source` 归一化成 3 小时，
                    // 「署名 7Timer! + 1 小时槽位」这套组合在类型层面就不成立。
                    let snapshot = WeatherSnapshot(
                        temperatureC: current.temperatureC,
                        code: current.code,
                        hourly: points,
                        source: .sevenTimer
                    )
                    self.save(place: place, snapshot: snapshot)
                    self.lastErrorDescription = nil
                    self.lastResultDescription = L("diag.fellBack")
                    self.finish(place: place, completion: completion, snapshot: snapshot)
                    return
                }
                self.keepOldData(place: place, failure: L("diag.parseFailed"), completion: completion)
            case .failure(let reason):
                self.keepOldData(place: place, failure: reason, completion: completion)
            }
        }
    }

    /// ④ 两个源都失败：旧数据继续显示（哪怕过期，只要还在 24 小时内），诊断里标注过期时长。
    private func keepOldData(
        place: Place,
        failure: String,
        completion: ((WeatherSnapshot?) -> Void)?
    ) {
        lastErrorDescription = failure
        let stale = WeatherParsing.staleLabel(ageSeconds: ageSeconds()) ?? L("common.none")
        lastResultDescription = Lf("diag.bothFailed", stale)
        finish(place: place, completion: completion)
    }

    /// 收尾：复位 in-flight、记录结束时刻，并把**属于当前地点**的快照回调出去。
    private func finish(
        place: Place,
        completion: ((WeatherSnapshot?) -> Void)?,
        snapshot: WeatherSnapshot? = nil
    ) {
        inFlight = false
        attemptStartedAt = nil
        lastFinishedAt = Date()
        completion?(snapshot ?? cached(for: place))
    }

    /// 取一段文本；网络错误 / 超时 / 非 2xx / 读数据失败一律当失败（都不抛给调用方）。
    private enum FetchResult {
        case success(String)
        case failure(String)
    }

    private func get(url: URL, completion: @escaping (FetchResult) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeoutSeconds
        // 网络在切换（Wi-Fi ↔ 蜂窝）时等一下，而不是立刻失败。
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: FetchResult
            if let error {
                result = .failure(Self.describe(error: error))
            } else if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                result = .failure("HTTP \(status)")
            } else if let data, let text = String(data: data, encoding: .utf8) {
                result = .success(text)
            } else {
                result = .failure(L("diag.parseFailed"))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// 人类可读的失败原因，直接显示在设置页里。
    private static func describe(error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorTimedOut:
            return L("diag.timeout")
        case NSURLErrorNotConnectedToInternet:
            return L("diag.offline")
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return L("diag.dns")
        case NSURLErrorCannotConnectToHost:
            return L("diag.cannotConnect")
        case NSURLErrorNetworkConnectionLost:
            return L("diag.connectionLost")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return L("diag.tls")
        default:
            return Lf("diag.networkError", ns.domain, ns.code)
        }
    }

    /// 每秒由界面调用一次：请求卡住太久就复位，避免 `inFlight` 永远为 true、
    /// 后续刷新全被 `guard !inFlight` 挡掉（真机上出现过一直停在「正在请求…」的现象）。
    ///
    /// 最长链路是「主源超时 15s + 等 2s + 主源再超时 15s + 备用源 15s」，约 47 秒，
    /// 阈值取 70 秒才不会把正在降级的请求误判成卡死。
    func watchdog() {
        guard inFlight, let startedAt = attemptStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 70 else { return }
        inFlight = false
        attemptStartedAt = nil
        lastErrorDescription = Lf("diag.noResponse", Int(elapsed))
        lastFinishedAt = Date()
    }

    // MARK: - 诊断

    /// 当前天气源 + 步长（诊断页一行：`Open-Meteo · 每 1 小时一格`）。
    func sourceSummary() -> String {
        let source = self.source
        let step = stepHours
        return "\(source.displayName) · \(Lf("weather.stepHours", step))"
    }

    /// 数据有多旧（诊断页一行：「数据过期 N 分钟」）；没有缓存时显示「无」。
    func ageSummary() -> String {
        guard let age = ageSeconds() else { return L("common.none") }
        return WeatherParsing.staleLabel(ageSeconds: age) ?? L("common.none")
    }

    /// 最近一次失败原因（诊断页一行）；没有失败过时显示「无」。
    func failureSummary() -> String {
        lastErrorDescription ?? L("common.none")
    }

    /// 设置页「诊断」用的一行描述。
    func diagnosticsSummary() -> String {
        let now = Date()
        if let snapshot = cached() {
            let age = Int(now.timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt))
            let ageText: String
            if age < 60 {
                ageText = Lf("diag.secondsAgo", age)
            } else if age < 3600 {
                ageText = Lf("diag.minutesAgo", age / 60)
            } else {
                ageText = Lf("diag.hoursAgo", age / 3600)
            }
            var text = Lf("diag.updated", "\(snapshot.temperatureC)°", snapshot.condition.label, ageText)
            if let lastErrorDescription {
                text += Lf("diag.lastFailure", lastErrorDescription)
            }
            return text
        }
        if let lastErrorDescription {
            return Lf("diag.noData", lastErrorDescription)
        }
        if inFlight {
            if let startedAt = attemptStartedAt {
                let elapsed = Int(Date().timeIntervalSince(startedAt))
                return Lf("diag.requestingElapsed", elapsed)
            }
            return L("diag.requesting")
        }
        return L("diag.neverSucceeded")
    }

    // MARK: - 存取

    private func decodeHourly() -> [WeatherHour] {
        guard let data = defaults.object(forKey: Key.hourly) as? Data else { return [] }
        return (try? JSONDecoder().decode([WeatherHour].self, from: data)) ?? []
    }

    private func needsRefresh(_ place: Place, ignoreLowPrecisionThrottle: Bool) -> Bool {
        guard defaults.object(forKey: Key.temperature) != nil else { return true }

        // 旧版本缓存里缺来源 / 步长：重取一次，否则槽位标签会与读数错位。
        if defaults.object(forKey: Key.source) == nil || defaults.object(forKey: Key.step) == nil {
            return true
        }

        // 换了地方（> 5 km）立刻取一次：新地点要么有自己的缓存，要么就是占位符 + 这次取数。
        if !belongsTo(place) { return true }

        guard let age = ageSeconds() else { return true }
        if age > Int(displayMaxAgeSeconds) { return true }

        let isStale = age > Int(ttlSeconds)
        let isLowPrecision = source.isLowPrecision || stepHours > 1

        if isStale {
            // 过期：纯判定一定给 true，再叠上 5 分钟失败节流 ——
            // 否则一直失败时每次回到前台都会立刻打一次网络（原有的节流语义不能丢）。
            guard WeatherParsing.shouldRefresh(
                isStale: true,
                isLowPrecision: isLowPrecision,
                lastLowPrecisionAttempt: lowPrecisionSinceAttemptSeconds()
            ) else { return false }
            let sinceAttempt = Int(Date().timeIntervalSince1970 - defaults.double(forKey: Key.attemptAt))
            return sinceAttempt >= Int(retryAfterFailureSeconds)
        }

        // 未过期：只有「低精度也要升级」这一条会触发；回到前台 / 切换地点可跳过 10 分钟窗口。
        guard isLowPrecision else { return false }
        if ignoreLowPrecisionThrottle { return true }
        return WeatherParsing.shouldRefresh(
            isStale: false,
            isLowPrecision: true,
            lastLowPrecisionAttempt: lowPrecisionSinceAttemptSeconds()
        )
    }

    /// 距上一次「低精度触发刷新」过去了多少秒；从没试过返回 nil。
    private func lowPrecisionSinceAttemptSeconds() -> Int? {
        guard defaults.object(forKey: Key.lowPrecisionAttempt) != nil else { return nil }
        return Int(Date().timeIntervalSince1970 - defaults.double(forKey: Key.lowPrecisionAttempt))
    }

    private func markLowPrecisionAttempt() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lowPrecisionAttempt)
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
        defaults.set(snapshot.source.rawValue, forKey: Key.source)
        defaults.set(snapshot.stepHours, forKey: Key.step)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.fetchedAt)
        defaults.set(place.latitude, forKey: Key.latitude)
        defaults.set(place.longitude, forKey: Key.longitude)
    }
}
