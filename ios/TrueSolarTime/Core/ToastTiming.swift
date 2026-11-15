import Foundation

/// 非阻塞 Toast 的时长常量（纯常量，便于自检断言「1.5~2 秒」这条要求）。
///
/// 视图实现在 `UI/Toast.swift`；这里只放数值，因为 `Scripts/main.swift` 的自检只编译
/// `Core/`，放在这里才能被断言守住。
enum ToastTiming {

    /// 浮层停留时长（秒）：用户要求 1.5~2 秒。
    static let duration: TimeInterval = 1.8

    /// 淡入淡出时长（秒）。
    static let fade: TimeInterval = 0.22
}
