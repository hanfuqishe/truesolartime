import Foundation
import UserNotifications

/// 前台的通知展示策略。
///
/// iOS 的默认行为是：**App 处于前台时不展示、也不发声**任何本地通知。
/// 我们的报时（进入关键时间 / 时辰交接）完全依赖本地通知，
/// 于是「开着 App 等报时」就一声也听不到 —— 用户反馈的「苹果的报时根本没有响」大半来自这里。
///
/// 这里只保留 `.sound`：前台**只出声、不弹横幅、不写通知中心**。
/// 提醒本身就是一声蜂鸣，不该在界面上多一条横幅；这也与 Android 端「报时不发通知、只播提示音」一致。
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    private override init() {
        super.init()
    }

    /// 前台收到通知：只播放声音。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.sound]
    }
}
