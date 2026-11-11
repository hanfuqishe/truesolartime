package com.realsuntime.solartime.widget

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.AlarmClock

/**
 * 小组件各区域点击后的跳转目标。
 *
 * - 标准时间 → 系统闹钟
 * - 天气 → 系统天气（先按 `CATEGORY_APP_WEATHER`、再试常见厂商包名，最后退回浏览器）
 * - 真太阳时 → 本 App（在 [WidgetUpdater] 里直接指向 MainActivity）
 *
 * 解析在刷新时完成：拿不到目标就不挂点击，避免点了没反应或崩溃。
 */
internal object WidgetIntents {

    /** 天气应用的已知包名，覆盖国内外常见 ROM。 */
    private val WEATHER_PACKAGES = listOf(
        "com.huawei.android.totemweather",
        "com.miui.weather2",
        "com.coloros.weather2",
        "com.oplus.weather",
        "com.samsung.android.weather",
        "com.google.android.apps.weather",
        "com.weather.Weather",
        "com.accuweather.android",
        "com.android.weather",
    )

    /** 华为天气另有专用 action，包名解析不到启动页时兜底。 */
    private const val HUAWEI_WEATHER_ACTION = "com.huawei.android.totemweather.action.START_HOME"

    /**
     * 系统闹钟：优先打开闹钟列表，退而求其次新建闹钟（都能落到同一界面）。
     * 都不存在时返回 null。
     */
    fun alarm(context: Context): Intent? {
        val showAlarms = Intent(AlarmClock.ACTION_SHOW_ALARMS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (resolvable(context, showAlarms)) return showAlarms
        val setAlarm = Intent(AlarmClock.ACTION_SET_ALARM).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return if (resolvable(context, setAlarm)) setAlarm else null
    }

    /** 系统天气；解析不到任何天气应用时退回浏览器（带当天日期，避免落到无关页面）。 */
    fun weather(context: Context, latitude: Double, longitude: Double): Intent? {
        val byCategory = Intent(Intent.ACTION_MAIN)
            .addCategory(APP_WEATHER_CATEGORY)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (resolvable(context, byCategory)) return byCategory

        val manager = context.packageManager
        WEATHER_PACKAGES.forEach { pkg ->
            manager.getLaunchIntentForPackage(pkg)?.let { return it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        }

        val huaweiAction = Intent(HUAWEI_WEATHER_ACTION).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (resolvable(context, huaweiAction)) return huaweiAction

        val web = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://www.weather.com/weather/today/l/%.3f,%.3f".format(latitude, longitude)),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return if (resolvable(context, web)) web else null
    }

    /**
     * 系统日历：优先用 `CATEGORY_APP_CALENDAR` 打开日历主页；
     * 定制 ROM 没注册这个分类时，退回 `content://com.android.calendar/time`（打开今天）。
     * 都不存在时返回 null，此时日期区域不挂点击（会冒泡到左栏的闹钟）。
     */
    fun calendar(context: Context): Intent? {
        val byCategory = Intent(Intent.ACTION_MAIN)
            .addCategory(APP_CALENDAR_CATEGORY)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (resolvable(context, byCategory)) return byCategory

        val today = Intent(Intent.ACTION_VIEW).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).setData(
            Uri.parse("content://com.android.calendar/time/${System.currentTimeMillis()}"),
        )
        return if (resolvable(context, today)) today else null
    }

    private fun resolvable(context: Context, intent: Intent): Boolean =
        context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null

    /** `Intent.CATEGORY_APP_WEATHER` 常量只有 15+ 才有，这里直接写字面量。 */
    private const val APP_WEATHER_CATEGORY = "android.intent.category.APP_WEATHER"

    private const val APP_CALENDAR_CATEGORY = "android.intent.category.APP_CALENDAR"
}
