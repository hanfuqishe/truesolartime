import Foundation

/// 空白瓦片的像素判定（与 Android 同一套算法，纯函数、可自检）。
///
/// 为什么需要它：高德对境外很多区域会返回 **HTTP 200 的空白瓦片**（灰底 + 水印、没有地理内容），
/// 只看状态码永远不会发现「这一屏其实是空的」，也就不会触发降级。
///
/// 算法（与 Android 对齐）：
/// 1. 采样：256×256 → **32×32**（步长 8、最近邻，不插值）—— 由 UI 侧解码时用最近邻缩放完成；
/// 2. 颜色量化：每通道取**高 4 位**，统计颜色种类；
/// 3. 方差：三通道方差均值（0…65025）；
/// 4. 空白 = `!海洋 && (方差 < 12 || (颜色种类 < 8 && 方差 < 400))`；
/// 5. 海洋豁免：色相 185–265°、饱和 ≥ 0.22、亮度 ≥ 60 的像素占 ≥ 60% → 视为**海面**（不是空白），
///    否则「纯蓝的海图」会被当成空白瓦片。
///
/// 「整屏判据」不在这里，由 `BasemapState.closeScreenBatch` 负责：
/// 一屏里**所有**看过的瓦片都空白才算这一屏空白（避免误伤撒哈拉、冰原这类纯色的**真**瓦片）。
struct BlankTileAnalysis: Equatable {

    /// 采样后的边长（32×32 = 1024 个样本）。
    static let sampleSide = 32
    /// 原始瓦片边长（256，步长 8）。
    static let sourceSide = 256

    /// 判定阈值（集中放这里，自检直接钉边界值）。
    static let minVariance: Double = 12
    static let manyColors: Int = 8
    static let mixedVariance: Double = 400
    static let oceanHueRange: ClosedRange<Double> = 185...265
    static let oceanMinSaturation: Double = 0.22
    static let oceanMinLightness: Double = 60
    static let oceanMinRatio: Double = 0.6

    let isBlank: Bool
    /// 量化到高 4 位之后的颜色种类数。
    let distinctColors: Int
    /// 三通道方差均值（0…65025）。
    let variance: Double
    /// 被判为「海洋色」的像素占比。
    let oceanRatio: Double

    init(isBlank: Bool, distinctColors: Int, variance: Double, oceanRatio: Double) {
        self.isBlank = isBlank
        self.distinctColors = distinctColors
        self.variance = variance
        self.oceanRatio = oceanRatio
    }

    /// 从三个通道的样本（长度一致）算出判定结果；样本为空时返回 `nil`（当作「无法判定」）。
    static func analyze(reds: [UInt8], greens: [UInt8], blues: [UInt8]) -> BlankTileAnalysis? {
        let count = min(reds.count, greens.count, blues.count)
        guard count > 0 else { return nil }

        var keys = Set<Int>()
        keys.reserveCapacity(count)
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0
        var ocean = 0

        for index in 0..<count {
            let r = reds[index]
            let g = greens[index]
            let b = blues[index]
            keys.insert(key(r: r, g: g, b: b))

            let dr = Double(r), dg = Double(g), db = Double(b)
            sumR += dr; sumG += dg; sumB += db
            sumR2 += dr * dr; sumG2 += dg * dg; sumB2 += db * db
            if isOcean(r: r, g: g, b: b) { ocean += 1 }
        }

        let n = Double(count)
        let variance = ((sumR2 / n - pow(sumR / n, 2))
            + (sumG2 / n - pow(sumG / n, 2))
            + (sumB2 / n - pow(sumB / n, 2))) / 3.0
        // 浮点误差可能得到 -1e-13 这种负数，钳到 0。
        let safeVariance = max(variance, 0)
        let oceanRatio = Double(ocean) / n
        let distinct = keys.count

        let isOcean = oceanRatio >= oceanMinRatio
        let isBlank = !isOcean
            && (safeVariance < minVariance || (distinct < manyColors && safeVariance < mixedVariance))

        return BlankTileAnalysis(
            isBlank: isBlank,
            distinctColors: distinct,
            variance: safeVariance,
            oceanRatio: oceanRatio
        )
    }

    /// 便捷入口：直接传 `(r, g, b)` 样本数组（自检里构造样本用）。
    static func analyze(samples: [(r: UInt8, g: UInt8, b: UInt8)]) -> BlankTileAnalysis? {
        analyze(
            reds: samples.map(\.r),
            greens: samples.map(\.g),
            blues: samples.map(\.b)
        )
    }

    /// 每通道取高 4 位后的颜色键（12 bit）。
    static func key(r: UInt8, g: UInt8, b: UInt8) -> Int {
        (Int(r >> 4) << 8) | (Int(g >> 4) << 4) | Int(b >> 4)
    }

    /// 这个像素算不算「海洋色」：HSL 色相 185–265°、饱和 ≥ 0.22、亮度 ≥ 60（0…255）。
    static func isOcean(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxChannel = max(rf, gf, bf)
        let minChannel = min(rf, gf, bf)
        let delta = maxChannel - minChannel
        let lightness = (maxChannel + minChannel) / 2 * 255
        guard lightness >= oceanMinLightness else { return false }
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * (lightness / 255) - 1))
        guard saturation >= oceanMinSaturation else { return false }
        guard delta > 0 else { return false }

        let hue: Double
        if maxChannel == rf {
            hue = 60 * ((gf - bf) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxChannel == gf {
            hue = 60 * ((bf - rf) / delta + 2)
        } else {
            hue = 60 * ((rf - gf) / delta + 4)
        }
        let normalized = hue < 0 ? hue + 360 : hue
        return oceanHueRange.contains(normalized)
    }
}
