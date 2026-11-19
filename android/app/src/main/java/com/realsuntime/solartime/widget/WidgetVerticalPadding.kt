package com.realsuntime.solartime.widget

/**
 * 桌面卡片的竖向留白：高度富余时**平均分给上下**，让内容垂直居中（不要全堆在底部）。
 *
 * 这是「模仿首页大卡片」的最小实现 —— 卡片内部的字号与行距完全沿用现有的宽度拟合
 * （与首页同一套比例），只把多出来的高度对称地补到 padding 上；
 * 放不下时仍走原来的压缩逻辑（`basePaddingDp`，由调用方决定收紧后的值）。
 */
internal object WidgetVerticalPadding {

    /**
     * @param availableDp 卡片可用高度
     * @param contentDp 内容自然高度（含基础上下内边距）
     * @param basePaddingDp 基础（单侧）内边距；放不下时原样返回
     * @return `(top, bottom)`，富余时两者相等
     */
    fun paddingDp(
        availableDp: Float,
        contentDp: Float,
        basePaddingDp: Float,
        maxExtraPerSideDp: Float = 40f,
    ): Pair<Float, Float> {
        val slack = availableDp - contentDp
        if (slack <= 1f) return basePaddingDp to basePaddingDp
        val extra = (slack / 2f).coerceAtMost(maxExtraPerSideDp)
        return (basePaddingDp + extra) to (basePaddingDp + extra)
    }
}
