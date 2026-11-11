package com.realsuntime.solartime.data

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.amap.api.services.core.AMapException
import com.amap.api.services.core.LatLonPoint
import com.amap.api.services.core.ServiceSettings
import com.amap.api.services.geocoder.GeocodeResult
import com.amap.api.services.geocoder.GeocodeSearch
import com.amap.api.services.geocoder.RegeocodeQuery
import com.amap.api.services.geocoder.RegeocodeResult
import com.realsuntime.solartime.BuildConfig
import com.realsuntime.solartime.map.CoordinateTransform
import com.realsuntime.solartime.widget.WidgetUpdater
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 用高德逆地理编码把经纬度反查成省／市／区县（Android 平台 Key，绑定包名与签名）。
 *
 * 小组件每分钟刷新，所以只在「位置明显变化或缓存过期」时才查询一次，结果存进
 * SharedPreferences；没有配置 key、没有网络或查询失败时，调用方回退到离线城市表。
 *
 * 注意：查询会把坐标发给高德。高德 SDK 要求首次使用前声明隐私合规，
 * 正式上架时应改为在用户同意隐私政策后再触发查询。
 */
object DistrictResolver {

    private const val PREFS = "district_cache"
    private const val KEY_NAME = "name"
    private const val KEY_SHORT = "short"
    private const val KEY_LAT = "lat"
    private const val KEY_LON = "lon"
    private const val KEY_TIME = "time"

    /** 新坐标与上次反查坐标相距超过该距离才重新反查，其余情况沿用已缓存的结果。 */
    private const val MOVE_THRESHOLD_KM = 5.0

    /**
     * 缓存格式版本。结果写法变了（例如现在带上「市」前缀、并额外存区县短名）就把旧缓存当过期，
     * 避免升级后一直显示旧名字。
     */
    private const val CACHE_SCHEMA = 3
    private const val KEY_SCHEMA = "schema"

    /** 高德用来占位、本身不是地名的上级字段。 */
    private val PLACEHOLDER_REGIONS = setOf("市辖区", "县", "省直辖县级行政区划", "自治区直辖县级行政区划")

    /** 缓存有效期。 */
    private const val MAX_AGE_MILLIS = 30L * 24 * 60 * 60 * 1000

    /** 单次查询的最长等待，超时后放弃本次（下一分钟再试）。 */
    private const val TIMEOUT_MILLIS = 10_000L

    private val inFlight = AtomicBoolean(false)

    // 懒加载：纯逻辑（pickName）可在 JVM 单测里直接调用，不依赖 Android Looper。
    private val handler by lazy { Handler(Looper.getMainLooper()) }

    /**
     * 反查结果的两级写法：[full] 带上级（如「上海市宝山区」），[short] 只有区县（如「宝山区」）。
     *
     * 小组件里那一行只有十来字的宽度，名字太长就得退到 [short]，否则会被省略号截断成
     * 「克孜勒苏柯尔克孜自治…」这种看不出位置的样子。
     */
    data class DistrictNames(val full: String, val short: String)

    /** 最近一次反查到的名字；不判断距离，避免新结果回来前显示闪成别的名字。 */
    fun cachedNames(context: Context): DistrictNames? {
        val prefs = prefs(context)
        val full = prefs.getString(KEY_NAME, null) ?: return null
        return DistrictNames(full, prefs.getString(KEY_SHORT, null) ?: full)
    }

    fun cachedName(context: Context): String? = cachedNames(context)?.full

    /** 距离上次反查的坐标是否已超过阈值、或缓存已过期。 */
    fun needsRefresh(context: Context, place: Place): Boolean {
        val prefs = prefs(context)
        if (prefs.getString(KEY_NAME, null) == null) return true
        if (prefs.getInt(KEY_SCHEMA, 0) != CACHE_SCHEMA) return true
        val lat = prefs.getFloat(KEY_LAT, Float.NaN).toDouble()
        val lon = prefs.getFloat(KEY_LON, Float.NaN).toDouble()
        if (lat.isNaN() || lon.isNaN()) return true
        val moved = CityIndex.distanceKm(lat, lon, place.latitude, place.longitude)
        val age = System.currentTimeMillis() - prefs.getLong(KEY_TIME, 0L)
        return shouldQuery(moved, age)
    }

