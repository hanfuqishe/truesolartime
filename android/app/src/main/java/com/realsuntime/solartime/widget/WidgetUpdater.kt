package com.realsuntime.solartime.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import com.realsuntime.solartime.MainActivity
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.LocationTracker
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.map.CoordinateTransform
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarTimeMath
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * 桌面小组件：左侧为所在国标准时间（跟随设备时区）、日期与星期，
 * 右侧为当地真太阳时与时辰。
 *
 * 小组件无法每秒刷新，按分钟对齐刷新；定位优先取系统最近一次定位，
 * 没有权限或没有定位记录时退回 App 保存的位置。
 */
object WidgetUpdater {

    const val ACTION_TICK = "com.realsuntime.solartime.action.WIDGET_TICK"
    private const val REQUEST_TICK = 7301

    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, SolarWidgetProvider::class.java))
        if (ids.isEmpty()) {
            cancelTick(context)
            return
        }
        val views = buildViews(context)
        ids.forEach { manager.updateAppWidget(it, views) }
        scheduleNextTick(context)
    }

    fun buildViews(context: Context): RemoteViews {
        val now = Instant.now()
        val place = resolvePlace(context)
        val zone = civilZoneOf(place)
        val civil = now.atZone(zone)
        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(now, place.longitude)
        val shichenIndex = Shichen.indexOf(trueSolarSeconds)
        val isDay = SolarTimeMath.solarAltitudeDegrees(now, place.latitude, place.longitude) > -0.833

        return RemoteViews(context.packageName, R.layout.widget_solar_time).apply {
            setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (isDay) R.drawable.widget_background_day else R.drawable.widget_background_night,
            )
            setTextViewText(R.id.widget_civil_time, "%02d:%02d".format(civil.hour, civil.minute))
            setTextViewText(R.id.widget_civil_date, dateText(civil))
            setTextViewText(R.id.widget_solar_time, clockText(trueSolarSeconds))
            setTextViewText(
                R.id.widget_solar_sub,
                "${Shichen.name(shichenIndex)} · ${Shichen.halfLabel(trueSolarSeconds)}${chineseNumber(Shichen.quarterOfHalf(trueSolarSeconds))}刻",
            )
            setOnClickPendingIntent(R.id.widget_root, openApp(context))
        }
    }

    /** 对齐到下一分钟（多留 0.5 秒，避免正好踩在整分上重复刷新）。 */
    fun scheduleNextTick(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val now = System.currentTimeMillis()
        val next = now - now % 60_000L + 60_000L + 500L
        val pendingIntent = tickIntent(context)
        // 用 RTC（不唤醒），熄屏时不刷新也无妨，亮屏后系统会补发。
        if (canScheduleExact(manager)) {
            manager.setExact(AlarmManager.RTC, next, pendingIntent)
        } else {
            manager.set(AlarmManager.RTC, next, pendingIntent)
        }
    }

    fun cancelTick(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        manager.cancel(tickIntent(context))
    }

    /** 请求把小组件固定到桌面（Android 8.0+ 且启动器支持时）。 */
    fun requestPin(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(AppWidgetManager::class.java) ?: return
        if (!manager.isRequestPinAppWidgetSupported) return
        val provider = ComponentName(context, SolarWidgetProvider::class.java)
        manager.requestPinAppWidget(provider, null, null)
    }

    private fun tickIntent(context: Context): PendingIntent {
        val intent = Intent(context, SolarWidgetProvider::class.java).setAction(ACTION_TICK)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_TICK,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()

    /**
     * 所在地的法定时区。中国全境统一为东八区，直接固定；
     * 其他地区跟随设备时区（人在当地时手机通常已自动切换）。
     */
    private fun civilZoneOf(place: Place): ZoneId =
        if (CoordinateTransform.isInChina(place.latitude, place.longitude)) {
            ZoneId.of("Asia/Shanghai")
        } else {
            ZoneId.systemDefault()
        }

    private fun resolvePlace(context: Context): Place {
        val fix = LocationTracker(context).lastKnownLocation()
        if (fix != null) {
            return Place(fix.latitude, fix.longitude, com.realsuntime.solartime.data.PlaceSource.GPS, "GPS")
        }
        return AppSettings(context).place
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun clockText(trueSolarSeconds: Double): String {
        val total = trueSolarSeconds.toLong().coerceIn(0, 86_399)
        return "%02d:%02d".format(total / 3600, (total % 3600) / 60)
    }

    private fun dateText(civil: ZonedDateTime): String {
        val weekdays = arrayOf("星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六")
        return "${civil.monthValue}月${civil.dayOfMonth}日 · ${weekdays[civil.dayOfWeek.value % 7]}"
    }

    private fun chineseNumber(value: Int): String = when (value) {
        1 -> "一"
        2 -> "二"
        3 -> "三"
        4 -> "四"
        else -> value.toString()
    }
}
