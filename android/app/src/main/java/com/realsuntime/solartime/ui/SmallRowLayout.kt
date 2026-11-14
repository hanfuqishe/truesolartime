package com.realsuntime.solartime.ui

/**
 * 小字行（左「日期 · 天气 · 温度区间」，右「经纬度」）的排布规则。
 *
 * 空间不够时**隐藏右侧经纬度**，优先保住日期与天气 —— 宁可少一个次要信息，
 * 也不要把日期压成省略号。首页大卡片与桌面卡片共用这一条规则。
 */
object SmallRowLayout {

    /**
     * 是否显示右侧的经纬度。
     *
     * @param leadingWidthPx 左侧文本（日期/天气）的自然宽度
     * @param trailingWidthPx 右侧文本（经纬度）的自然宽度；空字符串传 0
     * @param gapPx 两者之间的间距
     * @param availablePx 整行可用宽度
     */
    fun shouldShowTrailing(
        leadingWidthPx: Float,
        trailingWidthPx: Float,
        gapPx: Float,
        availablePx: Float,
    ): Boolean {
        if (trailingWidthPx <= 0f || availablePx <= 0f) return false
        return leadingWidthPx + trailingWidthPx + gapPx <= availablePx
    }
}
