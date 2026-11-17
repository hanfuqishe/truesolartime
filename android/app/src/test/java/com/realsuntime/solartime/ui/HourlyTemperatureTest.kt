package com.realsuntime.solartime.ui

import com.realsuntime.solartime.data.WeatherRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneOffset

/**
 * 逐时行图标下面那一行：显示**气温**（`18°`），不再是天气文字。
 *
 * 这套断言跑的就是界面用的那两个纯函数（[hourTemperatures] + [temperatureLabel]）：
 * 首页大卡片的 `HeroHourly` 与桌面小组件的 `bindHourly` 都从这里取数，所以这里过了就等于两边都过了。
 * 单位测试里拿不到 `Context`，格式化按资源的实际模板等价替代：
 * `R.string.weather_temp` = `%1$d°`、`R.string.weather_unknown` = `-`。
 */
class HourlyTemperatureTest {

    private val zoneOffsetSeconds = 8 * 3600

    /** 2026-11-16 的某个 UTC 时刻（测试里统一用它算 epoch，避免手写魔数）。 */
    private fun utc(hour: Int, minute: Int = 0): Long =
        LocalDateTime.of(2026, 11, 16, hour, minute).toEpochSecond(ZoneOffset.UTC)

    private fun points(
        fromEpoch: Long,
        temps: List<Int>,
        stepHours: Int,
        code: Int = 3,
    ): List<WeatherRepository.HourPoint> = temps.mapIndexed { index, temp ->
        WeatherRepository.HourPoint(fromEpoch + index * stepHours * 3600L, temp, code)
    }

    /** 与界面同一个格式化口径（`%1$d°`，缺读数 `-`）。 */
    private fun labels(temperatures: List<Int?>): List<String> =
        temperatures.map { temperatureLabel(it, { value -> "$value°" }, "-") }

    // ---------------------------------------------------------------- 六格的顺序与格式

    /**
     * 主源（1 小时粒度）：本地 21:55 → 现在(21 点)/22时/23时/0时/1时/2时。
     *
     * 六个标签依次是「现在格的实时温度、点1温度、点2温度…」，每个都以 `°` 结尾、
     * 不带 `C`、也不带天气文字。
     */
    @Test
    fun sixSlotsShowTemperaturesStartingWithTheLiveReading() {
        val now = utc(hour = 13, minute = 55) // 本地 21:55
        // 本地 20:00 起每小时一个点，温度 15°、16°、17°…
        val points = points(fromEpoch = utc(hour = 12), temps = (0 until 8).map { 15 + it }, stepHours = 1)
        val temperatures = hourTemperatures(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = zoneOffsetSeconds,
            stepHours = 1,
            currentTemperatureC = 12,
        )
        // 首格是实时读数 12°；之后是各自采样点的温度（21 点那个点是 16°，不是 15°）
        assertEquals(listOf(12, 17, 18, 19, 20, 21), temperatures)

        val labels = labels(temperatures)
        assertEquals(listOf("12°", "17°", "18°", "19°", "20°", "21°"), labels)
        assertEquals(6, labels.size)
        // 格式：数字 + 度符号，不带 C；也没有一格是天气文字
        assertTrue("温度标签应以 ° 结尾，实际 $labels", labels.all { it.endsWith("°") })
        assertTrue(labels.none { it.contains("C") || it.contains("云") || it.contains("雨") })
    }

    /**
     * 备用源（7Timer!）3 小时粒度、且采样点已经过时：
     * 「现在」那一格必须用实时温度，不能用几小时前那个采样点的温度。
     *
     * 本地 21:55 的「现在」是 20:00 那个采样点（15°），而实时读数是 18° —— 首格写 18°，
     * 与卡片日期行里那个温度一致（iOS `HeroCard.HourlyRow` 同一条规则）。
     */
    @Test
    fun nowSlotPrefersTheLiveReadingOverTheStaleSample() {
        val now = utc(hour = 13, minute = 55) // 本地 21:55
        // 7Timer! 的采样网格：UTC 12/15/18/21 点 → 本地 20/23/2/5 点，3 小时一格
        val points = points(
            fromEpoch = utc(hour = 12),
            temps = listOf(15, 14, 13, 14, 15, 16, 17, 18),
            stepHours = 3,
        )
        val temperatures = hourTemperatures(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = zoneOffsetSeconds,
            stepHours = 3,
            currentTemperatureC = 18,
        )
        assertEquals(18, temperatures[0]) // 实时温度，不是采样点的 15°
        assertEquals(listOf(18, 14, 13, 14, 15, 16), temperatures)
        assertEquals(listOf("18°", "14°", "13°", "14°", "15°", "16°"), labels(temperatures))
        // 对照：没有实时读数时才退回采样点温度
        assertEquals(
            15,
            hourTemperatures(points, now, zoneOffsetSeconds, stepHours = 3, currentTemperatureC = null)[0],
        )
    }

