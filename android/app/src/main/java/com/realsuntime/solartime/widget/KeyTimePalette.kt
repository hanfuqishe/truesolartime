package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeTemperature

/**
 * 关键时间段用的配色，取值与首页大卡片一致：
 *
 * - 白天（橙色底）：亮绿/亮红过于抢眼，暗一档反而与底色的明度差更大、更沉稳；
 * - 夜间（深蓝底）：需要亮一档才看得清。
 *
 * 时间轴上的色带、当前时刻的圆点与真太阳时的数字都取这里的颜色，保证三处始终一致。
 */
object KeyTimePalette {

    /** 白天用的暗一档。 */
    val COLD: Int = 0xFF2E7D32.toInt()
    val HOT: Int = 0xFFB3261E.toInt()

    /** 夜间用的亮一档。 */
    val COLD_NIGHT: Int = 0xFF4CAF7D.toInt()
    val HOT_NIGHT: Int = 0xFFD9534F.toInt()

    fun of(temperature: TakeTemperature?, isDay: Boolean): Int? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD else COLD_NIGHT
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT else HOT_NIGHT
        else -> null
    }
}
