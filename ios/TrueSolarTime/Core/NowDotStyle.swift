import Foundation

/// 「现在」圆点怎么画 —— 大卡片 0–24 时**时间轴**与大卡片**圆盘上的太阳点**共用这一套。
///
/// 参数取自时间轴那个白点（`HeroCard.HeroAxis`）的**实测值**，不是估的：
/// **实心圆半径 5.5pt** + **柔光圆（半径再外扩 2pt = 7.5pt）0.28 不透明度**，
/// 两笔画法（先柔光、后实心），**不是径向渐变**。
///
/// 为什么放在 Core：颜色（`ThemeColors`）与几何（`SunPathGeometry`）都在 Core，自检才守得住
/// 「圆盘上的太阳点和时间轴那个现在点一样大」。用户反馈「太阳点画太大」正是因为两边各写各的
/// （圆盘是 4pt 实心 + 8.8pt 渐变淡出，时间轴是 5.5pt 实心 + 7.5pt 柔光）——
/// 现在两边读同一组常量，要缩就改这里一个数，**不会再出现一大一小**。
struct NowDotStyle: Equatable {

    /// 核心实心圆半径（pt）。
    let radius: CGFloat
    /// 柔光圆相对核心半径**外扩**多少 pt（`insetBy(dx: -glowInset, dy: -glowInset)`）。
    let glowInset: CGFloat
    /// 柔光圆的不透明度。
    let glowAlpha: Double

    /// 柔光圆半径（pt）。
    var glowRadius: CGFloat { radius + glowInset }
    /// 柔光半径 / 核心半径（时间轴上是 7.5 / 5.5 ≈ 1.36，不是 2×）。
    var glowScale: CGFloat { glowRadius / radius }

    /// 唯一实例：时间轴与太阳点都读它。
    static let shared = NowDotStyle(radius: 5.5, glowInset: 2, glowAlpha: 0.28)
}
