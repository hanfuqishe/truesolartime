package com.realsuntime.solartime.widget

import org.junit.Assert.assertEquals
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
    fun shichenChimeIsShorter() {
        // 250 ms
        assertEquals(5_512, Chime.samples(250).size)
    }
}
