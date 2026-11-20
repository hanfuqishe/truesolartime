package com.realsuntime.solartime.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 校准尺的纯几何：刻度 y、宽度上限、实测高度夹取与预算。
 *
 * 真实高度读不到（RemoteViews 在桌面进程），所以尺子必须「0 在顶端、每 10dp 一格、
 * maxDp 处有刻度」，用户读出的最大完整刻度才等于可用高度。
 */
class WidgetRulerTest {

    @Test
    fun tickYMatchesTheDpScale() {
        assertEquals(0f, WidgetRuler.tickY(0, 400, 1200), 0.01f)
        assertEquals(30f, WidgetRuler.tickY(10, 400, 1200), 0.01f)
        assertEquals(150f, WidgetRuler.tickY(50, 400, 1200), 0.01f)
        assertEquals(1200f, WidgetRuler.tickY(400, 400, 1200), 0.01f)
        // 尺子的刻度必须覆盖 0..maxDp，且每 10dp 一条。
        val ticks = WidgetRuler.tickDps(400)
        assertEquals(41, ticks.size)
        assertTrue(ticks.first() == 0 && ticks.last() == 400)
        assertTrue(ticks.contains(50) && ticks.contains(400))
    }

    @Test
    fun bitmapWidthIsClampedToTheBinderFriendlyLimit() {
        assertEquals(1024, WidgetRuler.clampWidthPx(2048))
        assertEquals(1024, WidgetRuler.clampWidthPx(1024))
        assertEquals(600, WidgetRuler.clampWidthPx(600))
        assertEquals(1, WidgetRuler.clampWidthPx(0))
        assertEquals(1, WidgetRuler.clampWidthPx(-50))
    }

    @Test
    fun overrideHeightIsClampedToTheSupportedRange() {
        assertEquals(0, WidgetRuler.clampOverrideDp(0))
        assertEquals(0, WidgetRuler.clampOverrideDp(-10))
        assertEquals(100, WidgetRuler.clampOverrideDp(50))
        assertEquals(220, WidgetRuler.clampOverrideDp(220))
        assertEquals(400, WidgetRuler.clampOverrideDp(500))
    }

    /** 有实测值 → 用实测值 − 4dp；0 → 回退自动估算。 */
    @Test
    fun availableHeightPrefersTheOverrideAndFallsBackToAuto() {
        assertEquals(216f, WidgetRuler.availableDp(220, 160f), 0.01f)
        assertEquals(160f, WidgetRuler.availableDp(0, 160f), 0.01f)
        // 实测值越大，预算越大（收轴判定的输入）。
        assertTrue(WidgetRuler.availableDp(300, 160f) > WidgetRuler.availableDp(220, 160f))
    }
}
