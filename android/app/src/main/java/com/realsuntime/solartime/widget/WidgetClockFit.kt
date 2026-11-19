package com.realsuntime.solartime.widget

/**
 * 卡片竖向空间分配：**先把富余高度用来放大时钟**，再把剩下的均分到上下内边距。
 *
 * 时钟放大有两条硬上限：
 * 1. **宽度拟合值** [fittedPx]：再大两列就会挤到一起；
 * 2. **可用高度**：放大后「其它内容 + 时钟行」不能超过 [availableDp]。
 *
 * 都不超时，余量平均分给 top / bottom（垂直居中）。
 * 空间不足（`availableDp < 内容高度`）时不放大，走原有的压缩逻辑。
 */
internal object WidgetClockFit {

    /** 主时钟行盒 = 1.2em（字体 ascent 0.9 + descent 0.3）。 */
    const val CLOCK_LINE_EM = 1.2f

    /** 单侧最多加这么多内边距：再大就只是把字往中间推，反而显空。 */
    const val MAX_EXTRA_PADDING_DP = 40f

    data class Fit(
        /** 放大后的主字号（px）。 */
        val mainPx: Float,
        /** 富余均分后，**单侧**额外内边距（dp）。 */
        val extraPaddingDp: Float,
    )

    /**
     * @param availableDp 卡片可用高度
     * @param otherContentDp 除「时钟行」以外的内容高度
     * @param fittedPx 宽度拟合出的主字号上限（放大不得超过它）
     * @param minPx 当前（未放大）的主字号
     * @param density 渲染密度
     */
    fun fit(
        availableDp: Float,
        otherContentDp: Float,
        fittedPx: Float,
        minPx: Float,
        density: Float,
        maxExtraPaddingDp: Float = MAX_EXTRA_PADDING_DP,
    ): Fit {
        if (density <= 0f) return Fit(minPx, 0f)
        val roomDp = availableDp - otherContentDp
        // 可用高度反推出的主字号（时钟行高度 = 1.2 × mainPx）。
        val byHeightPx = (roomDp.coerceAtLeast(0f) * density) / CLOCK_LINE_EM
        val grown = byHeightPx.coerceAtMost(fittedPx).coerceAtLeast(minPx)
        val contentDp = otherContentDp + CLOCK_LINE_EM * grown / density
        val leftover = (availableDp - contentDp).coerceIn(0f, 2f * maxExtraPaddingDp)
        return Fit(mainPx = grown, extraPaddingDp = leftover / 2f)
    }
}
