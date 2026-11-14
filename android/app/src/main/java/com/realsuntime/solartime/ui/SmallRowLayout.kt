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

    /**
     * 大卡片顶部那行（`UTC+8` · 行政区划 · 右列「真太阳时」）的退化级别。
     *
     * 优先级：**保留城市名 > 保留「真太阳时」 > 保留 UTC**。空间不够时按级退化：
     *
     * - **0 级**：`UTC+8`、行政区划、右列「真太阳时」都显示；
     * - **1 级**：城市名占用右列「真太阳时」那四个字的位置 —— 隐藏这个标签（右列的时辰照旧显示），
     *   城市名最多可以长到左列整宽 [availablePx]；
     * - **2 级**：城市名连整宽都放不下 —— 再把 UTC 让出去，城市名从最左占满整列，超出用省略号。
     *
     * @param wUtc UTC 标签的自然宽度
     * @param wCity 行政区划的自然宽度；空字符串传 0
     * @param wLabel 右列「真太阳时」标签的宽度（**含**它与右侧时辰之间的间距）
     * @param available 左列的可用宽度
     * @param gap 元素之间的间距
     */
    fun cityRowTier(
        wUtc: Float,
        wCity: Float,
        wLabel: Float,
        available: Float,
        gap: Float,
    ): Int {
        // 还没量出行宽、或者没有城市名：先按 0 级排，避免第一帧就跳成「只剩城市名」。
        if (available <= 0f || wCity <= 0f) return 0
        // 0 级：UTC 与城市名之间留两侧间距还放得下。
        if (wCity + gap <= available - wUtc - gap) return 0
        // 1 级：城市名可以吃到「真太阳时」的位置，但右列没有标签可吃（宽度为 0）时就没什么
        // 好让的，直接进 2 级 —— 宁可把 UTC 让出去，也别让城市名白缩一段。
        val cityCanTake = minOf(available - wUtc - gap + wLabel.coerceAtLeast(0f), available)
        return if (wCity + gap <= cityCanTake) 1 else 2
    }
}
