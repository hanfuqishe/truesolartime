package com.realsuntime.solartime.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmallRowLayoutTest {

    @Test
    fun showsCoordinatesWhenBothFit() {
        // 100 + 80 + 8 = 188 <= 200，放得下
        assertTrue(SmallRowLayout.shouldShowTrailing(100f, 80f, 8f, 200f))
    }

    @Test
    fun hidesCoordinatesWhenTooWide() {
        // 150 + 80 + 8 = 238 > 200，藏掉经纬度
        assertFalse(SmallRowLayout.shouldShowTrailing(150f, 80f, 8f, 200f))
    }

    @Test
    fun hidesCoordinatesWhenTrailingIsEmpty() {
        assertFalse(SmallRowLayout.shouldShowTrailing(100f, 0f, 8f, 200f))
    }

    @Test
    fun hidesCoordinatesBeforeFirstMeasure() {
        // 行宽还没量出来（0）时先不显示，等 onSizeChanged 回来再看
        assertFalse(SmallRowLayout.shouldShowTrailing(100f, 80f, 8f, 0f))
    }

    @Test
    fun exactFitIsVisible() {
        assertTrue(SmallRowLayout.shouldShowTrailing(112f, 80f, 8f, 200f))
    }
}
