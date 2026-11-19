package com.realsuntime.solartime.widget

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * 秒数限宽：任何参数下都必须 **严格小于「两位数字 + 冒号」**，否则 Chronometer 自带的冒号会露出来，
 * 与静态冒号叠成 `::37`。
 */
class ClockWidthMathTest {

    @Test
    fun maxWidthAlwaysLeavesNoRoomForTheChronometerColon() {
        val random = Random(7)
        repeat(500) {
            val digit = random.nextFloat() * 80f + 1f      // 1–81 px
            val colon = random.nextFloat() * 40f + 1f      // 1–41 px
            val slack = random.nextFloat() * 30f           // 0–30 px
            val width = ClockWidthMath.secondsMaxWidthPx(digit, colon, slack)
            assertTrue(
                "digit=$digit colon=$colon slack=$slack width=$width",
                width.toFloat() < 2f * digit + colon,
            )
            // 也不能窄到把两位数字裁掉（允许 1px 的取整误差）。
            assertTrue(
                "digit=$digit width=$width 太窄",
                width.toFloat() >= 2f * digit - 1f,
            )
        }
    }

    /** 余量再大也必须被压到冒号宽以内（以前 2dp 就足够露出冒号）。 */
    @Test
    fun oversizedSlackIsClampedBelowTheColonWidth() {
        val digit = 24f
        val colon = 9f
        val width = ClockWidthMath.secondsMaxWidthPx(digit, colon, slackPx = 100f)
        assertTrue("width=$width", width < (2 * digit + colon).toInt())
        assertTrue("width=$width 应保留两位数字", width >= (2 * digit).toInt())
    }

    /** 余量为 0 / 负数时不额外放宽度。 */
    @Test
    fun nonPositiveSlackAddsNothing() {
        val digit = 24f
        val colon = 9f
        assertTrue(ClockWidthMath.secondsMaxWidthPx(digit, colon, 0f) <= (2 * digit).toInt())
        assertTrue(ClockWidthMath.secondsMaxWidthPx(digit, colon, -5f) <= (2 * digit).toInt())
    }
}
