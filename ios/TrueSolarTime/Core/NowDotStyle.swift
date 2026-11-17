import Foundation

/// 时间轴「现在」圆点怎么画 —— **两笔**：实心圆 + 单层柔光圆。
///
/// | 层 | 半径 | alpha |
/// |---|---|---|
/// | 柔光圆 | 核心 + `glowInset`(2pt) = **7.5pt** | **0.28** |
/// | 实心圆 | **5.5pt** | 1.0（完全不透明） |
///
/// 这是时间轴最初的样子（用户明确要求回到这个版本）。中间那层 0.55 与「三次 fill 的 alphaRamp」
/// 已经删掉 —— 时间轴的点在橙色卡上用深色画，加中间层反而糊。
///
/// 圆盘上的太阳点**尺寸**与它一致（核心半径 = `radius`、整体外沿 = `glowRadius`），
/// 但光晕是**独立的径向渐变**（见 `SunHaloStyle`），不是这个 0.28 的平铺柔光圆：
/// 亮金画在米白卡片上，平铺的柔光圆会散成一团光斑，渐变收边才不散。
struct NowDotStyle: Equatable {

    /// 核心实心圆半径（pt）——这一圈内完全不透明。
    let radius: CGFloat
    /// 柔光圆相对核心半径外扩多少 pt。
    let glowInset: CGFloat
    /// 柔光圆的不透明度。
    let glowAlpha: Double

    /// 柔光圆半径（pt）。
    var glowRadius: CGFloat { radius + glowInset }

    /// 唯一实例：时间轴用它；太阳点的核心半径 / 整体外沿也取它（保证视觉大小一致）。
    static let shared = NowDotStyle(radius: 5.5, glowInset: 2, glowAlpha: 0.28)
}
