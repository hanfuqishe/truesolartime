import Foundation

/// 圆盘太阳点的**光晕**怎么画：独立的一圈径向渐变（画在核心之前）。
///
/// | 项 | 值 | 说明 |
/// |---|---|---|
/// | 起点半径 | **5.5pt** = `NowDotStyle.radius` | 从核心边缘开始，**不从圆心**开始 |
/// | 外沿半径 | **7.5pt** = `NowDotStyle.glowRadius` | 与时间轴柔光圆同外沿 ⇒ 整体直径一致 |
/// | alpha | **0.35 → 0** | 线性收到透明 |
///
/// 为什么和时间轴的柔光（平铺 0.28 一层）不一样：时间轴的点画在橙色卡片上、用深色，
/// 平铺柔光就够；太阳点是**亮金画在米白卡片**上，平铺 0.28 会在核心外面糊成一大片淡雾，
/// 所以改用「从核心半径起、0.35 收到 0」的渐变 —— 核心边界干净，柔光只在外面薄薄一层。
///
/// 尺寸仍与时间轴共用（`NowDotStyle`），所以「太阳点整体直径 ≈ 时间轴圆点」这个关系不变。
struct SunHaloStyle: Equatable {

    /// 光晕起点的 alpha（到 `endRadius` 收成 0）。
    let alpha: Double

    /// 光晕起点半径 = 核心半径。
    var startRadius: CGFloat { NowDotStyle.shared.radius }
    /// 光晕外沿半径 = 时间轴柔光圆半径。
    var endRadius: CGFloat { NowDotStyle.shared.glowRadius }

    /// 渐变的两档 alpha（location 0 → 1，作用范围是 `startRadius`…`endRadius`）。
    var stops: [(alpha: Double, location: Double)] {
        [(alpha, 0), (0, 1)]
    }

    /// 唯一实例。
    static let shared = SunHaloStyle(alpha: 0.35)
}
