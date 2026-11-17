import Foundation

/// 「现在」圆点怎么画 —— 大卡片 0–24 时**时间轴**与大卡片**圆盘上的太阳点**共用这一套。
///
/// 画法：**三层同心圆，从外往里画**（后画的一层盖住前一层），三层同一个颜色，只有半径与 alpha 不同：
///
/// | 层 | 半径 | alpha | 视觉 |
/// |---|---|---|---|
/// | ③ 外圈 | 核心 + 2pt（7.5pt） | **0.45** | 淡光 |
/// | ② 中间层 | 核心 + 1pt（6.5pt） | **0.55** | 半透过渡 |
/// | ① 核心 | 核心半径（5.5pt） | **1.0** | 完全不透明 |
///
/// 为什么要加中间层：原来只有「实心 + 0.28 柔光」两笔，核心边缘之外**立刻**掉到 0.28 ——
/// 边缘一大片都太淡，亮金画在米白卡片上就散成「一团光斑」。加上 0.55 的中间层后，
/// 落差从 1.0 → 0.28（Δ0.72）变成 1.0 → 0.55 → 0.45（Δ0.45 / Δ0.10），边缘才「实」。
///
/// 参数放在 Core：颜色（`ThemeColors`）与几何（`SunPathGeometry`）都在 Core，自检才守得住
/// 「圆盘太阳点与时间轴那个点读同一组常量、一起变」。
struct NowDotStyle: Equatable {

    /// 核心实心圆半径（pt）——**这一圈内完全不透明**。
    let radius: CGFloat
    /// 中间层相对核心半径外扩多少 pt。
    let midInset: CGFloat
    /// 外圈相对核心半径外扩多少 pt。
    let glowInset: CGFloat
    /// 中间层不透明度。
    let midAlpha: Double
    /// 外圈不透明度。
    let glowAlpha: Double

    /// 中间层半径（pt）。
    var midRadius: CGFloat { radius + midInset }
    /// 外圈半径（pt）。
    var glowRadius: CGFloat { radius + glowInset }

    /// 三层透明度表（从核心往外）：`(外扩 pt, alpha)`。
    ///
    /// 第一项就是核心：外扩 0、alpha **1.0** —— UI 按它从后往前画，所以核心半径处完全不透明。
    var alphaRamp: [(inset: CGFloat, alpha: Double)] {
        [(0, 1), (midInset, midAlpha), (glowInset, glowAlpha)]
    }

    /// 唯一实例：时间轴与太阳点都读它（要改就改这里，两边一起变）。
    static let shared = NowDotStyle(
        radius: 5.5,
        midInset: 1,
        glowInset: 2,
        midAlpha: 0.55,
        glowAlpha: 0.45
    )
}
