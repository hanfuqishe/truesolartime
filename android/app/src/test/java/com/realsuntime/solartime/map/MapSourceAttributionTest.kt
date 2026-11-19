package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 设置页「地图数据来源」的完整署名与链接（纯函数）。
 *
 * 卡片底部只放 4 个主要来源的短署名；设置页放官方英文原文全量 + 版权链接。
 */
class MapSourceAttributionTest {

    private val osmText = "地图数据 © OpenStreetMap 贡献者"
    private val amapText = "底图 © 高德地图"

    private fun note(source: MapStyle) = MapSourceAttribution.noteFor(source, osmText, amapText)

    /** 防删短：Esri 全量署名必须保留 OSM 贡献者与 GIS User Community 两段。 */
    @Test
    fun esriFullAttributionKeepsEveryRequiredSource() {
        assertTrue(
            "缺少 OpenStreetMap contributors：${MapSourceAttribution.ESRI_FULL}",
            MapSourceAttribution.ESRI_FULL.contains("OpenStreetMap contributors"),
        )
        assertTrue(
            "缺少 GIS User Community：${MapSourceAttribution.ESRI_FULL}",
            MapSourceAttribution.ESRI_FULL.contains("GIS User Community"),
        )
        // 官方原文里的 14 个来源至少都在（抽查几个容易漏的）。
        listOf("Esri", "HERE", "Garmin", "USGS", "Intermap", "INCREMENT P", "NRCan", "METI", "NGCC")
            .forEach { assertTrue("缺少来源 $it", MapSourceAttribution.ESRI_FULL.contains(it)) }
    }

    /** 三种源的设置页署名互不相同，也都与卡片短署名不同（含链接后比较）。 */
    @Test
    fun aboutNotesDifferPerSourceAndFromTheCardShortText() {
        val esri = note(MapStyle.ESRI)
        val osm = note(MapStyle.OSM)
        val amap = note(MapStyle.AMAP_VECTOR)

        val esriComposite = esri.text + (esri.url ?: "")
        val osmComposite = osm.text + (osm.url ?: "")
        val amapComposite = amap.text + (amap.url ?: "")
        assertEquals(3, setOf(esriComposite, osmComposite, amapComposite).size)

        // 卡片短署名：MapStyle.attribution（ESRI 只有 4 个来源那一行，设置页是完整版）。
        assertNotEquals(MapStyle.ESRI.attribution, esri.text)
        // OSM 的正文与卡片一致，但多一个版权链接 → 整条（正文 + 链接）与卡片短版不同。
        assertNotEquals(MapStyle.OSM.attribution, osmComposite)
        // 高德没有可点的版权页：正文与卡片一致，也没有链接。
        assertEquals(MapStyle.AMAP_VECTOR.attribution, amap.text)
        assertEquals(null, amap.url)
    }

    /** 链接域名正确：Esri 走 arcgisonline.com，OSM 走 openstreetmap.org。 */
    @Test
    fun copyrightLinksPointToTheRightHosts() {
        assertTrue(
            "Esri 链接域名不对：${note(MapStyle.ESRI).url}",
            note(MapStyle.ESRI).url.orEmpty().startsWith("https://server.arcgisonline.com/"),
        )
        assertTrue(
            "OSM 链接域名不对：${note(MapStyle.OSM).url}",
            note(MapStyle.OSM).url.orEmpty().startsWith("https://www.openstreetmap.org/"),
        )
        assertTrue(MapSourceAttribution.ESRI_URL.contains("/World_Street_Map/MapServer"))
        assertTrue(MapSourceAttribution.OSM_URL.endsWith("/copyright"))
    }

    /** 自动模式按「境内高德 / 境外 Esri」解析实际源；手动选择照旧。 */
    @Test
    fun resolveSourceFollowsTheEffectiveRule() {
        assertEquals(
            MapStyle.ESRI,
            MapSourceAttribution.resolveSource(MapStyle.AUTO, 1.3521, 103.8198, "sg"),
        )
        assertEquals(
            MapStyle.AMAP_VECTOR,
            MapSourceAttribution.resolveSource(MapStyle.AUTO, 39.9042, 116.4074, "cn"),
        )
        // 无国家码时按 73–135°E / 18–54°N：新加坡在框外 → Esri。
        assertEquals(
            MapStyle.ESRI,
            MapSourceAttribution.resolveSource(MapStyle.AUTO, 1.3521, 103.8198, null),
        )
        // 手动选 Esri / OSM / 高德：照用户选的来。
        assertEquals(MapStyle.ESRI, MapSourceAttribution.resolveSource(MapStyle.ESRI, 39.9, 116.4, "cn"))
        assertEquals(MapStyle.OSM, MapSourceAttribution.resolveSource(MapStyle.OSM, 39.9, 116.4, "cn"))
        assertEquals(
            MapStyle.AMAP_SATELLITE,
            MapSourceAttribution.resolveSource(MapStyle.AMAP_SATELLITE, 48.85, 2.35, "fr"),
        )
    }
}
