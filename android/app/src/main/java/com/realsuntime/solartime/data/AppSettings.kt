package com.realsuntime.solartime.data

import android.content.Context
import com.realsuntime.solartime.map.MapStyle

class AppSettings(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences("solar_time_settings", Context.MODE_PRIVATE)

    var place: Place
        get() = placeFromStored(
            latitudeRaw = prefs.getString(KEY_LATITUDE, null),
            longitudeRaw = prefs.getString(KEY_LONGITUDE, null),
            sourceRaw = prefs.getString(KEY_SOURCE, null),
            labelRaw = prefs.getString(KEY_LABEL, null),
            labelResNameRaw = prefs.getString(KEY_LABEL_RES, null),
            countryCodeRaw = prefs.getString(KEY_PLACE_COUNTRY, null),
        )
        set(value) {
            prefs.edit()
                .putString(KEY_LATITUDE, value.latitude.toString())
                .putString(KEY_LONGITUDE, value.longitude.toString())
                .putString(KEY_SOURCE, value.source.name)
                .putString(KEY_LABEL, value.label)
                .putString(KEY_LABEL_RES, value.labelResName)
                // SharedPreferences 存不了 null，用空串表示未知。
                .putString(KEY_PLACE_COUNTRY, value.countryCode.orEmpty())
                .apply()
        }

    var remindersEnabled: Boolean
        get() = prefs.getBoolean(KEY_REMINDERS, false)
        set(value) = prefs.edit().putBoolean(KEY_REMINDERS, value).apply()

    var mapStyle: MapStyle
        get() = MapStyle.fromName(prefs.getString(KEY_MAP_STYLE, null))
        set(value) = prefs.edit().putString(KEY_MAP_STYLE, value.name).apply()

    /** 「进入关键时间」报时。pref 键沿用旧名字，升级后不丢设置。 */
    var keyTimeChimeEnabled: Boolean
        get() = prefs.getBoolean(KEY_HOURLY_CHIME, false)
        set(value) = prefs.edit().putBoolean(KEY_HOURLY_CHIME, value).apply()

    /** 定位权限只自动申请一次，避免每次启动都弹窗。 */
    var locationPermissionRequested: Boolean
        get() = prefs.getBoolean(KEY_LOCATION_ASKED, false)
        set(value) = prefs.edit().putBoolean(KEY_LOCATION_ASKED, value).apply()

    /** 应用在前台时是否禁止自动熄屏（默认开）。 */
    var keepScreenOn: Boolean
        get() = prefs.getBoolean(KEY_KEEP_SCREEN_ON, true)
        set(value) = prefs.edit().putBoolean(KEY_KEEP_SCREEN_ON, value).apply()

    /**
     * 界面与桌面卡片的配色模式（默认「自动」＝按日出日落，与旧版本行为一致）。
     *
     * 键名 `theme_mode`；值用枚举名（`AUTO` / `LIGHT` / `DARK`），读不出来时当「自动」。
     */
    var themeMode: ThemeMode
        get() = ThemeMode.fromName(prefs.getString(KEY_THEME_MODE, null))
        set(value) = prefs.edit().putString(KEY_THEME_MODE, value.name).apply()

    /** 上次为桌面卡片主动取 GPS 的时刻：卡片可见时最多 5 分钟取一次，避免每分钟都唤醒定位。 */
    var lastWidgetFixMillis: Long
        get() = prefs.getLong(KEY_LAST_WIDGET_FIX, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_WIDGET_FIX, value).apply()

    private companion object {
        const val KEY_LATITUDE = "latitude"
        const val KEY_LONGITUDE = "longitude"
        const val KEY_SOURCE = "place_source"
        const val KEY_LABEL = "place_label"
        const val KEY_LABEL_RES = "place_label_res"
        const val KEY_PLACE_COUNTRY = "place_country"
        const val KEY_REMINDERS = "shichen_reminders"
        const val KEY_MAP_STYLE = "map_style"
        const val KEY_HOURLY_CHIME = "hourly_chime"
        const val KEY_LOCATION_ASKED = "location_permission_requested"
        const val KEY_KEEP_SCREEN_ON = "keep_screen_on"
        const val KEY_THEME_MODE = "theme_mode"
        const val KEY_LAST_WIDGET_FIX = "last_widget_fix"
    }
}

/**
 * 从 SharedPreferences 的原始值还原观测点（纯函数，便于单测）。
 *
 * **`labelResName` 只在「全新安装、一个地点都没存过」时才回落到默认城市（北京）**：
 * 手动坐标 / GPS 的 `labelResName` 本来就是 null，`putString(key, null)` 会把键删掉，
 * 旧实现于是又读到默认值 `city_beijing` —— 这就是「刚输入埃及坐标、地名却还是北京」的根因。
 * 存过地点（source != DEFAULT）却没名字时，必须老老实实返回 null，让界面等逆地理编码，
 * 失败就显示占位符 `-`。
 */
internal fun placeFromStored(
    latitudeRaw: String?,
    longitudeRaw: String?,
    sourceRaw: String?,
    labelRaw: String?,
    labelResNameRaw: String?,
    countryCodeRaw: String?,
): Place {
    val source = sourceRaw
        ?.let { runCatching { PlaceSource.valueOf(it) }.getOrNull() }
        ?: PlaceSource.DEFAULT
    val isFreshInstall = source == PlaceSource.DEFAULT
    return Place(
        latitude = latitudeRaw?.toDoubleOrNull() ?: Place.DEFAULT.latitude,
        longitude = longitudeRaw?.toDoubleOrNull() ?: Place.DEFAULT.longitude,
        source = source,
        label = labelRaw ?: Place.DEFAULT.label,
        labelResName = labelResNameRaw
            ?: if (isFreshInstall) Place.DEFAULT.labelResName else null,
        // 空串表示「不知道」（GPS / 手动坐标），按 null 读出来让调用方回退逆地理编码。
        countryCode = countryCodeRaw?.takeIf { it.isNotEmpty() },
    )
}