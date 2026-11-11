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
}
