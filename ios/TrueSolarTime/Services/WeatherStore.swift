import Foundation

/// 天气取数：主源 Open-Meteo（**1 小时**粒度）+ 备用源 7Timer!（**3 小时**粒度）。
///
/// 三端统一的新策略（**主源失败不拖，降级后尽快切回**）：
/// 1. 主源失败（网络 / 超时 / 非 2xx / JSON 解析失败）→ **不再等 2 秒重试**，**立刻**请求备用源
///    （单次请求超时也从 15 秒缩到 5 秒，界面不用干等）；
/// 2. 缓存 ≤30 分钟 → **保持现状不清空**，界面继续用缓存，不问备用源；
/// 3. 缓存过期（或根本没有缓存）→ 请求 7Timer!，成功就整份换成 3 小时粒度；
/// 4. 两个源都失败 → **保留旧数据继续显示**（24 小时硬上限），诊断里标注「数据过期 N 分钟」。
///
/// 刷新触发（判定见 `WeatherParsing.shouldRefresh` / `needsRefresh`）：
/// - **当前是低精度数据**（7Timer! / 3 小时）→ 退避式重试主源：**前台 60 → 120 → 300 秒**（封顶 5 分钟，
///   连续失败才退避，成功切回立刻清零）、**后台 10 分钟**；不看 30 分钟过期与否。
///   回到前台 / 切换地点可以立刻触发一次（跳过窗口）；
/// - **主源数据** → 30 分钟过期才刷，过期后失败再按 5 分钟节流。切回主源后绝不按 60 秒轮询。
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
        /// 上一次「低精度触发刷新」的时刻：把退避窗口也落盘，重启后不会立刻再打一次。
        static let lowPrecisionAttempt = "weather.low_precision_attempt"
        /// 「重试主源」的**连续**失败次数：决定前台退避档位（60 → 120 → 300 秒），成功一次就清零。
        static let lowPrecisionFailures = "weather.low_precision_failures"
    }

    private let defaults = UserDefaults.standard
    /// 正常刷新间隔：超过它就发起请求（不是「超过它就不显示」）。
    private let ttlSeconds: TimeInterval = TimeInterval(WeatherParsing.cacheTTLSeconds)
    /// 小时预报与旧数据的兜底时限（对齐 1.4.39 的 24 小时硬上限）。
    private let displayMaxAgeSeconds: TimeInterval = TimeInterval(WeatherParsing.displayMaxAgeSeconds)
    /// 主源数据过期之后，取数一直失败时的重试间隔（5 分钟）。
    private let failureRetrySeconds: TimeInterval = TimeInterval(WeatherParsing.primaryFailureRetrySeconds)

    private var inFlight = false
    /// 本次请求开始时刻，用于「已 N 秒」与卡死看门狗。
    private var attemptStartedAt: Date?
    /// App 是否在前台（由 `AppModel` 按 `scenePhase` 同步）。
    ///
    /// 前台：降级后按 60 → 120 → 300 秒的退避轮询主源；后台：最少隔 10 分钟才试一次
    /// （iOS 会挂起 App，计时器本来也不跑，这里把判定口径一起对齐）。
    private var isForeground = true

    /// 天气请求用的会话：单次请求超时 **5 秒**（`WeatherParsing.requestTimeoutSeconds`）。
    ///
    /// 主源失败要立刻降级，所以不能挂在 15 秒的超时上；也不显式设置 `waitsForConnectivity`
    /// —— `ephemeral` 配置的默认值就是 `false`，离线时几乎立刻失败，界面马上走
    /// 「保留旧数据」这条路，而不是卡在「正在请求…」。
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(WeatherParsing.requestTimeoutSeconds)
        configuration.timeoutIntervalForResource = TimeInterval(WeatherParsing.requestTimeoutSeconds * 2)
        return URLSession(configuration: configuration)
    }()

    /// 最近一次失败原因（成功时为 nil）。
    private(set) var lastErrorDescription: String?
    /// 最近一次 WeatherKit 失败原因（诊断用；成功或未尝试时为 nil）。
    private(set) var weatherKitFailure: String?
    /// 本轮是否已经试过 WeatherKit（自动模式回退 Open-Meteo 时避免无限重入）。
    private var weatherKitAttempted = false
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
    ///   - ignoreLowPrecisionThrottle: 本轮跳过退避窗口（60 → 120 → 300 秒 / 后台 10 分钟）。
    ///     回到前台 / 切换地点时用 true —— 用户刚打开 App，值得立刻试一次切回 1 小时数据。
    /// - Returns: 是否真的发起了这次取数（被 30 分钟窗口 / 退避窗口 / in-flight 挡住时为 false）。
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

        // **WeatherKit 优先**（自动 / 手动 WeatherKit 且非未知态）：
        // 成功就直接用它的快照；失败只记诊断、继续走下面的 Open-Meteo 链路（不弹错误）。
        if WeatherChain.shouldRequestWeatherKit(
            setting: AppSettings().weatherSource,
            isLocationUnknown: false
        ) {
            weatherKitAttempted = true
            let setting = AppSettings().weatherSource
            WeatherKitProvider.fetch(latitude: place.latitude, longitude: place.longitude) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.weatherKitFailure = nil
                    self.finish(place: place, snapshot: snapshot, completion: completion)
                case .failure(let failure):
                    self.weatherKitFailure = failure.displayText
                    self.lastErrorDescription = Lf("weather.diagWeatherKitFailureFormat", failure.displayText)
                    // 手动 WeatherKit：不回退（保留旧数据），直接收工；自动模式下继续走 Open-Meteo。
                    if WeatherChain.nextSource(after: .weatherKit, setting: setting) == nil {
                        self.keepOldData(place: place, completion: completion)
                        return
                    }
                    self.fetchOpenMeteoAfterWeatherKit(place: place, completion: completion)
                }
            }
            return true
        }
        attemptStartedAt = Date()
        markAttempt()
        // 当前拿的是低精度数据：记下这次「重试主源」的时刻，退避窗口（60/120/300 秒）从这里算。
        if source.isLowPrecision {
            markLowPrecisionAttempt()
        }
        fetchPrimary(place: place, url: url, attempt: 0, completion: completion)
        return true
    }

    /// ① 主源：**失败一次就立刻降级**（不再等 2 秒重试，界面不用干等）。
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
                self.primaryFailed(
                    place: place,
                    url: url,
                    attempt: attempt,
                    failure: L("diag.parseFailed"),
                    completion: completion
                )
            case .failure(let reason):
                self.primaryFailed(
                    place: place,
                    url: url,
                    attempt: attempt,
                    failure: reason,
                    completion: completion
                )
            }
        }
    }

    /// 主源这一次失败之后做什么（判定在 Core 里，便于自检）。
    ///
    /// 现在 `WeatherParsing.primaryMaxAttempts == 1`，所以**第一次失败就是降级**：
    /// 立刻去问 7Timer!，把 3 小时粒度的数据先摆在界面上，而不是让用户盯着空白等重试。
    /// `.retry` 分支保留着（且不再有 2 秒等待），以后若把 `primaryMaxAttempts` 调大就可直接用。
    private func primaryFailed(
        place: Place,
        url: URL,
        attempt: Int,
        failure: String,
        completion: ((WeatherSnapshot?) -> Void)?
    ) {
        lastErrorDescription = failure
        // 正在显示 7Timer! 数据：这次失败要计入退避档位（60 → 120 → 300 秒，见
        // `WeatherParsing.lowPrecisionRetryDelay`）。主源数据时不计：那套走 5 分钟节流。
        if source.isLowPrecision {
            noteLowPrecisionFailure()
        }
        switch WeatherParsing.afterPrimaryFailure(attempt: attempt) {
        case .fallback:
            degrade(place: place, completion: completion)
        case .retry:
            fetchPrimary(place: place, url: url, attempt: attempt + 1, completion: completion)
        }
    }

    /// 主源成功：整份换成 1 小时粒度，**清空退避**（连续失败次数归零）。
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
        // 切回主源：退避与「低精度轮询」的计时一起重置，回到 30 分钟过期 / 5 分钟节流的普通逻辑。
        resetLowPrecisionRetry()
        finish(place: place, completion: completion)
    }

    /// ②③④ 主源失败之后的降级链（**只失败一次就进来**，不再有重试）。
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
                    // 「重试主源」的计时从降级这一刻开始：主源刚失败过，立刻再打一次只是浪费，
                    // 所以 60 秒后才试；这次失败同时计入退避档位（连续 1 次 → 60 秒、
                    // 2 次 → 120 秒、≥3 次 → 300 秒，见 `WeatherParsing.lowPrecisionRetryDelay`）。
                    if self.lowPrecisionFailures == 0 {
                        self.noteLowPrecisionFailure()
                    }
                    self.markLowPrecisionAttempt()
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
        // 与 session 的 `timeoutIntervalForRequest` 同一个值（5 秒）：主源要尽快失败、尽快降级。
        request.timeoutInterval = TimeInterval(WeatherParsing.requestTimeoutSeconds)
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
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
    /// 最长链路现在是「主源 5 秒 + 备用源 5 秒 ≈ 10 秒」（去掉 2 秒重试之后更短了），
    /// 阈值取 30 秒：给慢网 / DNS 卡住留 3 倍余量，又不会把正在降级的请求误判成卡死。
    func watchdog() {
        guard inFlight, let startedAt = attemptStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 30 else { return }
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

        // 低精度数据（7Timer! / 3 小时）：按退避表轮询主源（前台 60 → 120 → 300 秒、后台 10 分钟），
        // 不看 30 分钟过期与否 —— 手里只有 3 小时粒度时，唯一要紧的是尽快切回 1 小时数据。
        // 成功一次 `source` 就变回 `.openMeteo`，这条分支随即失效（主源数据绝不按 60 秒轮询）。
        if source.isLowPrecision {
            return WeatherParsing.shouldRefresh(
                isStale: age > Int(ttlSeconds),
                isLowPrecision: true,
                lastLowPrecisionAttempt: lowPrecisionSinceAttemptSeconds(),
                consecutiveFailures: lowPrecisionFailures,
                isForeground: isForeground,
                ignoreLowPrecisionThrottle: ignoreLowPrecisionThrottle
            )
        }

        // 主源数据：30 分钟过期才刷；过期后叠 5 分钟失败节流（一直失败时别每次回前台都打网络）。
        guard age > Int(ttlSeconds) else { return false }
        let sinceAttempt = Int(Date().timeIntervalSince1970 - defaults.double(forKey: Key.attemptAt))
        return sinceAttempt >= Int(failureRetrySeconds)
    }

    /// 距上一次「重试主源」过去了多少秒；从没试过返回 nil。
    private func lowPrecisionSinceAttemptSeconds() -> Int? {
        guard defaults.object(forKey: Key.lowPrecisionAttempt) != nil else { return nil }
        return Int(Date().timeIntervalSince1970 - defaults.double(forKey: Key.lowPrecisionAttempt))
    }

    private func markLowPrecisionAttempt() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lowPrecisionAttempt)
    }

    /// 「重试主源」的连续失败次数（退避档位）。成功一次主源就归零。
    private var lowPrecisionFailures: Int {
        defaults.integer(forKey: Key.lowPrecisionFailures)
    }

    /// 记一次「重试主源」失败：60 → 120 → 300 秒（封顶 5 分钟）。
    private func noteLowPrecisionFailure() {
        let next = min(lowPrecisionFailures + 1, 99)
        defaults.set(next, forKey: Key.lowPrecisionFailures)
    }

    /// 切回主源：把退避与「低精度轮询」的计时一起清掉，回到普通逻辑。
    private func resetLowPrecisionRetry() {
        defaults.set(0, forKey: Key.lowPrecisionFailures)
        // 清掉时间戳：下次真要降级时，第一次重试不必等窗口。
        defaults.removeObject(forKey: Key.lowPrecisionAttempt)
    }

    /// 前后台变化（`AppModel` 按 `scenePhase` 调）：前台才按 60 秒起步的退避轮询主源，
    /// 后台最少隔 10 分钟才试一次。
    func setForeground(_ foreground: Bool) {
        isForeground = foreground
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
