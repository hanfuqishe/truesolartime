import Foundation

/// 圆盘太阳点怎么画：**小实心核心 + 径向渐变柔光**（两笔，核心画在光晕之后）。
///
/// | 层 | 半径 | 画法 |
/// |---|---|---|
/// | 实心核心 | **2.75pt**（= 时间轴那个点 5.5pt 的一半） | 纯色 `#D9AC1C` / 夜间 `#F5D68A`，alpha 1.0 |
/// | 柔光 | **2.75 → 5.5pt** | 同色径向渐变，alpha **0.35 → 0** |
///
/// 为什么核心只有一半：真机上「5.5pt 核心 + 外扩 2pt 的平铺柔光」看起来点偏大、而且外圈是
/// 一层半透明实心环 —— 是硬边、没有渐变。现在整体直径 11pt（原 15pt），外面从核心边缘
/// （**startRadius = 核心半径，不是 0**）一路渐隐到 5.5pt，才有真正的「柔光」。
///
/// 时间轴上的「现在」圆点**故意不同**（`NowDotStyle`：一个 5.5pt 径向渐变圆，alpha 1 / 0.45 / 0）——
/// 那个点画在橙色卡片上，尺寸与画法都保持原样，不要跟着改。
struct SunHaloStyle: Equatable {

    /// 太阳点实心核心半径：时间轴「现在」圆点核心的一半。
    static let coreRadius: CGFloat = 2.75

    /// 柔光起点的 alpha（到 `endRadius` 收成 0）。
    let alpha: Double

    /// 柔光渐变起点半径 = **核心半径**（不是 0）：光只从核心外面开始，核心本身不被冲淡。
    var startRadius: CGFloat { Self.coreRadius }
    /// 柔光渐变外沿半径 = 核心的 2 倍（5.5pt）：整体直径 11pt。
    var endRadius: CGFloat { Self.coreRadius * 2 }

    /// 渐变的两档 alpha（location 0 → 1，作用范围是 `startRadius`…`endRadius`）。
    var stops: [(alpha: Double, location: Double)] {
        [(alpha, 0), (0, 1)]
    }

    /// 唯一实例。
    static let shared = SunHaloStyle(alpha: 0.35)
}
