import Foundation

/// 「连续点击版本号 7 次」才显示诊断区块的判定逻辑。
///
/// 纯逻辑（没有 SwiftUI、没有持久化），便于自检：
/// - 必须**连击 7 次**才算解锁；
/// - 相邻两次点击的间隔超过 [maxInterval] 秒就从头数；
/// - 只负责「这一次点击是否刚好凑满 7 次」，显示开关本身由 `AppModel` 持有
///   （`@Published showDiagnostics`，不写 UserDefaults，重启即回到隐藏）。
struct DiagnosticsUnlock {

    /// 需要连击的次数。
    static let requiredTaps = 7

    /// 相邻两次点击允许的最大间隔（秒）；超过就重置计数。
    static let maxInterval: TimeInterval = 2

    /// 当前已经连击了几次（0…requiredTaps）。
    private(set) var taps = 0

    /// 上一次点击的时刻。
    private var lastTapAt: Date?

    /// 记录一次点击。刚好凑满 [requiredTaps] 次时返回 true，并把计数清零。
    mutating func register(at now: Date = Date()) -> Bool {
        if let lastTapAt, now.timeIntervalSince(lastTapAt) > Self.maxInterval {
            taps = 0
        }
        lastTapAt = now
        taps += 1
        guard taps >= Self.requiredTaps else { return false }
        taps = 0
        return true
    }
}
