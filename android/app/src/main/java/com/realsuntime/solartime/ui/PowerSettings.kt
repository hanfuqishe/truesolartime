package com.realsuntime.solartime.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * 把用户送到系统里「允许本应用后台运行」的设置页。
 *
 * 华为/荣耀会冻结后台应用并延迟其广播，报时因此可能晚几分钟才响；
 * 在「应用启动管理」里允许后台活动可以从根本上避免（App 内已改用闹钟语义兜底）。
 */
internal object PowerSettings {

    /** 华为/荣耀的「应用启动管理」页面；其余机型退到应用详情页。 */
    fun openBackgroundSettings(context: Context) {
        if (openHuaweiStartupManager(context)) return
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(details) }
    }

    /** 只有华为/荣耀才有这一页，其他机型直接返回 false。 */
    private fun openHuaweiStartupManager(context: Context): Boolean {
        if (Build.MANUFACTURER?.lowercase() !in setOf("huawei", "honor")) return false
        val intents = listOf(
            Intent().setClassName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            ),
            Intent().setClassName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity",
            ),
        )
        intents.forEach { intent ->
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // 试下一个
            } catch (_: SecurityException) {
                // 试下一个
            }
        }
        return false
    }
}
