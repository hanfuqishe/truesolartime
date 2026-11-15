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
     * 大卡片顶部标签行（`UTC+8` · 地区 · `真太阳时` · 时辰）的退化档位。
     *
     * 这一行是**整行一个逻辑单元**（不是左右两列各自一行），四段文本的位置随宽度分 4 档：
     *
     * - **档 0（都放得下）**：整行分左右两半（各占 [rowWidth] 的一半，与下面两列等宽一致）。
     *   左半 `UTC` 贴左、地区贴右（贴着两半的分界）；右半 `真太阳时` 贴左、时辰贴右。
     * - **档 1（地区太长，左半放不下）**：不再显示 `真太阳时`，整行当一个整体 ——
     *   `UTC` 贴左、时辰贴右、地区在两者之间居中。
     * - **档 2（还放不下）**：再把 `UTC` 收掉 —— 地区贴左、时辰贴右。
     * - **档 3（仍放不下）**：排布同档 2，地区尾部用省略号（`TextOverflow.Ellipsis`）。
     *
     * **任何档位时辰都保留**，且始终贴整行最右。
     *
     * @param wUtc `UTC+8` 这类时区文本的自然宽度
     * @param wCity 行政区划文本的自然宽度；空字符串传 0
     * @param wLabel `真太阳时` 那四个字的自然宽度
     * @param wShichen 时辰（如「辰时 · 初」）的自然宽度
     * @param rowWidth 整行可用宽度（还没量出来时传 0）
     * @param gap 相邻两段文本之间的间距
     */
    fun cityRowTier(
        wUtc: Float,
        wCity: Float,
        wLabel: Float,
        wShichen: Float,
        rowWidth: Float,
        gap: Float,
    ): Int {
        // 行宽还没量出来（第一帧）：先按档 0 排，免得闪一下「只剩地区」。
        if (rowWidth <= 0f) return 0
        val utc = wUtc.coerceAtLeast(0f)
        val city = wCity.coerceAtLeast(0f)
        val label = wLabel.coerceAtLeast(0f)
        val shichen = wShichen.coerceAtLeast(0f)
        val space = gap.coerceAtLeast(0f)
        val half = rowWidth / 2f
        // 档 0：两半各自装得下 —— 左半 UTC + 间距 + 地区，右半 真太阳时 + 间距 + 时辰。
        if (utc + city + space <= half && label + shichen + space <= half) return 0
        // 档 1：收掉「真太阳时」后，UTC + 地区 + 时辰 在整行内放得下。
        if (utc + city + shichen + 2f * space <= rowWidth) return 1
        // 档 2：再收掉 UTC，地区 + 时辰 在整行内放得下。
        if (city + shichen + space <= rowWidth) return 2
        return 3
    }

    /**
     * 档 0 时左右两半的宽度：恒为整行的一半（与下面两列等宽一致）。
     *
     * 宽度还没量出来时返回 `0f to 0f`。
     */
    fun cityRowHalves(rowWidth: Float): Pair<Float, Float> {
        if (rowWidth <= 0f) return 0f to 0f
        val half = rowWidth / 2f
        return half to half
    }

    /**
     * 两列之间那条竖分隔线（整行 50%）要不要**向上延伸到标签行顶部**。
     *
     * 只有档 0 需要：那一档标签行还是左右两半 —— 左半地区贴右、右半「真太阳时」贴左，
     * 两半的分界**就是**下面两列的分界。把线从标签行顶部一路贯下来，它才正好落在
     * 「地区」与「真太阳时」之间，把两者隔开，视觉上连成一条。
     *
     * 档 1~3 的标签行已经合并成一整行（地区居中 / 贴左、时辰贴右），线再上延就会横穿
     * 文字，所以只盖下方两列。
     *
     * 首页大卡片（`HeroCard`）与桌面小组件（`WidgetUpdater`）共用这一条规则。
     */
    fun dividerReachesLabelRow(tier: Int): Boolean = tier == 0
}