    /** 纯判定逻辑，便于单测。 */
    internal fun shouldQuery(movedKm: Double, ageMillis: Long): Boolean =
        movedKm > MOVE_THRESHOLD_KM || ageMillis !in 0..MAX_AGE_MILLIS

    /** 需要时发起一次查询，成功后重绘小组件。必须在主线程调用（高德 SDK 的限制）。 */
    fun requestRefresh(context: Context, place: Place) {
        if (BuildConfig.AMAP_API_KEY.isBlank()) return
        if (!needsRefresh(context, place)) return
        if (!inFlight.compareAndSet(false, true)) return

        val app = context.applicationContext
        handler.post {
            try {
                ServiceSettings.updatePrivacyShow(app, true, true)
                ServiceSettings.updatePrivacyAgree(app, true)

                // 高德使用 GCJ-02，数据层是 WGS-84，查询前先换算。
                val (gcjLat, gcjLon) = CoordinateTransform.wgs84ToGcj02(place.latitude, place.longitude)
                val search = GeocodeSearch(app)
                search.setOnGeocodeSearchListener(object : GeocodeSearch.OnGeocodeSearchListener {
                    override fun onRegeocodeSearched(result: RegeocodeResult?, code: Int) {
                        try {
                            if (code == AMapException.CODE_AMAP_SUCCESS) {
                                val address = result?.regeocodeAddress
                                val names = pickNames(address?.district, address?.city, address?.province)
                                if (names != null) {
                                    save(app, place, names)
                                    WidgetUpdater.refreshAll(app)
                                }
                            }
                        } finally {
                            inFlight.set(false)
                        }
                    }

                    override fun onGeocodeSearched(result: GeocodeResult?, code: Int) = Unit
                })
                search.getFromLocationAsyn(
                    RegeocodeQuery(LatLonPoint(gcjLat, gcjLon), 200f, GeocodeSearch.AMAP),
                )
            } catch (e: Exception) {
                inFlight.set(false)
                return@post
            }

            // SDK 没回调时兜底放开，避免一直卡在「查询中」。
            handler.postDelayed({ inFlight.set(false) }, TIMEOUT_MILLIS)
        }
    }

    /**
     * 区县名补上上级行政区划：优先市（直辖市时市与省同名，于是得到「上海市宝山区」），
     * 市缺失或只是「市辖区」这类占位值时用省；区县名本身已带上级前缀就不再重复。
     * 没有区县时退回市，再退回省。
     */
    fun pickNames(district: String?, city: String?, province: String?): DistrictNames? {
        val county = cleanName(district)
        val town = cleanName(city)?.takeUnless { it in PLACEHOLDER_REGIONS }
        val region = cleanName(province)?.takeUnless { it in PLACEHOLDER_REGIONS }
        if (county == null) {
            val only = town ?: region ?: return null
            return DistrictNames(only, only)
        }
        val parent = listOfNotNull(town, region).firstOrNull { it != county }
        val full = if (parent == null || county.startsWith(parent)) county else parent + county
        // 短名只留区县；若区县就是全部（如县级市），短名与全名相同。
        return DistrictNames(full, county)
    }

    /** 只要带上级的全名。 */
    fun pickName(district: String?, city: String?, province: String?): String? =
        pickNames(district, city, province)?.full

    /** 高德会把空字段填成空串或「[]」，这类值一律当作没有。 */
    private fun cleanName(value: String?): String? =
        value?.trim()?.takeIf { it.isNotEmpty() && it != "[]" }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun save(context: Context, place: Place, names: DistrictNames) {
        prefs(context).edit()
            .putString(KEY_NAME, names.full)
            .putString(KEY_SHORT, names.short)
            .putInt(KEY_SCHEMA, CACHE_SCHEMA)
            .putFloat(KEY_LAT, place.latitude.toFloat())
            .putFloat(KEY_LON, place.longitude.toFloat())
            .putLong(KEY_TIME, System.currentTimeMillis())
            .apply()
    }
}
