package com.realsuntime.solartime.data

import com.realsuntime.solartime.ui.cityLabel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 手动坐标的地名显示（回归用例：「输入埃及坐标，地名却还是北京」）。
 *
 * 根因链有两处，这里都钉住：
 * 1. `AppSettings.place` 的读取把默认城市名（`city_beijing`）当成兜底，手动坐标的 `labelResName`
 *    被 `putString(key, null)` 删掉后又读回默认值 → 卡片写着「北京」；
 * 2. 显示层在没有反查结果时，不能拿上一个地点的名字凑数，只能显示 `-`。
 */
class ManualPlaceNameTest {

    private fun manualPlace(labelResName: String? = null): Place = placeFromStored(
        latitudeRaw = "25.2048",
        longitudeRaw = "30.2708",
        sourceRaw = "MANUAL",
        labelRaw = "手动设置",
        labelResNameRaw = labelResName,
        countryCodeRaw = "",
    )

    /** 手动坐标存过之后，读出来仍是「没有城市名」：不能被默认城市（北京）顶替。 */
    @Test
    fun manualPlaceKeepsNoPresetLabel() {
        val place = manualPlace()
        assertNull("手动坐标不应回填默认城市名", place.labelResName)
        assertEquals(PlaceSource.MANUAL, place.source)
        assertEquals(25.2048, place.latitude, 1e-9)
        assertEquals(30.2708, place.longitude, 1e-9)
    }

    /** 手动坐标 + 反查失败（没有区划名）→ 地名显示 `-`。 */
    @Test
    fun failedLookupForManualCoordinateShowsDash() {
        val place = manualPlace()
        val preset = place.labelResName?.let { "北京" }
        assertEquals("-", cityLabel(districtName = null, presetLabel = preset, unknown = "-"))

        // 旧城市的缓存名字必须被距离判定拒绝：北京 → 埃及 ≈ 7400 km，远超 5 km 阈值。
        val movedKm = CityIndex.distanceKm(39.9042, 116.4074, place.latitude, place.longitude)
        assertTrue("北京到埃及应远超阈值：$movedKm", movedKm > 1000.0)
        assertFalse(DistrictResolver.trustsNameAt(movedKm))
    }

    /** 手动坐标 + 反查成功 → 显示反查结果（优先级最高）。 */
    @Test
    fun successfulLookupWinsOverThePlaceholder() {
        val resolved = "开罗省, 开罗"
        assertEquals(resolved, cityLabel(districtName = resolved, presetLabel = null, unknown = "-"))
    }

    /** 先选预设城市（北京）再改手动坐标：旧地名的资源名不能残留。 */
    @Test
    fun switchingFromPresetCityDoesNotLeaveTheOldName() {
        val beijing = placeFromStored(
            latitudeRaw = "39.9042",
            longitudeRaw = "116.4074",
            sourceRaw = "MANUAL",
            labelRaw = "",
            labelResNameRaw = "city_beijing",
            countryCodeRaw = "cn",
        )
        assertEquals("city_beijing", beijing.labelResName)

        val egypt = manualPlace()
        assertNull("换到手动坐标后不能再带着北京的资源名", egypt.labelResName)
        // 显示层：反查没回来 + 没有预设名 → 「-」，不会是「北京」。
        val presetLabel = egypt.labelResName?.let { "北京" }
        assertEquals("-", cityLabel(districtName = null, presetLabel = presetLabel, unknown = "-"))
    }

    /** 全新安装（一个地点都没存过）仍显示默认城市北京，不能因为这个修复把首屏变成「-」。 */
    @Test
    fun freshInstallStillShowsTheDefaultCity() {
        val place = placeFromStored(null, null, null, null, null, null)
        assertEquals(PlaceSource.DEFAULT, place.source)
        assertEquals("city_beijing", place.labelResName)
        assertEquals("北京", cityLabel(districtName = null, presetLabel = "北京", unknown = "-"))
    }

    /** GPS 定位同样没有城市名：等反查，失败就是 `-`。 */
    @Test
    fun gpsPlaceHasNoPresetLabelEither() {
        val place = placeFromStored("25.2048", "30.2708", "GPS", "GPS", null, "")
        assertNull(place.labelResName)
        assertEquals("-", cityLabel(districtName = null, presetLabel = null, unknown = "-"))
    }
}
