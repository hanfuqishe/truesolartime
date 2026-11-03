import Foundation
import UserNotifications

/// 时辰交接提醒。
///
/// iOS 没有 Android 那种可任意定时的闹钟，只能在申请时把未来若干时辰边界
/// 逐条排成定时通知；系统对单个应用最多保留 64 条待发通知，
/// 因此每次滚动排 5 天（60 条），App 回到前台时再续排。
final class ShichenReminder {

    static let shared = ShichenReminder()

    private let center = UNUserNotificationCenter.current()
    private static let identifierPrefix = "shichen-boundary-"
    private let leadSeconds: TimeInterval = 300
    private let daysToSchedule = 5

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func clearPending() {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map { $0.identifier }.filter { $0.hasPrefix(Self.identifierPrefix) }
            guard !identifiers.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func reschedule(place: Place, from now: Date = Date()) {
        clearPending()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        var cursor = now
        let limit = daysToSchedule * 12

        for index in 0..<limit {
            // +1 秒避免恰好在边界上反复取到同一条边界。
            let boundary = Shichen.nextBoundary(after: cursor.addingTimeInterval(1), longitude: place.longitude)
            let fireDate = boundary.addingTimeInterval(-leadSeconds)
            cursor = boundary

            guard fireDate > now else { continue }

            let boundarySeconds = SolarTimeMath.trueSolarSecondsOfDay(boundary, longitude: place.longitude)
            let shichenName = Shichen.name(Shichen.index(of: boundarySeconds))
            let boundaryTime = TimeOfDay(secondsOfDay: boundarySeconds).clockWithSeconds

            let content = UNMutableNotificationContent()
            content.title = "即将进入\(shichenName)"
            content.body = "约 5 分钟后（真太阳时 \(boundaryTime)）"
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(Self.identifierPrefix)\(index)",
                content: content,
                trigger: trigger
            )
            center.add(request) { _ in }
        }
    }
}