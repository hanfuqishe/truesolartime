package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.notify.ShiChenReminder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class ChimeTest {

    @Test
    fun beepIsHalfASecondAtThirtyTwoHundredHertz() {
        val samples = Chime.samples(500)
        // 22050 Hz × 0.5 s
        assertEquals(11_025, samples.size)
        assertEquals(3_200.0, Chime.BEEP_HZ, 0.0)

        // 首尾各有淡入淡出，中间振幅应接近满量程的 60%
        assertEquals(0, samples.first().toInt())
        assertEquals(0, samples.last().toInt())
        val peak = samples.maxOf { abs(it.toInt()) }
        assertTrue("peak=$peak", peak in 13_300..13_800)

        // 22050/3200 ≈ 6.89 个采样点一个周期：累计 8 个周期后相位接近回到原点
        val period = (22_050.0 / 3_200.0 * 9).toInt()
        assertTrue(abs(samples[1_000] - samples[1_000 + period]) < 6_000)
    }

    @Test
    fun shichenYieldsToLongerKeyTimeBeep() {
        val bands = listOf(TakeBand(900, 1020), TakeBand(1200, 1320))

        // 真太阳时 15:00 正是关键时间起点 → 交接让位（否则会响短的 250 ms）
        assertTrue(ShiChenReminder.collidesWithKeyStart(900.0, bands))
        assertTrue(ShiChenReminder.collidesWithKeyStart(900.4, bands))
        // 15:30 不在起点上 → 互相独立
        assertFalse(ShiChenReminder.collidesWithKeyStart(930.0, bands))
        // 没有关键时间数据时不撞车
        assertFalse(ShiChenReminder.collidesWithKeyStart(900.0, emptyList()))
        // 跨午夜：起点 23:50
        assertTrue(ShiChenReminder.collidesWithKeyStart(1430.2, listOf(TakeBand(1430, 30))))
        assertFalse(ShiChenReminder.collidesWithKeyStart(1439.9, listOf(TakeBand(1430, 30))))

        // 关键时间报时确实比交接更长
        assertTrue(KeyTimeChime.BEEP_MILLIS > ShiChenReminder.BEEP_MILLIS)
    }

    @Test
    fun mergesTwoRemindersThatFireTogether() {
        // 15:00 既是关键时间起点、又是时辰交接：两个闹钟只差几十毫秒
        assertTrue(Chime.shouldPlay(nowMillis = 10_000, lastPlayedMillis = 0))       // 从未响过
        assertFalse(Chime.shouldPlay(nowMillis = 10_000, lastPlayedMillis = 9_960))  // 40 ms 前 → 跳过
        assertFalse(Chime.shouldPlay(nowMillis = 10_000, lastPlayedMillis = 9_000))  // 1 s 前 → 仍跳过
        assertFalse(Chime.shouldPlay(nowMillis = 10_000, lastPlayedMillis = 8_000))  // 2 s 前 → 仍跳过
        assertTrue(Chime.shouldPlay(nowMillis = 10_000, lastPlayedMillis = 7_400))   // 2.6 s 前 → 可以再响
    }

    /**
     * 回归「报时会响两声」：第一声准点，隔 1~2 秒又响一声。
     *
     * 成因：关键时间按真太阳时算，边界不是整秒；闹钟比边界早到零点几秒时，
     * 响完就地重排会把同一段边界算回来，于是又排出一个一秒后的闹钟。
     * 现在三道防线：触发点向上取整、重排参考时刻后推 SETTLE_SECONDS、2.5 秒内重复播放一律丢弃。
     */
    @Test
    fun secondBeepWithinSettleWindowIsDropped() {
        val first = 10_000L                       // 第一声播放于 t=10s（0 是「从未响过」的哨兵值，不能当基准）
        assertFalse(Chime.shouldPlay(nowMillis = first + 1_200, lastPlayedMillis = first))
        assertFalse(Chime.shouldPlay(nowMillis = first + 2_000, lastPlayedMillis = first))
        assertTrue(Chime.shouldPlay(nowMillis = first + 3_000, lastPlayedMillis = first))
    }

    @Test
    fun shichenChimeIsShorter() {
        // 250 ms
        assertEquals(2_205, Chime.samples(100).size)
    }
}
