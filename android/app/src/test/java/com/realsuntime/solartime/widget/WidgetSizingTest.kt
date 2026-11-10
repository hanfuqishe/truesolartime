package com.realsuntime.solartime.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetSizingTest {

    @Test
    fun keepsDesignSizeWhenThereIsEnoughRoom() {
        // "00:00" 宽约 2.62 倍字号：120 宽度足够放下 42 的字号，封顶在设计字号
        assertEquals(42f, WidgetSizing.fitTextSizePx(120f, 2.62f, minPx = 22f, maxPx = 42f), 0.01f)
    }

    @Test
    fun shrinksToFitNarrowColumn() {
        // 只有 70 可用 → 字号约 26.7
        assertEquals(26.7f, WidgetSizing.fitTextSizePx(70f, 2.62f, minPx = 22f, maxPx = 42f), 0.1f)
    }

    @Test
    fun neverGoesBelowMinimumEvenWhenWidthIsTiny() {
        assertEquals(22f, WidgetSizing.fitTextSizePx(10f, 2.62f, minPx = 22f, maxPx = 42f), 0.01f)
    }

    @Test
    fun fallsBackToMinimumOnInvalidInput() {
        assertEquals(22f, WidgetSizing.fitTextSizePx(0f, 2.62f, minPx = 22f, maxPx = 42f), 0.01f)
        assertEquals(22f, WidgetSizing.fitTextSizePx(100f, 0f, minPx = 22f, maxPx = 42f), 0.01f)
    }
}
