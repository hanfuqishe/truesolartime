package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import kotlin.random.Random

class TakeTimeRepositoryTest {

    /** 取自 https://www.duosuccess.com/tcm/001a01080301b01a.htm 的实际内容（含标签与全角空格）。 */
    private val page = """
        <html><body>
        <p>服用時間&nbsp;Take Time : 15:00-17:00　20:00-22:00　10:00-12:00　(凍或溫 Cold or Mild)</p>
        <p>黑豆 6粒　西米 2粒</p>
        </body></html>
    """.trimIndent()

    @Test
    fun parsesThreeBandsAndColdMarker() {
        val schedule = TakeTimeRepository.parse(page)
        assertEquals(
            listOf(TakeBand(900, 1020), TakeBand(1200, 1320), TakeBand(600, 720)),
            schedule?.bands,
        )
        assertEquals(TakeTemperature.COLD_OR_MILD, schedule?.temperature)
    }

    @Test
    fun parsesHotMarker() {
        val hot = page.replace("Cold or Mild", "Hot or Mild").replace("凍或溫", "熱或溫")
        assertEquals(TakeTemperature.HOT_OR_MILD, TakeTimeRepository.parse(hot)?.temperature)
    }

    @Test
    fun returnsNullWhenThePageHasNoTimeLine() {
        assertNull(TakeTimeRepository.parse("<html><body>页面改版了</body></html>"))
        assertNull(TakeTimeRepository.parse("Take Time : 稍後公佈"))
    }

    @Test
    fun keepsScheduleWithoutMarker() {
        val plain = page.replace("(凍或溫 Cold or Mild)", "")
        val schedule = TakeTimeRepository.parse(plain)
        assertEquals(3, schedule?.bands?.size)
        assertNull(schedule?.temperature)
    }

    @Test
    fun handlesCrossMidnightBand() {
        val late = page.replace("15:00-17:00", "23:30-01:00")
        assertEquals(TakeBand(1410, 60), TakeTimeRepository.parse(late)?.bands?.first())
    }

    @Test
    fun syncsOnceADayInsideTheRandomWindow() {
        val day = LocalDate.of(2026, 11, 11)
        val zone = ZoneId.of("Asia/Shanghai")
        val target = TakeTimeRepository.pickTargetMillis(day, zone, offsetMinutes = 150)
        // 目标时刻 = 当天 02:30
        assertEquals(day.atTime(2, 30).atZone(zone).toInstant().toEpochMilli(), target)

        // 今天已成功 → 不再同步
        assertFalse(
            TakeTimeRepository.shouldSync(
                nowMillis = target + 3_600_000,
                targetMillis = target,
                today = "2026-11-11",
                lastSuccessDay = "2026-11-11",
                lastAttemptMillis = 0L,
            ),
        )
        // 目标时刻未到 → 不同步
        assertFalse(
            TakeTimeRepository.shouldSync(
                nowMillis = target - 1,
                targetMillis = target,
                today = "2026-11-11",
                lastSuccessDay = "2026-11-10",
                lastAttemptMillis = 0L,
            ),
        )
        // 到达目标时刻且今天没成功 → 同步
        assertTrue(
            TakeTimeRepository.shouldSync(
                nowMillis = target,
                targetMillis = target,
                today = "2026-11-11",
                lastSuccessDay = "2026-11-10",
                lastAttemptMillis = 0L,
            ),
        )
    }

    @Test
    fun retriesEveryHourAfterAFailure() {
        val hour = 3_600_000L
        val target = 1_000_000L
        val failedAt = target + 5L

        // 刚失败不久 → 不重试
        assertFalse(
            TakeTimeRepository.shouldSync(target + hour, target, "2026-11-11", null, failedAt),
        )
        // 满一小时 → 重试
        assertTrue(
            TakeTimeRepository.shouldSync(failedAt + hour + 1, target, "2026-11-11", null, failedAt),
        )
        // 重试成功当天不再同步
        assertFalse(
            TakeTimeRepository.shouldSync(
                failedAt + 2 * hour,
                target,
                "2026-11-11",
                "2026-11-11",
                failedAt + hour,
            ),
        )
    }

    @Test
    fun syncWindowStaysBetweenOneAndFiveAm() {
        val day = LocalDate.of(2026, 11, 11)
        val zone = ZoneId.of("Asia/Shanghai")
        val midnight = day.atStartOfDay(zone).toInstant().toEpochMilli()
        repeat(200) {
            val offset = 60 + Random.nextInt(300 - 60)
            assertTrue(TakeTimeRepository.isInsideSyncWindow(offset))
            val minutes = (TakeTimeRepository.pickTargetMillis(day, zone, offset) - midnight) / 60_000
            assertTrue("offset=$offset", minutes in 60..299)
        }
        assertFalse(TakeTimeRepository.isInsideSyncWindow(59))
        assertFalse(TakeTimeRepository.isInsideSyncWindow(300))
    }

    @Test
    fun bandContainsReportsWhetherNowIsInside() {
        val band = TakeBand(900, 1020) // 15:00-17:00
        assertTrue(band.contains(900.0))
        assertTrue(band.contains(950.5))
        assertFalse(band.contains(1020.0))
        assertFalse(band.contains(899.9))

        // 跨午夜：23:50-00:30
        val late = TakeBand(1430, 30)
        assertTrue(late.contains(1440.0 - 5))   // 23:55
        assertTrue(late.contains(0.0))
        assertTrue(late.contains(29.9))
        assertFalse(late.contains(30.0))
        assertFalse(late.contains(600.0))
    }

    @Test
    fun cacheStaysValidForSevenDaysOnly() {
        assertTrue(TakeTimeRepository.isFresh(0L))
        assertTrue(TakeTimeRepository.isFresh(7L * 24 * 60 * 60 * 1000))
        assertFalse(TakeTimeRepository.isFresh(7L * 24 * 60 * 60 * 1000 + 1))
        // 时间戳异常（未来时间）也不采信
        assertFalse(TakeTimeRepository.isFresh(-1L))
    }

    @Test
    fun bandsRoundTripThroughCache() {
        val bands = listOf(TakeBand(900, 1020), TakeBand(1410, 60))
        assertEquals(bands, TakeTimeRepository.decodeBands(TakeTimeRepository.encodeBands(bands)))
        assertNull(TakeTimeRepository.decodeBands(null))
        assertNull(TakeTimeRepository.decodeBands(""))
        assertEquals(emptyList<TakeBand>(), TakeTimeRepository.decodeBands("garbage"))
    }
}