    // ---------------------------------------------------------------- 缺读数 → `-`

    @Test
    fun missingTemperaturesFallBackToASingleDash() {
        val now = utc(hour = 13, minute = 55)
        // 一格数据都没有：照样排满 6 格，温度一律占位符 `-`（沿用 weather_unknown，不是 `--`）
        val empty = hourTemperatures(
            points = emptyList(),
            nowEpochSeconds = now,
            zoneOffsetSeconds = zoneOffsetSeconds,
            stepHours = 1,
            currentTemperatureC = null,
        )
        assertEquals(List(6) { null }, empty)
        assertEquals(List(6) { "-" }, labels(empty))

        // 采样点只够头两格：后面的格子没有读数 → `-`
        val partial = hourTemperatures(
            points = points(fromEpoch = utc(hour = 12), temps = listOf(15, 16), stepHours = 1),
            nowEpochSeconds = now,
            zoneOffsetSeconds = zoneOffsetSeconds,
            stepHours = 1,
            currentTemperatureC = null,
        )
        assertEquals(listOf(16, null, null, null, null, null), partial)
        assertEquals(listOf("16°", "-", "-", "-", "-", "-"), labels(partial))
    }

    /** 还没有有效定位时（桌面小组件）整行都写 `-`：兜底坐标的天气不能被当成本地读数。 */
    @Test
    fun unknownPlaceShowsPlaceholdersOnly() {
        val now = utc(hour = 13, minute = 55)
        val temperatures = hourTemperatures(
            points = points(fromEpoch = utc(hour = 12), temps = listOf(15, 16, 17, 18, 19, 20, 21, 22), stepHours = 1),
            nowEpochSeconds = now,
            zoneOffsetSeconds = zoneOffsetSeconds,
            stepHours = 1,
            currentTemperatureC = 12,
            hasFix = false,
        )
        assertEquals(List(6) { null }, temperatures)
        assertEquals(List(6) { "-" }, labels(temperatures))
    }

    // ---------------------------------------------------------------- 桌面第二排

    /**
     * 桌面卡片第二排逐时行（平板加料）接在第一排后面：按**格数**跳过前 6 格，
     * 且永远没有「现在」那一格 —— 因此也不能用实时温度。
     */
    @Test
    fun secondHourRowKeepsSampledTemperaturesAndHasNoNowSlot() {
        val now = utc(hour = 13, minute = 55)
        val points = points(fromEpoch = utc(hour = 12), temps = (0 until 14).map { 10 + it }, stepHours = 3)
        val temperatures = hourTemperatures(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = zoneOffsetSeconds,
            stepHours = 3,
            currentTemperatureC = 99,
            skip = 6,
        )
        assertFalse("第二排不该出现实时温度", temperatures.contains(99))
        assertEquals(listOf(16, 17, 18, 19, 20, 21), temperatures)
        assertEquals(listOf("16°", "17°", "18°", "19°", "20°", "21°"), labels(temperatures))
    }

    // ---------------------------------------------------------------- 格式化本身

    @Test
    fun temperatureLabelFormatsDegreesAndNeverDoublesTheDash() {
        val degrees: (Int) -> String = { "$it°" }
        assertEquals("18°", temperatureLabel(18, degrees, "-"))
        assertEquals("-3°", temperatureLabel(-3, degrees, "-"))
        assertEquals("0°", temperatureLabel(0, degrees, "-"))
        assertEquals("-", temperatureLabel(null, degrees, "-"))
    }
}
