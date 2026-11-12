import Foundation

/// 抓取「西格瑪食療」页面上的「服用時間 Take Time」（关键时间）。
///
/// 与 Android 版同样的策略：每天只在 01:00–05:00 之间挑一个随机时刻同步一次，
/// 失败隔一小时重试；成功的结果连时间戳一起缓存 7 天，过期就不再着色。
final class KeyTimeStore {

    static let shared = KeyTimeStore()

    private enum Key {
        static let bands = "keytime.bands"
        static let temperature = "keytime.temperature"
        static let fetchedAt = "keytime.fetched_at"
        static let attemptAt = "keytime.attempt_at"
        static let targetAt = "keytime.target_at"
        static let targetDay = "keytime.target_day"
    }

    private let defaults = UserDefaults.standard
    private var inFlight = false

    private init() {}

    /// 缓存里的关键时间；超过 7 天或从未抓到时返回 nil。
    func schedule() -> TakeTimeSchedule? {
        guard let bands = TakeTimeParsing.decodeBands(defaults.string(forKey: Key.bands)) else { return nil }
        let fetchedAt = defaults.double(forKey: Key.fetchedAt)
        let age = Date().timeIntervalSince1970 - fetchedAt
        guard age >= 0, age <= TakeTimeParsing.validSeconds else { return nil }
        let temperature = defaults.string(forKey: Key.temperature).flatMap(TakeTemperature.init(rawValue:))
        return TakeTimeSchedule(bands: bands, temperature: temperature)
    }

    /// 需要且允许时联网刷新一次；成功后在主线程回调。
    func requestRefresh(force: Bool = false, completion: ((TakeTimeSchedule) -> Void)? = nil) {
        guard !inFlight else { return }
        let now = Date()
        guard force || shouldSyncNow(now) else { return }

        inFlight = true
        defaults.set(now.timeIntervalSince1970, forKey: Key.attemptAt)

        var request = URLRequest(url: TakeTimeParsing.pageURL)
        request.timeoutInterval = 15
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            defer { self.inFlight = false }
            guard let data, let html = String(data: data, encoding: .utf8),
                  let schedule = TakeTimeParsing.parse(html: html) else { return }
            DispatchQueue.main.async {
                self.save(schedule)
                completion?(schedule)
            }
        }.resume()
    }

    private func shouldSyncNow(_ now: Date) -> Bool {
        // 失败过了就等一小时再试。
        let attemptAt = defaults.double(forKey: Key.attemptAt)
        if attemptAt > 0, now.timeIntervalSince1970 - attemptAt < TakeTimeParsing.retrySeconds {
            return false
        }
        // 已经有今天取到的数据就不用再取。
        let today = dayKey(now)
        if defaults.string(forKey: Key.targetDay) == today,
           let fetchedAt = Optional(defaults.double(forKey: Key.fetchedAt)),
           dayKey(Date(timeIntervalSince1970: fetchedAt)) == today {
            return false
        }
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
            defaults.set(temperature.rawValue, forKey: Key.temperature)
        } else {
            defaults.removeObject(forKey: Key.temperature)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Key.fetchedAt)
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
