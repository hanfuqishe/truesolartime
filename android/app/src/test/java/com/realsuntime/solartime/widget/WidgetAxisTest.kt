package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeBand
import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetAxisTest {

    @Test
    fun keepsKeyTimesAsTrueSolarTimes() {
        // 页面上的时间直接当真太阳时用，不做任何换算
        val spans = WidgetAxis.spans(listOf(TakeBand(900, 1020)))
        assertEquals(1, spans.size)
        assertEquals(900.0, spans[0].startMinutes, 0.001)
        assertEquals(1020.0, spans[0].endMinutes, 0.001)
    }

    @Test
    fun splitsBandThatPastTheEndOfTheDay() {
        // 23:50-00:30（长 40 分钟）在 0–24 的线性轴上拆成两段
        val spans = WidgetAxis.spans(listOf(TakeBand(1430, 30)))
        assertEquals(2, spans.size)
        assertEquals(1430.0, spans[0].startMinutes, 0.001)
        assertEquals(1440.0, spans[0].endMinutes, 0.001)
        assertEquals(0.0, spans[1].startMinutes, 0.001)
        assertEquals(30.0, spans[1].endMinutes, 0.001)
    }

    @Test
    fun keepsAllThreeBandsInOrder() {
        val spans = WidgetAxis.spans(
            listOf(TakeBand(900, 1020), TakeBand(1200, 1320), TakeBand(600, 720)),
        )
        assertEquals(3, spans.size)
        assertEquals(900.0, spans[0].startMinutes, 0.001)
        assertEquals(1200.0, spans[1].startMinutes, 0.001)
        assertEquals(600.0, spans[2].startMinutes, 0.001)
    }

    @Test
    fun handlesEmptyList() {
        assertEquals(0, WidgetAxis.spans(emptyList()).size)
    }
}
