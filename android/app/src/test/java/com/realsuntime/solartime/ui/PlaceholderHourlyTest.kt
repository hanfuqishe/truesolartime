package com.realsuntime.solartime.ui

import com.realsuntime.solartime.solar.Placeholders
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 未知态（定位不可用）的逐时行占位。
 *
 * 用户口径：**不要**把整行藏起来 —— 六个时间格照常按系统时间往后推，
 * 每格温度写 `--°`、不画天气图标，行高与间距与正常态一致（所以卡片高度不跳）。
 *
 * 这里盯的是纯函数 [placeholderHourCells]，Compose 那层只负责把 null 图标位留空。
 */
class PlaceholderHourlyTest {

    private val nowLabel = "现在"
    private val hourLabel: (Int) -> String = { "${it}时" }

    private fun cells(nowHour: Int) = placeholderHourCells(
        nowHour = nowHour,
        nowLabel = nowLabel,
        hourLabel = hourLabel,
        temperature = Placeholders.temperature(),
    )

    @Test
    fun unknownStateAlwaysHasSixHourlyCells() {
        assertEquals("逐时行必须仍是六格", 6, cells(10).size)
    }

    @Test
    fun firstCellIsNowAndTheRestAdvanceOneHourEach() {
        val list = cells(10)
        assertEquals("现在", list[0].label)
        // 时刻是**照常推算**的：从系统时间那一格起，每小时一格。
        assertEquals(listOf("11时", "12时", "13时", "14时", "15时"), list.drop(1).map { it.label })
        assertEquals(6, list.size)
    }

    /** 跨午夜：22 点起的六格要回绕成 22/23/0/1/2/3（首格仍写「现在」）。 */
    @Test
    fun hourLabelsWrapAroundMidnight() {
        val list = cells(22)
        assertEquals("现在", list[0].label)
        assertEquals(listOf("23时", "0时", "1时", "2时", "3时"), list.drop(1).map { it.label })
    }

    /** 每格温度都是 `--°`，且没有图标（`iconRes == null` 时 UI 只留图标位、不画图）。 */
    @Test
    fun everyCellShowsTheTemperaturePlaceholderAndNoIcon() {
        for (hour in listOf(0, 7, 12, 22, 23)) {
            val list = cells(hour)
            assertEquals("$hour 点起始：六格温度必须全是 --°", 6, list.count { it.temperature == "--°" })
            assertTrue("温度占位符来自 Placeholders", list.all { it.temperature == Placeholders.TEMPERATURE })
            assertEquals(6, list.count { it.iconRes == null })
            assertNull(list.first().iconRes)
        }
    }

    /**
     * 行高不变的结构前提：占位格与真实格一样有「时间标签 + 图标位 + 温度」三段。
     *
     * 图标虽然不画，但 UI 用同尺寸的空 Spacer 占位（见 `HeroHourly`），
     * 所以这一行的高度、以及它与上方时间轴的间距，与正常态完全一致。
     */
    @Test
    fun placeholderCellsKeepTheSameThreePartStructure() {
        val cell = cells(10).first()
        assertTrue("标签非空", cell.label.isNotEmpty())
        assertTrue("温度非空", cell.temperature.isNotEmpty())
        // 没有图标 = 只留位置（正是「行高不跳」的关键）。
        assertNull(cell.iconRes)
    }
}
