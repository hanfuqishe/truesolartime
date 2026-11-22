import SwiftUI
import UserNotifications

@main
struct TrueSolarTimeApp: App {

    init() {
        // 必须在任何通知到达之前挂上代理：否则 App 在前台时系统会**静默吞掉**本地通知，
        // 报时（进入关键时间 / 时辰交接）就一声也听不见。
        // 具体策略见 NotificationPresenter：前台只出声，不弹横幅。
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
