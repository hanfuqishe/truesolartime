package com.realsuntime.solartime.data

import android.content.Context

class AppSettings(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences("solar_time_settings", Context.MODE_PRIVATE)

    var place: Place
        get() = Place(
            latitude = prefs.getString(KEY_LATITUDE, null)?.toDoubleOrNull() ?: Place.DEFAULT.latitude,
            longitude = prefs.getString(KEY_LONGITUDE, null)?.toDoubleOrNull() ?: Place.DEFAULT.longitude,
            source = prefs.getString(KEY_SOURCE, null)
                ?.let { runCatching { PlaceSource.valueOf(it) }.getOrNull() }
                ?: Place.DEFAULT.source,
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

    private companion object {
        const val KEY_LATITUDE = "latitude"
        const val KEY_LONGITUDE = "longitude"
        const val KEY_SOURCE = "place_source"
        const val KEY_LABEL = "place_label"
        const val KEY_REMINDERS = "shichen_reminders"
    }
}
