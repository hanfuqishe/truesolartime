import Foundation

/// 抓取「西格瑪食療」页面上的「服用時間 Take Time」（关键时间）。
///
/// 策略与 Android `TakeTimeRepository` 一致：每天在 01:00–05:00 之间挑一个随机时刻同步一次，
/// 失败隔一小时重试；成功的结果连时间戳缓存 7 天，过期就不着色。
///
/// 与 Android 的差异都是「更不容易静默失败」的方向：
/// - 抓取失败**当场重试一次**（Android 被小组件每分钟轮询兜底，iOS 没有后台刷新，只能自己补）；
/// - `waitsForConnectivity`：冷启动/切网瞬间先等网络再发请求，而不是立刻报「离线」；
/// - 手上没有可用数据时**跳过随机窗口**立刻抓一次（否则只在凌晨打开过 app 的用户永远拿不到）；
/// - 每次抓取的 HTTP 状态 / 字节数 / 段数 / 失败原因都记下来，设置页「诊断」可见。
final class KeyTimeStore {

    static let shared = KeyTimeStore()

    private enum Key {
        static let bands = "keytime.bands"
        static let temperature = "keytime.temperature"
        static let fetchedAt = "keytime.fetched_at"
        static let attemptAt = "keytime.attempt_at"
        static let targetAt = "keytime.target_at"
        static let targetDay = "keytime.target_day"
        static let successDay = "keytime.success_day"
    }

    private let defaults = UserDefaults.standard
    private var inFlight = false

    /// 抓取用的会话：允许等网络；不用 URL 缓存（页面只有几 KB，改版后必须拿到新内容）。
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    // MARK: - 诊断（设置 → 诊断 → 关键时间）

    /// 最近一次抓取的结果描述，例如「成功：3 段 · 冻或温（HTTP 200）」「网络错误（-1009）」。
    private(set) var lastOutcome: String = L("keytime.st.never")
    private(set) var lastAttemptAt: Date?
    private(set) var lastSuccessAt: Date?
    private(set) var lastHTTPStatus: Int?
    private(set) var lastByteCount: Int?

    private init() {}

    /// 缓存里的关键时间；超过 7 天或从未抓到时返回 nil。
    func schedule() -> TakeTimeSchedule? {
        guard let bands = TakeTimeParsing.decodeBands(defaults.string(forKey: Key.bands)) else { return nil }
        let fetchedAt = defaults.double(forKey: Key.fetchedAt)
        let age = Date().timeIntervalSince1970 - fetchedAt
        guard age >= 0, age <= TakeTimeParsing.validSeconds else { return nil }
        let temperature = TakeTemperature.fromStorageKey(defaults.string(forKey: Key.temperature))
        return TakeTimeSchedule(bands: bands, temperature: temperature)
    }

    /// 需要且允许时联网刷新一次；成功后在主线程回调。
    ///
    /// - Parameter force: 忽略「今天已同步 / 随机窗口 / 失败节流」的判定，立刻抓一次（设置页「立即同步」）。
    func requestRefresh(force: Bool = false, completion: ((TakeTimeSchedule) -> Void)? = nil) {
        guard !inFlight else { return }
        let now = Date()
        guard force || shouldSyncNow(now) else { return }
        fetch(attempt: 1, now: now, completion: completion)
    }

    /// 设置页的「立即同步关键时间」：诊断用，绕过节流。
    func refreshNow(completion: ((TakeTimeSchedule) -> Void)? = nil) {
        requestRefresh(force: true, completion: completion)
    }

    // MARK: - 抓取

