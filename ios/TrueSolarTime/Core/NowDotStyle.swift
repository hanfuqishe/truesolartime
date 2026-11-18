import Foundation

/// 时间轴上「现在」那个圆点的画法：**一个径向渐变圆**（与 Android 完全一致）。
///
/// | 项 | 值 |
/// |---|---|
/// | 半径 | **5.5pt** |
/// | 色标位置 | **0 / 0.5 / 1** |
/// | alpha | **1.0 / 0.45 / 0**（同色） |
///
/// 以前是「5.5pt 实心 + 外扩 2pt 的平铺柔光」两笔：外圈是一层半透明实心环，看着硬，
/// 整体视觉尺寸也偏大（到 7.5pt）。Android 用一个渐变圆 —— 边缘从 0.45 快速收到 0，
/// 视觉核心只有约 2.75pt，所以显得更小更柔。iOS 现在与它相同。
///
/// 圆盘上的太阳点**不用这套参数**（它仍是「实心核心 + 独立渐变光晕」，见 `SunHaloStyle`）。
struct NowDotStyle: Equatable {

    /// 圆点半径（渐变圆的外沿）。
    let radius: CGFloat

    /// 三档 alpha（对应 location 0 / 0.5 / 1）。第一档不透明：圆心是实心的。
    let alphas: [Double]

    /// 色标位置（与 `alphas` 一一对应）。
    let stops: [Double]

    /// 唯一实例。
    static let shared = NowDotStyle(radius: 5.5, alphas: [1.0, 0.45, 0.0], stops: [0, 0.5, 1])
}
