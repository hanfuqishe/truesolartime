package com.realsuntime.solartime.ui

import com.realsuntime.solartime.data.PlaceSource

/**
 * 首页标题行（齿轮图标左边）的位置徽标规则。
 *
 * 只有**跟随 GPS** 时才显示 `GPS` 小徽标：它提示的是「这个位置来自定位」，而不是地名。
 * 选了预设城市、或手动输入经纬度时不显示任何东西 —— 地名已经在下方大卡片里，
 * 标题行再放一份只会挤掉标题，长地址还会被截成「New …」。
 *
 * 不显示时调用方直接**不渲染**这个 `Text`（`null`，不是空串）：标题列本来就吃满
 * 剩余宽度，徽标缺席时不会留下占位空隙，标题自然变宽。
 */
object HeaderBadge {

    /** 该来源要不要显示 `GPS` 徽标。预设城市 / 手动坐标一律不显示。 */
    fun showsGps(source: PlaceSource): Boolean = source == PlaceSource.GPS

    /**
     * 徽标文本：跟随 GPS 时是 [gpsLabel]（调用方传本地化后的资源），其余情况是 `null`。
     *
     * @param source 当前观测点的来源
     * @param gpsLabel 已本地化的 `GPS` 文案（`R.string.location_badge_gps`）
     */
    fun textFor(source: PlaceSource, gpsLabel: String): String? =
        if (showsGps(source)) gpsLabel else null
}
