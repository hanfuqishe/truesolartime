package com.realsuntime.solartime.map

import kotlin.math.max
import kotlin.math.min

/**
 * 「空白瓦片」判定 —— 纯 JVM 逻辑，不碰 Android，单测可以脱离设备跑。
 *
 * 要解决的问题：高德对**境外**坐标常常回 200 的空白瓦片（灰底 + 「高德地图」水印，
 * 没有任何地理内容）。osmdroid 只看 HTTP 与解码，于是把它当成「成功」，
 * 降级链就停在高德这一级，用户看到一片灰。这里用一次轻量像素分析把这种瓦片认出来，
 * 交给 [MapFallback] 当失败处理，继续往下探（z12 → z11 → z10 → z3）。
 *
 * 判据（数值都可以在这里调，单测 [TileBlankTest] 盯着边界）：
 * 1. **颜色种类少且方差小**：颜色按每通道高 4 位量化（4096 种可能），种类 < [MIN_COLOR_KINDS]
 *    且平均每通道方差 < [VARIANCE_THRESHOLD] → 空白。灰底 + 一抹水印白字正好落在这里。
 * 2. **几乎单色**：方差 < [MONO_VARIANCE]（连纹理都没有，JPEG 噪声也救不回来）→ 空白，
 *    不管颜色种类是多少。纯色瓦片、带压缩噪声的纯色瓦片都走这条。
 * 3. **海洋不算空白**：整块瓦片大部分是「饱和的蓝色」时判为海面（纯蓝色的海也是有效内容）。
 *    这一条优先于上面两条，否则纯蓝海面会被第 2 条判成空白。
 *
 * 为什么不看「平均亮度」：高德空白瓦片是浅灰，而城市瓦片的底色也是浅灰，
 * 亮度几乎一样；能把它们分开的是**有没有深色文字/彩色道路**，也就是方差与颜色种类。
 *
 * 采样：调用方把瓦片缩放到 [SAMPLE_SIDE]×[SAMPLE_SIDE] 再取像素（256 像素的瓦片即
 * 每 [SAMPLE_STEP] 像素取一个点，共 [SAMPLE_SIDE]² = 1024 个样本）；本文件只吃 int 数组。
 */
object TileBlank {

    /** 采样步长（像素）：256×256 的瓦片按此抽点。 */
    const val SAMPLE_STEP = 8

    /** 每个方向的采样点数：256 / [SAMPLE_STEP] = 32，合计 1024 个样本。 */
    const val SAMPLE_SIDE = 32

    /** 颜色量化：每通道只留高 4 位（16 级），于是有 4096 个可能的「颜色种类」。 */
    private const val QUANT_SHIFT = 4

    /** 颜色种类少于它、且方差低于 [VARIANCE_THRESHOLD] → 空白。七种算空白，八种就不算了。 */
    const val MIN_COLOR_KINDS = 8

    /** 平均每通道方差（0..65025）低于它算「没什么内容」；标准差约 20/255。 */
    const val VARIANCE_THRESHOLD = 400.0

    /** 方差低于它 → 几乎单色（标准差约 3.5/255），无论颜色种类多少都判空白。 */
    const val MONO_VARIANCE = 12.0

    /** 蓝色（海面）样本占比达到它 → 判为海洋，算有内容。 */
    const val OCEAN_BLUE_SHARE = 0.6

    /** 判为「蓝色」所需的最低饱和度：太浅的灰蓝（#C8D8E8 这种）不算海。 */
    private const val OCEAN_MIN_SATURATION = 0.22

    /**
     * 分析一块瓦片的像素（ARGB_8888 打包的 int，alpha 忽略）。
     *
     * @param colors 采样点的颜色数组；空数组表示「没采到样本」，此时**不**判空白
     *               （宁可不降级，也不要因为一次读取失败就把好的底图踢下去）。
     */
    fun analyzeColors(colors: IntArray): TileContent {
        val count = colors.size
        if (count == 0) {
            return TileContent(
                sampleCount = 0,
                colorKinds = 0,
                variance = 0.0,
                blueShare = 0.0,
                isOcean = false,
                isBlank = false,
            )
        }

        val kinds = HashSet<Int>(min(count, 64))
        var sumR = 0L
        var sumG = 0L
        var sumB = 0L
        var blue = 0
        for (color in colors) {
            val r = (color shr 16) and 0xFF
            val g = (color shr 8) and 0xFF
            val b = color and 0xFF
            sumR += r
            sumG += g
            sumB += b
            kinds.add(quantize(r, g, b))
            if (isOceanBlue(r, g, b)) blue++
        }

        val meanR = sumR.toDouble() / count
        val meanG = sumG.toDouble() / count
        val meanB = sumB.toDouble() / count
        var devR = 0.0
        var devG = 0.0
        var devB = 0.0
        for (color in colors) {
            val r = ((color shr 16) and 0xFF) - meanR
            val g = ((color shr 8) and 0xFF) - meanG
            val b = (color and 0xFF) - meanB
            devR += r * r
            devG += g * g
            devB += b * b
        }
        val variance = (devR + devG + devB) / (3.0 * count)
        val blueShare = blue.toDouble() / count
        val isOcean = blueShare >= OCEAN_BLUE_SHARE
        val isBlank = !isOcean && (
            variance < MONO_VARIANCE ||
                (kinds.size < MIN_COLOR_KINDS && variance < VARIANCE_THRESHOLD)
            )

        return TileContent(
            sampleCount = count,
            colorKinds = kinds.size,
            variance = variance,
            blueShare = blueShare,
            isOcean = isOcean,
            isBlank = isBlank,
        )
    }

