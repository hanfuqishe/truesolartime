package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeTemperature

/**
 * 关键时间段用的配色，取值与首页大卡片一致：
 *
 * - 真太阳时的数字：白天用与淡金同浓度的淡绿/淡红，深绿/深红压在橙底上发闷；
 * - 时间轴上的色段与当前时刻的圆点：淡色在橙底上几乎看不出边界，仍用深一档；
 * - 夜间（深蓝底）：两种用途共用亮一档的颜色。
 */
object KeyTimePalette {

    /** 白天数字用的淡绿/淡红。 */
    val COLD_INK: Int = 0xFFBCF5CA.toInt()
    val HOT_INK: Int = 0xFFFFC4C9.toInt()

    /** 白天色段用的深绿/深红。 */
    val COLD_BAND: Int = 0xFF2E7D32.toInt()
    val HOT_BAND: Int = 0xFFB3261E.toInt()

    /** 夜间用的亮一档。 */
    val COLD_NIGHT: Int = 0xFF4CAF7D.toInt()
    val HOT_NIGHT: Int = 0xFFD9534F.toInt()

    /** 真太阳时数字的颜色。 */
    fun ink(temperature: TakeTemperature?, isDay: Boolean): Int? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_INK else COLD_NIGHT
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_INK else HOT_NIGHT
        else -> null
    }

    /** 时间轴色段与圆点的颜色。 */
    fun band(temperature: TakeTemperature?, isDay: Boolean): Int? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_BAND else COLD_NIGHT
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_BAND else HOT_NIGHT
        else -> null
    }
}