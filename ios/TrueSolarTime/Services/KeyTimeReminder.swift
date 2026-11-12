import Foundation
import UserNotifications

/// 「进入关键时间」报时，以及时辰交接的准时提醒。
///
/// iOS 没有 Android 的精确闹钟，只能把未来的触发点逐条排成**本地通知**：
/// - 关键时间段起点：500 ms 的 3200 Hz 蜂鸣（`chime500.wav`），与 Android 一致；
/// - 时辰交接：250 ms（`chime250.wav`），并且是**准时**触发（Android 也改成了准时）。
///
/// 系统对单个应用最多保留 64 条待发通知，所以滚动排未来 5 天，App 回到前台时续排。
final class KeyTimeReminder {

    static let shared = KeyTimeReminder()

    private let center = UNUserNotificationCenter.current()
    private static let keyTimePrefix = "keytime-chime-"
    private static let shichenPrefix = "shichen-chime-"
    private let daysToSchedule = 5

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
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
        if chimeEnabled, let schedule {
            scheduleKeyTime(place: place, schedule: schedule, now: now)
        }
        if shichenEnabled {
            scheduleShichen(place: place, now: now)
        }
    }

    // MARK: - 关键时间

    /// 把未来几天的每个「关键时间段起点」换算成系统时刻，逐条排通知。
    private func scheduleKeyTime(place: Place, schedule: TakeTimeSchedule, now: Date) {
        var index = 0
        for dayOffset in 0..<daysToSchedule {
            guard let dayStart = Calendar.current.date(byAdding: .day, value: dayOffset, to: Calendar.current.startOfDay(for: now)) else { continue }
            for band in schedule.bands {
                // 关键时间按真太阳时给：真太阳时 00:00 对应的系统时刻，可由当天真太阳时的秒数反解。
                guard let fireDate = systemDate(
                    trueSolarMinuteOfDay: Double(band.startMinute),
                    near: dayStart,
                    place: place
                ) else { continue }
                guard fireDate > now.addingTimeInterval(1) else { continue }

                let content = UNMutableNotificationContent()
                content.title = "进入关键时间"
                content.body = String(
                    format: "真太阳时 %@ 起（%@）",
                    band.startText,
                    schedule.temperature?.label ?? "关键时间"
                )
                content.sound = UNNotificationSound(named: UNNotificationSoundName("chime500.wav"))

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(
                    UNNotificationRequest(
                        identifier: "\(Self.keyTimePrefix)\(index)",
                        content: content,
                        trigger: trigger
                    )
                ) { _ in }
                index += 1
            }
        }
    }

    // MARK: - 时辰交接

    private func scheduleShichen(place: Place, now: Date) {
        var cursor = now
        for index in 0..<(daysToSchedule * 12) {
            let boundary = Shichen.nextBoundary(after: cursor.addingTimeInterval(1), longitude: place.longitude)
            cursor = boundary
            guard boundary > now else { continue }

            let boundarySeconds = SolarTimeMath.trueSolarSecondsOfDay(boundary, longitude: place.longitude)
            let name = Shichen.name(Shichen.index(of: boundarySeconds))

            let content = UNMutableNotificationContent()
            content.title = "进入\(name)"
            content.body = "真太阳时 \(TimeOfDay(secondsOfDay: boundarySeconds).clock)"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("chime250.wav"))

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: boundary
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(
                UNNotificationRequest(
                    identifier: "\(Self.shichenPrefix)\(index)",
                    content: content,
                    trigger: trigger
                )
            ) { _ in }
        }
    }

    // MARK: - 真太阳时 → 系统时刻

    /// 求「真太阳时为 `trueSolarMinuteOfDay` 分」对应的系统时刻，落在 `day` 所在的那一天。
    private func systemDate(trueSolarMinuteOfDay: Double, near day: Date, place: Place) -> Date? {
        SolarTimeMath.date(trueSolarMinuteOfDay: trueSolarMinuteOfDay, on: day, longitude: place.longitude)
    }
}
