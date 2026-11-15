import SwiftUI
import UIKit

/// 非阻塞的轻量提示（Toast）。
///
/// 只用于**告知**类消息（已跟随 GPS、没有定位权限、通知没开……）：半透明胶囊浮在底部，
/// 1.8 秒自动淡出，**不拦点击**（`allowsHitTesting(false)`，触摸直接穿透到下面的按钮/列表），
/// 也不需要点「确定」。
///
/// 需要用户做决定的确认框（`UIAlertController` 那类模态）在本 App 里一律不用：
/// 现有的提示都是纯告知，用模态会打断操作 —— 所以 `ContentView` 里原来那个
/// 「提示 / 好」的弹窗已经删掉，改由这里接管。
struct ToastModifier: ViewModifier {

    /// 浮层停留时长（秒）：用户要求 1.5~2 秒。数值在 `Core/ToastTiming.swift`（自检断言它在范围内）。
    static let duration: TimeInterval = ToastTiming.duration

    /// 淡入淡出时长（秒）。
    static let fade: TimeInterval = ToastTiming.fade

    @Binding var message: String?

    /// 待触发的自动消失任务（来新消息时取消上一个）。
    @State private var pending: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) { bubble }
            .animation(.easeInOut(duration: Self.fade), value: message)
            .onChange(of: message) { value in
                guard let value, !value.isEmpty else { return }
                // 浮层本身对 VoiceOver 隐藏（避免与下方内容抢焦点），改用一次性播报，
                // 这样「已跟随 GPS」这类消息读屏用户也能听到（原来的弹窗本来会被朗读）。
                UIAccessibility.post(notification: .announcement, argument: value)
                scheduleDismiss(value)
            }
    }

    @ViewBuilder
    private var bubble: some View {
        if let message, !message.isEmpty {
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.62))
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .transition(.opacity)
                // 关键：浮层不接收触摸，下面的按钮与滚动照常可用。
                .allowsHitTesting(false)
                // 纯视觉提示，不参与朗读顺序（消息本身本来就是补充信息）。
                .accessibilityHidden(true)
        }
    }

    /// 到点自动清空；期间又来了新消息就不清（对比文本），避免「新消息一闪就没」。
    private func scheduleDismiss(_ text: String) {
        pending?.cancel()
        let binding = $message
        let work = DispatchWorkItem {
            if binding.wrappedValue == text {
                binding.wrappedValue = nil
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }
}

extension View {

    /// 挂一个非阻塞 Toast：`model.message` 一有值就浮出来，1.8 秒后自动消失。
    ///
    /// 主界面与设置页各挂一次：设置页是 sheet，盖住主界面时那边的 Toast 会被挡住，
    /// 所以「通知权限没开」这类在设置页里产生的消息要有自己的那一份。
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
