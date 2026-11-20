package com.realsuntime.solartime.ui

/**
 * 设置页「常用城市」等宽网格的列数计算（纯函数，单测直接盯）。
 *
 * 目标：**保持等宽**，但别让每个 chip 比文字宽太多（P40 反馈：3 列时「新加坡」两侧各空一大截）。
 * 做法：从最多列往最少列试，第一个「最长城市名 + 两侧内边距 ≤ 列宽」的列数胜出；都不行就回落到
 * [MIN_COLUMNS]（宁可少一列，也不能截断「南极中山站」「摩尔曼斯克」）。
 */
object PresetGrid {

    /** 列间距（dp）。 */
    const val GAP_DP = 8f

    /** 行间距（dp）：比列间距更紧，整块「常用城市」才不会显得稀疏。 */
    const val ROW_GAP_DP = 6f

    /** chip 左右内边距（dp）：从原来的 ~16dp 收紧到 10dp，让文字占比更高。 */
    const val CHIP_PADDING_DP = 10f

    /** chip 高度（dp）：36dp → 32dp（仍 ≥ 32dp 的触控目标下限）。 */
    const val CHIP_HEIGHT_DP = 32f

    /** 城市名文字字号（sp）：估算宽度与渲染必须用同一个值。 */
    const val TEXT_SIZE_SP = 12f

    /**
     * 贪心分行（纯函数）：依次把每个 chip 塞进当前行，放不下就换行。
     *
     * * 单个 chip 比整行还宽时**独占一行**（渲染端再用 `maxLines=1 + ellipsis` 截断）；
     * * 行内间距 [gapDp] 计入判断（放下第 i 个时，需 `当前行宽 + gap + 该 chip 宽 ≤ 行宽`）。
     *
     * @return 每行包含的下标列表
     */
    fun packRows(
        itemWidthsDp: List<Float>,
        rowWidthDp: Float,
        gapDp: Float = GAP_DP,
    ): List<List<Int>> {
        if (itemWidthsDp.isEmpty()) return emptyList()
        val rows = mutableListOf<MutableList<Int>>()
        var current = mutableListOf<Int>()
        var used = 0f
        for (index in itemWidthsDp.indices) {
            val width = itemWidthsDp[index].coerceAtLeast(0f)
            if (current.isEmpty()) {
                current.add(index)
                used = width
                continue
            }
            if (used + gapDp + width <= rowWidthDp + 0.001f) {
                current.add(index)
                used += gapDp + width
            } else {
                rows.add(current)
                current = mutableListOf(index)
                used = width
            }
        }
        if (current.isNotEmpty()) rows.add(current)
        return rows
    }
    /** 最少 / 最多列数。 */
    const val MIN_COLUMNS = 3
    const val MAX_COLUMNS = 5

    /**
     * 估算文本宽度（dp）：CJK 字符按 1 个字号宽，拉丁字母/数字按 0.6，空格按 0.3。
     *
     * 只是用来挑列数，不做像素级排版；真正渲染时超长名还有省略号兜底。
     */
    fun estimateTextWidthDp(text: String, fontSizeSp: Float = TEXT_SIZE_SP): Float {
        var width = 0f
        for (char in text) {
            width += when {
                char == ' ' -> 0.3f
                char.code in 0x2E80..0x9FFF -> 1f // CJK（含「南」「极」「站」等）
                char.code in 0xFF00..0xFFEF -> 1f // 全角标点
                else -> 0.6f
            } * fontSizeSp
        }
        return width
    }

    /**
     * 选列数（5 → 4 → 3 依次试）。
     *
     * @param contentWidthDp 可用宽度 = 卡片内容宽 − 左右内边距
     * @param longestNameWidthDp 最长城市名的估算宽度
     * @return 保证「最长名 + 2 × [chipPaddingDp] ≤ 列宽」的最大列数；都放不下则 [minColumns]
     */
    fun columnCount(
        contentWidthDp: Float,
        longestNameWidthDp: Float,
        gapDp: Float = GAP_DP,
        chipPaddingDp: Float = CHIP_PADDING_DP,
        minColumns: Int = MIN_COLUMNS,
        maxColumns: Int = MAX_COLUMNS,
    ): Int {
        if (contentWidthDp <= 0f) return minColumns
        for (columns in maxColumns downTo minColumns) {
            val columnWidth = (contentWidthDp - (columns - 1) * gapDp) / columns
            if (longestNameWidthDp + 2f * chipPaddingDp <= columnWidth) return columns
        }
        return minColumns
    }
}
