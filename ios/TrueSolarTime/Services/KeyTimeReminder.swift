import Foundation
import UserNotifications

/// 「进入关键时间」报时，以及时辰交接的准时提醒。
///
/// iOS 没有 Android 的精确闹钟，只能把未来的触发点逐条排成**本地通知**：
/// - 关键时间段起点：500 ms 的 3200 Hz 蜂鸣（`chime500.wav`），与 Android 一致；
/// - 时辰交接：100 ms（`chime100.wav`），并且是**准时**触发（Android 也改成了准时）。
///
/// 两个必须注意的系统限制：
/// 1. 单个 App **最多保留 64 条**待发通知，超出的部分 `add` 会失败。
///    以前时辰交接一天排 12 条 × 5 天 = 60 条，关键时间再排 30 条，合计 90 条 ——
///    超出上限的那部分被系统直接丢掉，表现为「有些提醒从来不响」。
///    现在统一**按时间先后取最近的 60 条**：越近的越重要，远期的下次回到前台再续排。
/// 2. App 在前台时系统默认**不展示也不发声**，必须实现 `willPresent`（见 `NotificationPresenter`）。
final class KeyTimeReminder {

    static let shared = KeyTimeReminder()

    private let center = UNUserNotificationCenter.current()
    private static let keyTimePrefix = "keytime-chime-"
    private static let shichenPrefix = "shichen-chime-"
    private let daysToSchedule = 5

    /// 系统上限 64，留 4 条余量：将来加别的通知也不至于被挤掉。
    private static let maxPending = 60

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// 当前的通知授权状态（设置页用：被拒时提示用户去系统里打开）。
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func clearAll() {
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.keyTimePrefix) || $0.hasPrefix(Self.shichenPrefix) }
            guard !identifiers.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    /// 只清关键时间那部分（关掉开关时用）。
    func clearKeyTime() {
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(Self.keyTimePrefix) }
            guard !identifiers.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    /// 一条排好队的提醒。先收集、再统一排序裁剪，避免「先排的把后排的挤出 64 条上限」。
    private struct Candidate {
        let fireDate: Date
        let identifier: String
        let content: UNMutableNotificationContent
    }

    /// 重排全部提醒。
    ///
    /// - Parameters:
    ///   - place: 当前地点（关键时间按**真太阳时**给，换算成系统时刻要经度）
    ///   - schedule: 关键时间；为空时只排时辰交接
    ///   - chimeEnabled: 是否排「进入关键时间」的报时
    ///   - shichenEnabled: 是否排时辰交接提醒
    func reschedule(
        place: Place,
        schedule: TakeTimeSchedule?,
        chimeEnabled: Bool,
        shichenEnabled: Bool,
        from now: Date = Date()
    ) {
        clearAll()
        var candidates: [Candidate] = []
        if chimeEnabled, let schedule {
            candidates += keyTimeCandidates(place: place, schedule: schedule, now: now)
        }
        if shichenEnabled {
            candidates += shichenCandidates(place: place, now: now)
        }
        // 按时间先后取最近的若干条：越近的越重要；远期会在下次回到前台时续排。
        let chosen = candidates
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.maxPending)
        for candidate in chosen {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: candidate.fireDate
            )
            center.add(
                UNNotificationRequest(
                    identifier: candidate.identifier,
                    content: candidate.content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            ) { error in
                // 超限或权限被撤时这里才有 error；静默失败的代价是「提醒不响」，留一条日志值。
                if let error {
                    NSLog("KeyTimeReminder: add \(candidate.identifier) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 关键时间

    /// 未来几天里每个「关键时间段起点」对应的通知。
    private func keyTimeCandidates(
        place: Place,
        schedule: TakeTimeSchedule,
        now: Date
    ) -> [Candidate] {
        var result: [Candidate] = []
        var index = 0
        let startOfToday = Calendar.current.startOfDay(for: now)
        for dayOffset in 0..<daysToSchedule {
            guard let dayStart = Calendar.current.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            for band in schedule.bands {
                // 关键时间按真太阳时给：真太阳时 00:00 对应的系统时刻，可由当天真太阳时的秒数反解。
                guard let fireDate = systemDate(
                    trueSolarMinuteOfDay: Double(band.startMinute),
                    near: dayStart,
                    place: place
                ) else { continue }
                guard fireDate > now.addingTimeInterval(1) else { continue }

                let content = UNMutableNotificationContent()
                content.title = L("keytime.notifyTitle")
                content.body = Lf(
                    "keytime.notifyBody",
                    band.startText,
                    schedule.temperature?.label ?? L("keytime.title")
                )
                content.sound = UNNotificationSound(named: UNNotificationSoundName("chime500.wav"))

                result.append(
                    Candidate(
                        fireDate: fireDate,
                        identifier: "\(Self.keyTimePrefix)\(index)",
                        content: content
                    )
                )
                index += 1
            }
        }
        return result
    }

    // MARK: - 时辰交接

    private func shichenCandidates(place: Place, now: Date) -> [Candidate] {
        var result: [Candidate] = []
        var cursor = now
        for index in 0..<(daysToSchedule * 12) {
            let boundary = Shichen.nextBoundary(after: cursor.addingTimeInterval(1), longitude: place.longitude)
            cursor = boundary
            guard boundary > now else { continue }

            let boundarySeconds = SolarTimeMath.trueSolarSecondsOfDay(boundary, longitude: place.longitude)
            let name = Shichen.name(Shichen.index(of: boundarySeconds))

            let content = UNMutableNotificationContent()
            content.title = Lf("shichen.notifyTitle", name)
            content.body = Lf("shichen.notifyBody", TimeOfDay(secondsOfDay: boundarySeconds).clock)
            content.sound = UNNotificationSound(named: UNNotificationSoundName("chime100.wav"))

            result.append(
                Candidate(
                    fireDate: boundary,
                    identifier: "\(Self.shichenPrefix)\(index)",
                    content: content
                )
            )
        }
        return result
    }

    // MARK: - 真太阳时 → 系统时刻

    /// 求「真太阳时为 `trueSolarMinuteOfDay` 分」对应的系统时刻，落在 `day` 所在的那一天。
    private func systemDate(trueSolarMinuteOfDay: Double, near day: Date, place: Place) -> Date? {
        SolarTimeMath.date(
            trueSolarMinuteOfDay: trueSolarMinuteOfDay,
            on: day,
            longitude: place.longitude,
            offsetSeconds: place.standardOffsetSeconds
        )
    }
}
