package com.realsuntime.solartime.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.realsuntime.solartime.MainActivity

/**
 * 排「报时」这种必须准时响一次的闹钟。
 *
 * 普通精确闹钟（`setExactAndAllowWhileIdle`）在多数机型上够用，但华为/荣耀的
 * PowerGenie 会冻结后台应用并**代理其广播**，日志里能看到
 * `proxyBroadcast:[…] proxy:true` + `perform delay action` —— 闹钟准点触发，
 * 广播却被压到应用下次解冻才投递（往往是用户回到桌面时），报时就晚了几分钟。
 *
 * 这类 ROM 上改用 `setAlarmClock()`：把下一次报时登记成「闹钟」，系统会在触发
 * 瞬间解冻应用并正常投递（日志里变成 `unF_Z … OK` + `proxy:false`）。
 * 代价是状态栏会出现闹钟图标，所以只在需要它的机型上用。
 */
internal object ChimeAlarm {

    private val FREEZING_MANUFACTURERS = setOf("huawei", "honor")

    /** 该机型是否会代理/延迟后台广播，需要用「闹钟」语义排程。 */
    internal fun needsAlarmClockSemantics(manufacturer: String?): Boolean =
        manufacturer?.trim()?.lowercase() in FREEZING_MANUFACTURERS

    fun schedule(context: Context, triggerMillis: Long, pending: PendingIntent) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        if (needsAlarmClockSemantics(Build.MANUFACTURER)) {
            manager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerMillis, showIntent(context)),
                pending,
            )
        } else if (canScheduleExact(manager)) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMillis, pending)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMillis, pending)
        }
    }

    /** 高版本系统需用户授予「闹钟和提醒」权限才允许精确定时，否则退化为可延迟的闹钟。 */
    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()

    /** 用户点状态栏的闹钟图标时回到本 App。 */
    private fun showIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            SHOW_REQUEST_CODE,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private const val SHOW_REQUEST_CODE = 7310
}
