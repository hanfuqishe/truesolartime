package com.realsuntime.solartime.solar

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalTime

class TimeFormatTest {

    @Test
    fun utcOffsetLabelCoversWholeAndFractionalHours() {
        assertEquals("UTC+8", TimeFormat.utcOffsetLabel(8 * 3600))
        assertEquals("UTC-5", TimeFormat.utcOffsetLabel(-5 * 3600))
        assertEquals("UTC+0", TimeFormat.utcOffsetLabel(0))
        // 半小时／三刻钟时区要带分钟，不能四舍五入成整点。
        assertEquals("UTC+5:30", TimeFormat.utcOffsetLabel(5 * 3600 + 30 * 60))
        assertEquals("UTC-3:30", TimeFormat.utcOffsetLabel(-(3 * 3600 + 30 * 60)))
        assertEquals("UTC+5:45", TimeFormat.utcOffsetLabel(5 * 3600 + 45 * 60))
    }

    @Test
    fun clockFallsBackToPlaceholderWhenTimeIsMissing() {
        assertEquals("--:--", TimeFormat.clock(null))
        assertEquals("05:06", TimeFormat.clock(LocalTime.of(5, 6, 30)))
    }
}
