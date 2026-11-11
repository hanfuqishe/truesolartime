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
    fun beepIsHalfASecondAtTwoKilohertz() {
        val samples = Chime.samples(500)
        // 22050 Hz × 0.5 s
        assertEquals(11_025, samples.size)
        assertEquals(2_000.0, Chime.BEEP_HZ, 0.0)

        // 首尾各有淡入淡出，中间振幅应接近满量程的 60%
        assertEquals(0, samples.first().toInt())
        assertEquals(0, samples.last().toInt())
        val peak = samples.maxOf { abs(it.toInt()) }
        assertTrue("peak=$peak", peak in 17_000..19_700)

        // 一个完整周期（22050/2000 ≈ 11 个采样点）之后相位应回到相近位置
        val period = (22_050.0 / 2_000.0).toInt()
        assertTrue(abs(samples[2_000] - samples[2_000 + period]) < 2_000)
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
        assertTrue(Chime.shouldPlay(nowMillis = 1_000, lastPlayedMillis = 0))       // 从未响过
        assertTrue(Chime.shouldPlay(nowMillis = 1_000, lastPlayedMillis = 100))     // 900 ms 前
        assertFalse(Chime.shouldPlay(nowMillis = 1_000, lastPlayedMillis = 960))    // 40 ms 前 → 跳过
        assertFalse(Chime.shouldPlay(nowMillis = 1_000, lastPlayedMillis = 400))    // 600 ms 前 → 仍在窗口内
        assertTrue(Chime.shouldPlay(nowMillis = 1_000, lastPlayedMillis = 200))     // 800 ms 前 → 可以再响
    }

    @Test
    fun shichenChimeIsShorter() {
        // 250 ms
        assertEquals(5_512, Chime.samples(250).size)
    }
}