    private func fetch(attempt: Int, now: Date, completion: ((TakeTimeSchedule) -> Void)?) {
        inFlight = true
        if attempt == 1 {
            lastAttemptAt = now
            lastHTTPStatus = nil
            lastByteCount = nil
            defaults.set(now.timeIntervalSince1970, forKey: Key.attemptAt)
        }

        var request = URLRequest(url: TakeTimeParsing.pageURL)
        request.timeoutInterval = 25
        // UA 要能标识自己（便于对方站点识别）；同时带浏览器常见的头，减少被当成爬虫挡掉的机会。
        request.setValue(
            "TrueSolarTime-iOS/1.4.39 (com.realsuntime.solartime)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode
            let byteCount = data?.count
            let schedule = data
                .flatMap { TakeTimeParsing.decodeHTML($0) }
                .flatMap { TakeTimeParsing.parse(html: $0) }

            if let schedule {
                self.inFlight = false
                DispatchQueue.main.async {
                    self.lastHTTPStatus = status
                    self.lastByteCount = byteCount
                    self.lastSuccessAt = Date()
                    var outcome = Lf("keytime.out.successBands", schedule.bands.count)
                    if let temperature = schedule.temperature {
                        outcome += " · \(temperature.label)"
                    } else {
                        outcome += " · \(L("keytime.temperatureUnknown"))"
                    }
                    if let status { outcome += Lf("keytime.out.httpParen", status) }
                    self.lastOutcome = outcome
                    self.save(schedule)
                    completion?(schedule)
                }
                return
            }

            let reason: String
            if let error {
                let ns = error as NSError
                reason = Lf("diag.networkError", ns.domain, ns.code)
            } else if let status, !(200..<300).contains(status) {
                reason = "HTTP \(status)"
            } else if let data, TakeTimeParsing.decodeHTML(data) == nil {
                reason = Lf("keytime.out.decodeFailed", byteCount ?? 0)
            } else {
                reason = Lf("keytime.out.noKeyTime", byteCount ?? 0)
            }

            if attempt < 2 {
                // 第一次失败：3 秒后再试一次（冷启动/切网的第一请求经常失败）。
                DispatchQueue.main.async {
                    self.lastOutcome = Lf("keytime.out.retrying", reason)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    self.fetch(attempt: attempt + 1, now: Date(), completion: completion)
                }
                return
            }

            self.inFlight = false
            DispatchQueue.main.async {
                self.lastHTTPStatus = status
                self.lastByteCount = byteCount
                self.lastOutcome = Lf("keytime.out.retryHour", reason)
            }
        }.resume()
    }

    // MARK: - 同步时机

    /// 今天是否该联网同步。
    ///
    /// 与 Android `TakeTimeRepository.shouldSync` 等价：今天已成功就跳过；目标时刻没到也跳过；
    /// 失败后一小时重试一次。多一条兜底：**手上没有任何可用数据时立刻抓**（不看随机窗口），
    /// 因为 iOS 没有后台轮询，错过了凌晨那次就再也没有机会。
    private func shouldSyncNow(_ now: Date) -> Bool {
        // 失败过了就等一小时再试。
        let attemptAt = defaults.double(forKey: Key.attemptAt)
        if attemptAt > 0, now.timeIntervalSince1970 - attemptAt < TakeTimeParsing.retrySeconds {
            return false
        }
        // 今天已经成功同步过。
        let today = dayKey(now)
        if defaults.string(forKey: Key.successDay) == today { return false }
        // 没有任何可用数据（首次安装 / 缓存已过期）：立刻抓一次。
        if schedule() == nil { return true }
        // 当天 01:00–05:00 之间挑一个随机时刻，到点才同步。
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        var target = defaults.double(forKey: Key.targetAt)
        if defaults.string(forKey: Key.targetDay) != today || target <= 0 {
            let offsetMinutes = Int.random(
                in: TakeTimeParsing.syncWindowStartMinute..<TakeTimeParsing.syncWindowEndMinute
            )
            target = startOfDay.addingTimeInterval(TimeInterval(offsetMinutes * 60)).timeIntervalSince1970
            defaults.set(target, forKey: Key.targetAt)
            defaults.set(today, forKey: Key.targetDay)
        }
        return now.timeIntervalSince1970 >= target
    }

    private func save(_ schedule: TakeTimeSchedule) {
        defaults.set(TakeTimeParsing.encodeBands(schedule.bands), forKey: Key.bands)
        if let temperature = schedule.temperature {
            // 与 Android 用同一套值（cold / hot），旧版本存的 rawValue 也读得出来。
            defaults.set(temperature.storageKey, forKey: Key.temperature)
        } else {
            defaults.removeObject(forKey: Key.temperature)
        }
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: Key.fetchedAt)
        defaults.set(dayKey(now), forKey: Key.successDay)
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - 诊断

    /// 一行（可换行）的状态说明，设置页「诊断 → 关键时间」直接用。
    func diagnosticsSummary() -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("MMddHHmm")
        var parts: [String] = []
        if let schedule = schedule() {
            let bands = schedule.bands.map(\.text).joined(separator: L("list.separator"))
            parts.append(Lf("keytime.st.bands", schedule.bands.count, bands))
            parts.append(Lf("keytime.st.temperature", schedule.temperature?.label ?? L("keytime.temperatureUnknown")))
        } else {
            parts.append(L("keytime.st.none"))
        }
        let lastSuccess = lastSuccessAt.map { formatter.string(from: $0) } ?? L("keytime.st.neverShort")
        parts.append(Lf("keytime.st.lastSuccess", lastSuccess))
        if let lastAttemptAt {
            parts.append(Lf("keytime.st.lastAttempt", formatter.string(from: lastAttemptAt)))
        }
        if let status = lastHTTPStatus {
            parts.append(Lf("keytime.st.http", status))
        }
        if let bytes = lastByteCount {
            parts.append(Lf("keytime.st.bytes", bytes))
        }
        parts.append(Lf("keytime.st.result", lastOutcome))
        return parts.joined(separator: " · ")
    }
}
