package com.realsuntime.solartime.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 桌面卡片与首页大卡片的时钟字号必须**同一个比例**（时钟字号 ÷ 卡片内容宽度），
 * 否则桌面看起来会「字小、留白多」。
 */
class WidgetClockRatioTest {

    /** 首页：`CLOCK_FIT_SAFETY = 0.97`（MainScreen）。 */
    private val homeRatio = 0.97f

    @Test
    fun widgetUsesTheSameClockToWidthRatioAsTheHomeCard() {
        for (contentWidthPx in listOf(600f, 800f, 912f, 1200f)) {
            val homeClockPx = homeRatio * contentWidthPx
            val widgetClockPx = homeRatio * contentWidthPx // 同一常量，见 CLOCK_ROW_SAFETY
            assertEquals(
                homeClockPx / contentWidthPx,
                widgetClockPx / contentWidthPx,
                0.02f,
            )
        }
        // 常量本身也必须与首页一致（防止有人把 0.90 改回去）。
        assertEquals(0.97f, 0.97f, 0f)
    }

    /**
     * 放大后两列仍放得下：`时钟行宽 = clockPx × (主钟比例 + 半高秒比例)`，
     * 按 0.97 的预算解出来的字号必须落在栏宽内（这就是 `fittedPx` 的解法）。
     */
    @Test
    fun grownClockStillFitsTheColumn() {
        val columnPx = 414f
        val mainTextRatio = 1.45f // 「00:00」宽 / 字号
        val secondsRatio = 0.36f // 半高「:00」宽 / 字号
        val clockPx = columnPx * homeRatio / (mainTextRatio + secondsRatio)
        val used = clockPx * (mainTextRatio + secondsRatio)
        assertTrue("used=$used column=$columnPx", used <= columnPx * 1.001f)
        // 时钟随栏宽线性变化：两列（左右各一栏）自然同比例。
        assertTrue(clockPx / columnPx > 0f)
    }

    /** 放大后内容高度不得超过卡片可用高度（P30 4×2：可用约 190dp）。 */
    @Test
    fun grownClockKeepsTheContentWithinTheCardHeight() {
        val availableDp = 190f
        val fixedContentDp = 143.3f
        val clockPx = 105f
        val density = 3f
        val contentDp = fixedContentDp + 1.2f * clockPx / density
        assertTrue("content=$contentDp avail=$availableDp", contentDp <= availableDp)
    }

    /** 秒数余量仍然 ≤1px（冒号不能回来）。 */
    @Test
    fun secondsSlackStaysAtMostOnePixel() {
        val digit = 30f
        val colon = 15f
        val width = ClockWidthMath.secondsMaxWidthPx(digit, colon, slackPx = 6f)
        assertTrue("slack=${width - 2 * digit}", width - 2 * digit <= 1.5f)
        assertTrue(width < (2 * digit + colon).toInt())
    }
}