import Foundation

/// 圆盘上**太阳点**的画法：三层 —— 实心核心 + 中心高光 + 外圈柔光。
///
/// 为什么不再和时间轴那个点共用一套（`NowDotStyle`）：时间轴的点画在**橙色渐变卡片**上，
/// 中心 alpha=1 的亮色与底色对比强，读起来是「点 + 光」；太阳点画在**米白卡片**上，
/// 若从圆心就开始渐变（上一版 4pt → 8.8pt），金色在白底上会糊成**一团光斑**。
///
/// 所以太阳点改成三层，边界清楚：
/// 1. **实心核心** `coreRadius`（2.4pt）：纯色、**不渐变**，边界清楚（对白卡 ≥ 3:1）；
/// 2. **中心高光** `highlightRadius`（0.9pt）：核心正中央一个近白暖点，alpha 1.0 —— 「炫」的关键；
/// 3. **外圈柔光**：径向渐变从 **核心半径** 到 `glowRadius`（2.4 → 5.5pt），
///    `glowAlpha`（0.45）→ 0；**起点是核心半径，不是 0**，所以不会盖住核心、也不会从圆心糊开。
///
/// 地平线以下的点不画光：只有一圈描边空心点（半径 = `coreRadius`、`hollowLineWidth`）。
struct SunDotStyle: Equatable {

    /// 实心核心半径（pt）。
    let coreRadius: CGFloat
    /// 中心高光半径（pt）。
    let highlightRadius: CGFloat
    /// 外圈柔光半径（pt）。
    let glowRadius: CGFloat
    /// 外圈柔光的起始 alpha（到 `glowRadius` 收成 0）。
    let glowAlpha: Double
    /// 地平线以下空心圈的描边宽度（pt）。
    let hollowLineWidth: CGFloat

    /// 外圈渐变的**起点半径**：等于核心半径（光从核心边缘开始，不从圆心开始）。
    var glowStartRadius: CGFloat { coreRadius }

    /// 外圈渐变的两档 alpha（location 0 → 1，作用范围是 `coreRadius`…`glowRadius`）。
    var glowGradientStops: [(alpha: Double, location: Double)] {
        [(glowAlpha, 0), (0, 1)]
    }

    /// 唯一实例（UI 与自检共用）。
    static let shared = SunDotStyle(
        coreRadius: 2.4,
        highlightRadius: 0.9,
        glowRadius: 5.5,
        glowAlpha: 0.45,
        hollowLineWidth: 1
    )
}
