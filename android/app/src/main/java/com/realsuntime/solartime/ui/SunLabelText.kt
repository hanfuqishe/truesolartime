package com.realsuntime.solartime.ui

/**
 * 圆盘「上中天」标签的文案拼装（纯函数，单测直接盯结尾的方位后缀）。
 *
 * 圆盘是「面朝赤道的竖直平面」投影：北半球观察者面朝南、南半球面朝北，
 * 把上中天时的方位标在标签里，用户就不会把日出方向看反。
 */
object SunLabelText {

    /**
     * @param prefix 本地化的「上中天」/「Transit」/「上中天」
     * @param time 已格式化好的 `HH:mm`
     * @param latitude 观测点纬度：`< 0` 为南半球
     * @param dueSouth 本地化的「正南」（英文 `S`）
     * @param dueNorth 本地化的「正北」（英文 `N`）
     */
    fun noonLabel(
        prefix: String,
        time: String,
        latitude: Double,
        dueSouth: String,
        dueNorth: String,
    ): String = "$prefix $time · " + if (latitude < 0.0) dueNorth else dueSouth
}
