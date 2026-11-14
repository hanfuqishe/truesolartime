package com.realsuntime.solartime.ui

import org.junit.Assert.assertEquals
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

    // ---- 顶部那行（UTC + 行政区划 + 真太阳时）的三级退化 ----
    // 统一取值：间距 8、UTC 44、右列「真太阳时」标签 52（含与时辰之间的间距）、左列宽 200。
    // 0 级上限：city + 8 <= 200 - 44 - 8 = 148，即 city <= 140；
    // 1 级上限：城市名可吃掉标签的位置（148 + 52 > 200），封顶到整宽 200，即 city <= 192。

    @Test
    fun cityRowTierZeroWhenEverythingFits() {
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 100f, 52f, 200f, 8f))
    }

    @Test
    fun cityRowTierZeroAtExactFitBoundary() {
        // 140 + 8 = 148，正好等于 200 - 44 - 8，仍是 0 级
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 140f, 52f, 200f, 8f))
    }

    @Test
    fun cityRowTierOneJustOverTheBoundary() {
        // 141 + 8 = 149 > 148：城市名越过 UTC 那一侧，藏「真太阳时」标签
        assertEquals(1, SmallRowLayout.cityRowTier(44f, 141f, 52f, 200f, 8f))
    }

    @Test
    fun cityRowTierOneAtFullWidthBoundary() {
        // 192 + 8 = 200，正好撑满左列整宽，还是 1 级
        assertEquals(1, SmallRowLayout.cityRowTier(44f, 192f, 52f, 200f, 8f))
    }

    @Test
    fun cityRowTierTwoWhenCityIsWiderThanTheWholeColumn() {
        // 193 + 8 = 201 > 200：连整列都放不下，UTC 也一起让位
        assertEquals(2, SmallRowLayout.cityRowTier(44f, 193f, 52f, 200f, 8f))
    }

    @Test
    fun cityRowTierTwoWhenThereIsNoLabelToGiveUp() {
        // 右列没有「真太阳时」可让（宽 0）时，1 级没有意义：直接让 UTC 让位
        assertEquals(2, SmallRowLayout.cityRowTier(44f, 141f, 0f, 200f, 8f))
    }

    @Test
    fun cityRowTierOnExtremelyNarrowColumn() {
        // 左列只有 60：UTC 之后只剩 8，城市名 20 就已经放不下了 -> 1 级；55 连整宽都超 -> 2 级
        assertEquals(1, SmallRowLayout.cityRowTier(44f, 20f, 52f, 60f, 8f))
        assertEquals(2, SmallRowLayout.cityRowTier(44f, 55f, 52f, 60f, 8f))
    }

    @Test
    fun cityRowTierZeroOnExtremelyWideColumn() {
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 600f, 52f, 2000f, 8f))
    }

    @Test
    fun cityRowTierZeroBeforeFirstMeasure() {
        // 行宽还没量出来（0）时按 0 级排，避免第一帧跳成「只剩城市名」
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 300f, 52f, 0f, 8f))
    }
}
