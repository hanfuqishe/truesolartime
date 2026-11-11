package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeBand
import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetAxisTest {

    @Test
    fun shiftsBandsBySolarOffset() {
        // 15:00-17:00（900-1020）平移 +21.6 分钟后仍是同一段
        val spans = WidgetAxis.solarSpans(listOf(TakeBand(900, 1020)), 21.6)
        assertEquals(1, spans.size)
        assertEquals(921.6, spans[0].startMinutes, 0.001)
        assertEquals(1041.6, spans[0].endMinutes, 0.001)
    }

    @Test
    fun shiftsCrossMidnightBandIntoTheEarlyHours() {
        // 23:50-00:30（跨午夜，长 40 分钟）平移 +21.6 分钟 → 真太阳时 00:11.6-00:51.6
        val spans = WidgetAxis.solarSpans(listOf(TakeBand(1430, 30)), 21.6)
        assertEquals(1, spans.size)
        assertEquals(11.6, spans[0].startMinutes, 0.001)
        assertEquals(51.6, spans[0].endMinutes, 0.001)
    }

    @Test
    fun splitsBandThatPastTheEndOfTheDay() {
        // 23:50-00:30 平移 -21.6 分钟 → 23:28.4 起 40 分钟，越过 24:00，拆成两段
        val spans = WidgetAxis.solarSpans(listOf(TakeBand(1430, 30)), -21.6)
        assertEquals(2, spans.size)
        assertEquals(1408.4, spans[0].startMinutes, 0.001)
        assertEquals(1440.0, spans[0].endMinutes, 0.001)
        assertEquals(0.0, spans[1].startMinutes, 0.001)
        assertEquals(8.4, spans[1].endMinutes, 0.001)
    }

    @Test
    fun wrapsNegativeOffset() {
        // 05:00-06:00 平移 -21.6 分钟 → 04:38.4-05:38.4
        val spans = WidgetAxis.solarSpans(listOf(TakeBand(300, 360)), -21.6)
        assertEquals(1, spans.size)
        assertEquals(278.4, spans[0].startMinutes, 0.001)
        assertEquals(338.4, spans[0].endMinutes, 0.001)
    }

    @Test
    fun keepsOrderAndHandlesEmptyList() {
        assertEquals(0, WidgetAxis.solarSpans(emptyList(), 0.0).size)
        val spans = WidgetAxis.solarSpans(listOf(TakeBand(900, 1020), TakeBand(600, 720)), 0.0)
        assertEquals(2, spans.size)
        assertEquals(900.0, spans[0].startMinutes, 0.001)
        assertEquals(600.0, spans[1].startMinutes, 0.001)
    }
}
