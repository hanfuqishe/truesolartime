package com.realsuntime.solartime.data

import android.content.Context
import com.realsuntime.solartime.map.MapStyle

class AppSettings(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences("solar_time_settings", Context.MODE_PRIVATE)

    var place: Place
        get() = Place(
            latitude = prefs.getString(KEY_LATITUDE, null)?.toDoubleOrNull() ?: Place.DEFAULT.latitude,
            longitude = prefs.getString(KEY_LONGITUDE, null)?.toDoubleOrNull() ?: Place.DEFAULT.longitude,
            source = prefs.getString(KEY_SOURCE, null)
                ?.let { runCatching { PlaceSource.valueOf(it) }.getOrNull() }
                ?: PlaceSource.DEFAULT,
            label = prefs.getString(KEY_LABEL, null) ?: Place.DEFAULT.label,
        )
        set(value) {
            prefs.edit()
                .putString(KEY_LATITUDE, value.latitude.toString())
                .putString(KEY_LONGITUDE, value.longitude.toString())
                .putString(KEY_SOURCE, value.source.name)
                .putString(KEY_LABEL, value.label)
                .apply()
        }

    var remindersEnabled: Boolean
        get() = prefs.getBoolean(KEY_REMINDERS, false)
        set(value) = prefs.edit().putBoolean(KEY_REMINDERS, value).apply()

    var mapStyle: MapStyle
        get() = MapStyle.fromName(prefs.getString(KEY_MAP_STYLE, null))
        set(value) = prefs.edit().putString(KEY_MAP_STYLE, value.name).apply()

    var hourlyChimeEnabled: Boolean
        get() = prefs.getBoolean(KEY_HOURLY_CHIME, false)
        set(value) = prefs.edit().putBoolean(KEY_HOURLY_CHIME, value).apply()

    /** 定位权限只自动申请一次，避免每次启动都弹窗。 */
    var locationPermissionRequested: Boolean
        get() = prefs.getBoolean(KEY_LOCATION_ASKED, false)
        set(value) = prefs.edit().putBoolean(KEY_LOCATION_ASKED, value).apply()

    private companion object {
        const val KEY_LATITUDE = "latitude"
        const val KEY_LONGITUDE = "longitude"
        const val KEY_SOURCE = "place_source"
        const val KEY_LABEL = "place_label"
        const val KEY_REMINDERS = "shichen_reminders"
        const val KEY_MAP_STYLE = "map_style"
        const val KEY_HOURLY_CHIME = "hourly_chime"
        const val KEY_LOCATION_ASKED = "location_permission_requested"
    }
}