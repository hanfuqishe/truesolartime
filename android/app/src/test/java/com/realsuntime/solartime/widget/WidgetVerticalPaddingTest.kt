package com.realsuntime.solartime.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** 竖向留白：富余时上下均分（居中），不够时不动（交给压缩逻辑）。 */
class WidgetVerticalPaddingTest {

    @Test
    fun surplusIsSplitEvenlyBetweenTopAndBottom() {
        val (top, bottom) = WidgetVerticalPadding.paddingDp(
            availableDp = 190f,
            contentDp = 165f,
            basePaddingDp = 10f,
        )
        // 多出 25dp → 上下各 +12.5dp
        assertEquals(22.5f, top, 0.01f)
        assertEquals(22.5f, bottom, 0.01f)
        assertEquals("上下必须相等", top, bottom, 0.01f)
        // 补掉的总量 = 富余量
        assertEquals(25f, (top + bottom) - 2f * 10f, 0.01f)
    }

    /**
     * P30 的 4×2：可用 ~190dp、内容 ~165dp → 上下各比基础 10dp 多约 12.5dp
     * （验收口径：各多 ~12dp）。
     */
    @Test
    fun p30FourByTwoGetsAboutTwelveDpPerSide() {
        val (top, bottom) = WidgetVerticalPadding.paddingDp(190f, 165f, 10f)
        assertTrue("top=$top", top - 10f in 11.5f..13.5f)
        assertTrue("bottom=$bottom", bottom - 10f in 11.5f..13.5f)
    }

    @Test
    fun insufficientHeightKeepsTheBasePadding() {
        val (top, bottom) = WidgetVerticalPadding.paddingDp(150f, 165f, 4f)
        assertEquals(4f, top, 0f)
        assertEquals(4f, bottom, 0f)
    }

    @Test
    fun nearZeroSurplusDoesNotJitter() {
        val (top, bottom) = WidgetVerticalPadding.paddingDp(165.5f, 165f, 10f)
        assertEquals(10f, top, 0f)
        assertEquals(10f, bottom, 0f)
    }

    @Test
    fun extraPaddingIsCapped() {
        val (top, _) = WidgetVerticalPadding.paddingDp(400f, 150f, 10f, maxExtraPerSideDp = 40f)
        assertEquals(50f, top, 0.01f)
    }
}
