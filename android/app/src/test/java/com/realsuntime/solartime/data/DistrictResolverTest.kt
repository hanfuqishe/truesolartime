package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DistrictResolverTest {

    @Test
    fun queriesOnlyAfterMovingMoreThanFiveKilometres() {
        val fresh = 60_000L
        assertFalse(DistrictResolver.shouldQuery(movedKm = 0.0, ageMillis = fresh))
        assertFalse(DistrictResolver.shouldQuery(movedKm = 4.9, ageMillis = fresh))
        assertFalse(DistrictResolver.shouldQuery(movedKm = 5.0, ageMillis = fresh))
        assertTrue(DistrictResolver.shouldQuery(movedKm = 5.1, ageMillis = fresh))
        assertTrue(DistrictResolver.shouldQuery(movedKm = 42.0, ageMillis = fresh))
    }

    @Test
    fun queriesAgainWhenCacheExpires() {
        val tooOld = 31L * 24 * 60 * 60 * 1000
        assertTrue(DistrictResolver.shouldQuery(movedKm = 0.0, ageMillis = tooOld))
        assertTrue(DistrictResolver.shouldQuery(movedKm = 0.0, ageMillis = -1L))
    }

    @Test
    fun prefixesDistrictWithItsCity() {
        assertEquals("上海市宝山区", DistrictResolver.pickName("宝山区", "上海市", "上海市"))
        assertEquals("南京市鼓楼区", DistrictResolver.pickName("鼓楼区", "南京市", "江苏省"))
    }

    @Test
    fun fallsBackToProvinceWhenCityIsMissing() {
        // 直辖市常只给省不给市
        assertEquals("上海市宝山区", DistrictResolver.pickName("宝山区", "", "上海市"))
        // 县级市：省 + 区县
        assertEquals("浙江省义乌市", DistrictResolver.pickName("义乌市", null, "浙江省"))
    }

    @Test
    fun skipsPlaceholderCities() {
        assertEquals("湖北省仙桃市", DistrictResolver.pickName("仙桃市", "省直辖县级行政区划", "湖北省"))
        assertEquals("河北省某县", DistrictResolver.pickName("某县", "市辖区", "河北省"))
    }

    @Test
    fun keepsNameThatAlreadyCarriesItsParent() {
        assertEquals("上海市宝山区", DistrictResolver.pickName("上海市宝山区", "上海市", "上海市"))
    }

    @Test
    fun keepsShortNameWithoutParents() {
        // 长名字的小组件退路：只用区县名
        val names = DistrictResolver.pickNames("阿图什市", "克孜勒苏柯尔克孜自治州", "新疆维吾尔自治区")
        assertEquals("克孜勒苏柯尔克孜自治州阿图什市", names?.full)
        assertEquals("阿图什市", names?.short)

        val plain = DistrictResolver.pickNames("宝山区", "上海市", "上海市")
        assertEquals("上海市宝山区", plain?.full)
        assertEquals("宝山区", plain?.short)
    }

    @Test
    fun shortNameEqualsFullWhenThereIsNoDistrict() {
        val names = DistrictResolver.pickNames(null, "深圳市", "广东省")
        assertEquals("深圳市", names?.full)
        assertEquals("深圳市", names?.short)
    }

    @Test
    fun fallsBackToCity() {
        assertEquals("深圳市", DistrictResolver.pickName(null, "深圳市", "广东省"))
        assertEquals("深圳市", DistrictResolver.pickName("  ", "深圳市", "广东省"))
    }

    @Test
    fun fallsBackToProvinceForMunicipalities() {
        assertEquals("北京市", DistrictResolver.pickName("", "", "北京市"))
    }

    @Test
    fun ignoresEmptyAmapMarker() {
        assertNull(DistrictResolver.pickName("[]", "[]", ""))
        assertNull(DistrictResolver.pickName(null, null, null))
    }

    @Test
    fun composesLocalizedNamesFromFinestToCoarsest() {
        val names = DistrictResolver.composeNames("Huangpu District", "Shanghai", "Shanghai")
        assertEquals("Huangpu District, Shanghai", names?.full)
        assertEquals("Huangpu District", names?.short)
    }

    @Test
    fun keepsOneLevelWhenOnlyOneIsKnown() {
        assertEquals("Huangpu District", DistrictResolver.composeNames("Huangpu District", null, null)?.full)
        assertEquals("Shanghai", DistrictResolver.composeNames(null, "Shanghai", "")?.full)
    }

    @Test
    fun dropsRepeatedParentAndPlaceholders() {
        // Geocoder 有时把同一级填进两个字段；「市辖区」这类高德占位值也不该出现。
        assertEquals("Shanghai", DistrictResolver.composeNames(null, "Shanghai", "Shanghai")?.full)
        assertEquals("某县, 河北省", DistrictResolver.composeNames("某县", "市辖区", "河北省")?.full)
        assertNull(DistrictResolver.composeNames(" ", "[]", null))
    }

    @Test
    fun composesFromAnyNumberOfLevels() {
        val names = DistrictResolver.composeNames(
            listOf(null, "Old Town", "Huangpu District", "Shanghai", "Shanghai"),
        )
        assertEquals("Old Town, Huangpu District, Shanghai", names?.full)
        assertEquals("Old Town", names?.short)
        // 只保留最细的三级，太长的会被小组件省略号吃掉。
        assertEquals(
            "A, B, C",
            DistrictResolver.composeNames(listOf("A", "B", "C", "D", "E"))?.full,
        )
    }
}
