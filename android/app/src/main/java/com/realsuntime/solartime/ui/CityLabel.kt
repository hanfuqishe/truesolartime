package com.realsuntime.solartime.ui

/**
 * 卡片 / 标题行上的地名，优先级：
 *
 * 1. **逆地理编码查到的行政区划**（如「上海市宝山区」「Cairo, Cairo Governorate」）；
 * 2. 反查还没回来 / 失败时，只有**内置城市**才回退到它的本地化名字（如「北京」）；
 * 3. 都没有 —— 手动坐标、GPS 定位，或反查失败 —— 就显示占位符 `-`。
 *
 * 第 2 条只认 [presetLabel]（由 `Place.labelResName` 解析得来），**不能**拿上一个地点的名字凑数：
 * 手动输入埃及坐标时 `labelResName` 是 null，若存储层把默认城市（北京）当成兜底读出来，
 * 卡片就会一直写着「北京」——这是本轮修的 bug。纯函数，便于单测。
 *
 * @param districtName 逆地理编码结果；null / 空白表示还没查到或查询失败。
 * @param presetLabel 内置城市的本地化名字；手动坐标与 GPS 为 null。
 * @param unknown 占位符（资源里的 `-`）。
 */
internal fun cityLabel(districtName: String?, presetLabel: String?, unknown: String): String =
    districtName?.takeIf { it.isNotBlank() }
        ?: presetLabel?.takeIf { it.isNotBlank() }
        ?: unknown