    /** 一句诊断文案用的摘要，例如 `色彩 3 种 / 方差 41`。 */
    fun describe(content: TileContent): String =
        "色彩 ${content.colorKinds} 种 / 方差 ${content.variance.toInt()}" +
            if (content.isOcean) " / 海面" else ""

    /**
     * 一屏（视口）的结论：**看过的每一块都空白**才算「这一屏是空白」。
     *
     * 为什么不是「有一块空白就算」：低级别（z3 全球图）上，撒哈拉、西伯利亚、南极冰盖这些
     * 真·纯色瓦片和「没数据」的空白瓦片在像素上完全一样（实测高德 z3 的沙漠瓦片就是一块
     * #F7F3EA 纯色，和境外空白瓦片一模一样）。但真在出图的视口里一定混着海岸线、国界、地名 ——
     * 只要混进一块有内容的，就不能判这一屏没内容，否则会把正常的世界地图误降成「底图不可用」。
     *
     * 空集合（这一批没看到任何瓦片）**不**算空白：宁可不降级，也不要把「还没加载完」当成没内容。
     */
    fun viewportIsBlank(contents: List<TileContent>): Boolean =
        contents.isNotEmpty() && contents.all { it.isBlank }

    /** 每通道高 4 位 → 一个 12 位的「颜色种类」编号。 */
    private fun quantize(r: Int, g: Int, b: Int): Int =
        ((r shr QUANT_SHIFT) shl 8) or ((g shr QUANT_SHIFT) shl 4) or (b shr QUANT_SHIFT)

    /**
     * 这个像素像不像海面：色相落在蓝—青区间、饱和度够、且不是近黑。
     *
     * 高德矢量海面是 #A3C8F0 一类的浅蓝，深一点的海是 #1E6EB5；
     * 空白瓦片是纯灰（饱和度 0），城市瓦片的底色也是灰 —— 都不会被误认成海。
     */
    private fun isOceanBlue(r: Int, g: Int, b: Int): Boolean {
        val hi = max(r, max(g, b))
        val lo = min(r, min(g, b))
        // 近黑（夜里的卫星图）不当海：蓝色分量再高也没有意义。
        if (hi < 60) return false
        val delta = hi - lo
        if (delta == 0) return false
        val saturation = delta.toDouble() / hi
        if (saturation < OCEAN_MIN_SATURATION) return false
        val hue = when (hi) {
            r -> 60.0 * (((g - b).toDouble() / delta) % 6.0)
            g -> 60.0 * ((b - r).toDouble() / delta + 2.0)
            else -> 60.0 * ((r - g).toDouble() / delta + 4.0)
        }.let { if (it < 0) it + 360.0 else it }
        return hue in 185.0..265.0
    }
}

/** 一块瓦片的像素统计结论。 */
data class TileContent(
    /** 参与统计的采样点数。 */
    val sampleCount: Int,
    /** 量化后的颜色种类数。 */
    val colorKinds: Int,
    /** 三个通道的平均方差（0..65025）。 */
    val variance: Double,
    /** 判为蓝色的样本占比（海洋判据）。 */
    val blueShare: Double,
    /** 是否被判为海面（海面算有效内容）。 */
    val isOcean: Boolean,
    /** 是否没有实际地理内容（要按失败处理）。 */
    val isBlank: Boolean,
)

/** 一次瓦片回调的结果类型。 */
enum class TileResult {
    /** 拿到并画出了一块正常瓦片。 */
    LOADED,

    /** osmdroid 收敛出来的真实失败（非 2xx / 连接超时 / 解码失败）。 */
    FAILED,

    /** 拿到的是 200 的空白瓦片（高德对境外常这么回）：按失败处理，继续降级。 */
    BLANK,
}

/**
 * 瓦片回调上报给状态机的事件。
 *
 * osmdroid 的完成回调只带一个 `what`（`MapTileProviderBase.sendMessage` 用的是
 * `sendEmptyMessage`），既没有瓦片坐标也没有 bitmap；坐标与像素是在
 * `MapCard` 里从 tileCache 反查出来的，这里只负责把结论送上去。
 */
data class TileEvent(
    val zoom: Int,
    val result: TileResult,
    /** 判为空白时的量化颜色种类数（诊断用）；其它情况为 0。 */
    val colorKinds: Int = 0,
)
