package com.realsuntime.solartime.widget

/**
 * 小组件时钟字号换算：不同机型/桌面给到的宽度差别很大，固定字号会横向被裁掉，
 * 这里按可用宽度反推主时间字号。
 */
object WidgetSizing {

    /** 主时间文本（"00:00"）宽度与字号的比值，用于把可用宽度换算成字号。 */
    const val MAIN_TEXT_WIDTH_RATIO = 2.62f

    /**
     * 按可用宽度求主字号：文本宽度约等于 [widthRatio] × 字号。
     *
     * @param availableWidthPx 主时间文本可用的宽度（像素，已扣除秒数与冒号）
     * @param widthRatio 文本宽度/字号
     * @return 落在 [minPx]..[maxPx] 之间的字号
     */
    fun fitTextSizePx(
        availableWidthPx: Float,
        widthRatio: Float = MAIN_TEXT_WIDTH_RATIO,
        minPx: Float,
        maxPx: Float,
    ): Float {
        if (availableWidthPx <= 0f || widthRatio <= 0f) return minPx
        return (availableWidthPx / widthRatio).coerceIn(minPx, maxPx)
    }
}
