package com.realsuntime.solartime.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `CardFontMath` 的单元测试。
 *
 * 这台机器上没有华为真机也能验的，就是「反解公式」本身：必须保证
 *   request(nominal) 经过系统那一层之后又回到 nominal
 * 加法与乘法两条通道分别成立、同时开也成立，且不会越界。
 */
class CardFontMathTest {

    /** 加法通道：渲染值 = 请求值 + adjustment，所以反解后再加回去必须等于 nominal。 */
    @Test
    fun additiveChannelRoundTrips() {
        for (nominal in listOf(400, 500, 600)) {
            for (adjustment in listOf(0, 50, 100, 200, 300)) {
                val requested = CardFontMath.requestWeight(nominal, adjustment, 1f)
                assertEquals(
                    "nominal=$nominal adjustment=$adjustment",
                    nominal,
                    requested + adjustment,
                )
            }
        }
    }

    /** 乘法通道：渲染值 = 请求值 × scale，反解后再乘回去必须接近 nominal（允许 1 的取整误差）。 */
    @Test
    fun multiplicativeChannelRoundTrips() {
        for (nominal in listOf(400, 500, 600)) {
            for (scale in listOf(1f, 1.1f, 1.15f, 1.2f, 1.5f, 2f)) {
                val requested = CardFontMath.requestWeight(nominal, 0, scale)
                val rendered = requested * scale
                assertEquals(
                    "nominal=$nominal scale=$scale requested=$requested",
                    nominal.toFloat(),
                    rendered,
                    1.05f,
                )
            }
        }
    }

    /** 两条通道同时开（华为 ROM 上 AOSP 的加粗也开着）：先加后乘的反解同样成立。 */
    @Test
    fun bothChannelsRoundTrip() {
        val nominal = 500
        val adjustment = 100
        val scale = 1.2f
        val requested = CardFontMath.requestWeight(nominal, adjustment, scale)
        // 按「先加后乘」还原系统那一层：rendered = (requested + adjustment) * scale。
        val rendered = (requested + adjustment) * scale
        assertEquals(nominal.toFloat(), rendered, 1.3f)
    }

    /** 越界钳位：字重不能低于 1、不能高于 1000。 */
    @Test
    fun weightsAreClamped() {
        assertEquals(1, CardFontMath.requestWeight(400, 1000, 1f))
        assertEquals(1000, CardFontMath.requestWeight(1000, 0, 0.5f))
    }

    /** 非法 scale（0 / 负数 / NaN）当作「没有乘法通道」，不能把字重算成负数或 NaN。 */
    @Test
    fun invalidScaleIsIgnored() {
        listOf(0f, -1.2f, Float.NaN, Float.POSITIVE_INFINITY).forEach { scale ->
            assertEquals("scale=$scale", 500, CardFontMath.requestWeight(500, 0, scale))
        }
    }

    /** 诊断用的偏移量：ratio 1.2 在 500 上相当于 +100。 */
    @Test
    fun scaleDeltaMatchesWeightOffset() {
        assertEquals(100, CardFontMath.scaleWeightDelta(500, 1.2f))
        assertEquals(0, CardFontMath.scaleWeightDelta(500, 1f))
        assertEquals(0, CardFontMath.scaleWeightDelta(500, 0f))
    }

    /**
     * 华为两个键 → 倍率：正常态 0.79/0.79 必须得 1.0（不补偿），
     * 只有「加粗」把 font_weight_scale 抬上去才 > 1。
     */
    @Test
    fun huaweiRatioUsesNormalReference() {
        assertEquals(1f, CardFontMath.huaweiScaleRatio(0.79f, 0.79f), 1e-6f)
        assertEquals(1.2658228f, CardFontMath.huaweiScaleRatio(1.0f, 0.79f), 1e-5f)
        // 键缺失 / 非法值一律退回 1：宁可不补偿，也不能凭空改字重。
        assertEquals(1f, CardFontMath.huaweiScaleRatio(null, 0.79f), 0f)
        assertEquals(1f, CardFontMath.huaweiScaleRatio(1.0f, null), 0f)
        assertEquals(1f, CardFontMath.huaweiScaleRatio(1.0f, 0f), 0f)
        assertEquals(1f, CardFontMath.huaweiScaleRatio(Float.NaN, 0.79f), 0f)
    }

    /**
     * 华为「加粗」实况推演：normal=0.79，加粗把 scale 抬到 1.0（倍率 1.266）。
     * 目标 Medium(500) 时应请求 ≈395，反解后 395 × 1.266 ≈ 500。
     */
    @Test
    fun huaweiBoldCompensatesToMedium() {
        val ratio = CardFontMath.huaweiScaleRatio(1.0f, 0.79f)
        val requested = CardFontMath.requestWeight(500, 0, ratio)
        val rendered = requested * ratio
        assertEquals(500f, rendered, 2f)
    }

    /**
     * 「字体粗细」滑杆的默认档常量：只用来给诊断日志做参照，
     * 它的存在提醒后来人 `font_weight_scale_normal` 是镜像、不能当基线。
     */
    @Test
    fun huaweiDefaultScaleIsDocumented() {
        assertEquals(0.79f, CardFontMath.HUAWEI_DEFAULT_WEIGHT_SCALE, 1e-6f)
    }
}
