package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeBand
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyTimeChimeTest {

    private val bands = listOf(
        TakeBand(900, 1020),   // 15:00-17:00
        TakeBand(1200, 1320),  // 20:00-22:00
        TakeBand(600, 720),    // 10:00-12:00
    )

    @Test
    fun picksTheNearestUpcomingStart() {
        // 11:00 → 下一段起点是 15:00，还有 4 小时
        assertEquals(4 * 3600.0, KeyTimeChime.secondsToNextStart(11 * 3600.0, bands)!!, 0.001)
    }

    @Test
    fun wrapsAroundToTheNextDay() {
        // 21:00 → 今天的 10:00 已过，等明天的 10:00（13 小时）
        assertEquals(13 * 3600.0, KeyTimeChime.secondsToNextStart(21 * 3600.0, bands)!!, 0.001)
    }

    @Test
    fun waitsForTheNextStartWhenStandingOnOne() {
        // 正好踩在 15:00 的边界上 → 下一段是 20:00（5 小时后），不会立刻重响
        assertEquals(5 * 3600.0, KeyTimeChime.secondsToNextStart(15 * 3600.0, bands)!!, 0.001)
    }

    @Test
    fun waitsWholeDayWhenTheLastStartOfTheDayIsReached() {
        // 只有一段且正好在它的起点上 → 等明天的同一时刻
        assertEquals(
            86_400.0,
            KeyTimeChime.secondsToNextStart(15 * 3600.0, listOf(TakeBand(900, 1020)))!!,
            0.001,
        )
    }

    @Test
    fun returnsNullWithoutKeyTimes() {
        assertNull(KeyTimeChime.secondsToNextStart(11 * 3600.0, emptyList()))
    }

    /**
     * 回归「报时会响两声」：触发时刻必须**不早于**边界。
     *
     * 真太阳时的边界不是整秒：距离起点还有 0.2 秒时，四舍五入会排到「立刻」，
     * 响完重排又把同一段算回来 → 再响一声；向上取整排到 +200 ms，一定落在边界之后。
     */
    @Test
    fun triggerNeverLandsBeforeTheBoundary() {
        val now = 1_700_000_000_000L
        assertEquals(now + 200, KeyTimeChime.triggerFrom(now, 0.2))
        assertEquals(now + 1_500, KeyTimeChime.triggerFrom(now, 1.5))
        assertEquals(now + 60_000, KeyTimeChime.triggerFrom(now, 60.0))
        listOf(0.001, 0.2, 0.499, 0.5, 0.501, 3.333).forEach { delta ->
            val fired = KeyTimeChime.triggerFrom(now, delta)
            assertTrue("delta=$delta", fired - now >= (delta * 1000).toLong())
        }
    }
}
