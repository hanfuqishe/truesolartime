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
    fun prefersDistrict() {
        assertEquals("宝山区", DistrictResolver.pickName("宝山区", "", "上海市"))
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
