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

    // ---- 顶部那行（UTC · 地区 · 真太阳时 · 时辰）的四档退化 ----
    // 统一取值：整行 400、间距 8、UTC 44、右列「真太阳时」52、时辰 60，左右两半各 200。
    // 档 0 上限：左半 44 + 地区 + 8 <= 200 → 地区 <= 148；
    //            右半 52 + 60 + 8 = 120 <= 200（右半始终够，除非标签/时辰变长，见下面单独一条）。
    // 档 1 上限：44 + 地区 + 60 + 16 <= 400 → 地区 <= 280；
    // 档 2 上限：地区 + 60 + 8 <= 400 → 地区 <= 332；再宽就是档 3。

    @Test
    fun tierZeroWhenEverythingFits() {
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 100f, 52f, 60f, 400f, 8f))
    }

    @Test
    fun tierZeroAtExactLeftHalfFit() {
        // 44 + 148 + 8 = 200，正好等于左半宽，仍是档 0
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 148f, 52f, 60f, 400f, 8f))
    }

    @Test
    fun tierOneJustOverTheLeftHalf() {
        // 44 + 149 + 8 = 201 > 200：左半放不下，收掉「真太阳时」，地区改为整行居中
        assertEquals(1, SmallRowLayout.cityRowTier(44f, 149f, 52f, 60f, 400f, 8f))
    }

    @Test
    fun tierZeroWhenTheRightHalfIsExactlyFull() {
        // 右半 132 + 60 + 8 = 200：左右两半都刚好放得下
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 100f, 132f, 60f, 400f, 8f))
    }

    @Test
    fun tierOneWhenOnlyTheRightHalfOverflows() {
        // 地区只有 10 字宽，但「真太阳时」+ 时辰挤爆右半 → 收掉标签，档 1
        assertEquals(1, SmallRowLayout.cityRowTier(44f, 10f, 133f, 60f, 400f, 8f))
    }

    @Test
    fun tierOneAtExactFullRowFit() {
        // 44 + 280 + 60 + 16 = 400，整行正好放得下 UTC + 地区 + 时辰
        assertEquals(1, SmallRowLayout.cityRowTier(44f, 280f, 52f, 60f, 400f, 8f))
    }

    @Test
    fun tierTwoJustOverTheFullRow() {
        // 44 + 281 + 60 + 16 = 401 > 400：连整行都放不下，再收掉 UTC
        assertEquals(2, SmallRowLayout.cityRowTier(44f, 281f, 52f, 60f, 400f, 8f))
    }

    @Test
    fun tierTwoAtExactCityAndShichenFit() {
        // 332 + 60 + 8 = 400，地区 + 时辰 正好撑满整行
        assertEquals(2, SmallRowLayout.cityRowTier(44f, 332f, 52f, 60f, 400f, 8f))
    }

    @Test
    fun tierThreeWhenEvenTheCityAloneOverflows() {
        // 333 + 60 + 8 = 401 > 400：档 2 也放不下，地区尾部省略号
        assertEquals(3, SmallRowLayout.cityRowTier(44f, 333f, 52f, 60f, 400f, 8f))
    }

    @Test
    fun tierOnExtremelyNarrowRow() {
        // 整行只有 60：档 1/档 2 都放不下（44+20+60+16、20+60+8 都 > 60）→ 档 3
        assertEquals(3, SmallRowLayout.cityRowTier(44f, 20f, 52f, 60f, 60f, 8f))
        // 整行 100：地区 + 时辰（20 + 60 + 8 = 88）放得下，UTC 已收掉 → 档 2
        assertEquals(2, SmallRowLayout.cityRowTier(44f, 20f, 52f, 60f, 100f, 8f))
    }

    @Test
    fun tierZeroOnExtremelyWideRow() {
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 600f, 52f, 60f, 2000f, 8f))
    }

    @Test
    fun tierZeroBeforeFirstMeasure() {
        // 行宽还没量出来（0）时按档 0 排，避免第一帧跳成「只剩地区」
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 300f, 52f, 60f, 0f, 8f))
        assertEquals(0, SmallRowLayout.cityRowTier(44f, 300f, 52f, 60f, -1f, 8f))
    }

    @Test
    fun cityRowHalvesAreEqualAndSumToTheRow() {
        // 档 0 的左右两半与下面两列等宽：各占整行一半
        val (left, right) = SmallRowLayout.cityRowHalves(400f)
        assertEquals(200f, left, 0f)
        assertEquals(200f, right, 0f)
        assertEquals(400f, left + right, 0f)
        // 奇数宽度也不留缝
        val (oddLeft, oddRight) = SmallRowLayout.cityRowHalves(401f)
        assertEquals(200.5f, oddLeft, 0f)
        assertEquals(200.5f, oddRight, 0f)
        assertEquals(401f, oddLeft + oddRight, 0f)
        // 还没量出行宽
        assertEquals(0f to 0f, SmallRowLayout.cityRowHalves(0f))
    }

    @Test
    fun tierZeroRequiresBothHalvesToFit() {
        // 断言档 0 判定用的就是「左右两半各占一半」：地区刚好塞满左半 → 0，
        // 再宽 1px 就越过左半 → 1（右半的宽度不参与这条边界的判断）。
        val row = 400f
        val (leftHalf, rightHalf) = SmallRowLayout.cityRowHalves(row)
        assertEquals(200f, leftHalf, 0f)
        assertEquals(200f, rightHalf, 0f)
        val gap = 8f
        val utc = 44f
        val fitsLeft = leftHalf - utc - gap
        assertEquals(0, SmallRowLayout.cityRowTier(utc, fitsLeft, 52f, 60f, row, gap))
        assertEquals(1, SmallRowLayout.cityRowTier(utc, fitsLeft + 1f, 52f, 60f, row, gap))
    }

    // ---- 竖分隔线要不要上延到标签行顶部 ----

    @Test
    fun dividerReachesLabelRowOnlyInTierZero() {
        // 档 0 的标签行是左右两半，50% 分界与下方两列的分界是同一条线 → 上延
        assertTrue(SmallRowLayout.dividerReachesLabelRow(0))
        // 档 1~3 标签行已合并成一整行，线只盖下方两列
        assertFalse(SmallRowLayout.dividerReachesLabelRow(1))
        assertFalse(SmallRowLayout.dividerReachesLabelRow(2))
        assertFalse(SmallRowLayout.dividerReachesLabelRow(3))
        // 越界值一律不上延（只有档 0 这一种结构需要）
        assertFalse(SmallRowLayout.dividerReachesLabelRow(-1))
        assertFalse(SmallRowLayout.dividerReachesLabelRow(4))
    }

    @Test
    fun dividerFollowsTheTierBoundaries() {
        // 用 [cityRowTier] 的边界把「上延与否」串起来：地区 148 宽仍是档 0（上延），
        // 149 起变档 1（不上延）—— 与真实渲染同一条判定。
        val short = SmallRowLayout.cityRowTier(44f, 148f, 52f, 60f, 400f, 8f)
        val long = SmallRowLayout.cityRowTier(44f, 149f, 52f, 60f, 400f, 8f)
        assertEquals(0, short)
        assertEquals(1, long)
        assertTrue(SmallRowLayout.dividerReachesLabelRow(short))
        assertFalse(SmallRowLayout.dividerReachesLabelRow(long))
    }
}
