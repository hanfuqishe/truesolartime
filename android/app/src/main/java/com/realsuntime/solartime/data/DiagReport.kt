package com.realsuntime.solartime.data

import android.content.Context
import android.os.Build
import android.provider.Settings
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.widget.WidgetUpdater
import java.util.Locale

/**
 * 诊断页的纯文本报告。**只读**，每一行都是 `键 = 值`，方便对方截屏后肉眼对。
 *
 * 设计约束：
 * * 任何一项读取失败只显示 `读取失败: xxx`，绝不让整个页面崩掉（每块都 runCatching）；
 * * 不读 IMEI / 手机号 / 账号等敏感信息；经纬度保留（排查时区/日出日落需要）；
 * * 不做任何美化，就是可复制的纯文本。
 */
internal object DiagReport {

    fun build(context: Context): String = buildList {
        add(header(context))
        add("")
        addAll(appSection(context))
        add("")
        addAll(metricsSection(context))
        add("")
        addAll(fontSection(context))
        add("")
        add("===== ④ 最近一次小组件构建 =====")
        add(DiagStore.lastWidgetBuild(context))
        add("")
        add("===== ⑤ 最近一次刷新链路 =====")
        add(DiagStore.lastRefresh(context))
        add("")
        add("===== 地点 =====")
        addAll(placeSection(context))
        add("")
        add("===== 说明 =====")
        add("复制本页全部内容即可发给开发者；不含 IMEI/账号等敏感信息。")
    }.joinToString("\n")

    /**
     * 一行头信息：`真太阳时诊断信息  1.4.93  HUAWEI ELE-AL00  Android 10`。
     * 放在最前面，对方粘到微信里我们一眼就能认出是谁的机器。
     */
    fun header(context: Context): String = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val version = info.versionName ?: "?"
        "真太阳时诊断信息  $version  ${Build.MANUFACTURER} ${Build.MODEL}  Android ${Build.VERSION.RELEASE}"
    }.getOrElse { "真太阳时诊断信息  (头部读取失败: ${DiagStore.describe(it)})" }

    // ---------------------------------------------------------------- ① 应用与系统

    private fun appSection(context: Context): List<String> = runCatching {
        val pm = context.packageManager
        val info = pm.getPackageInfo(context.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        listOf(
            "===== ① 应用与系统 =====",
            "App 版本 = ${info.versionName ?: "?"}",
            "versionCode = $code",
            "机型 = ${Build.MODEL}",
            "品牌 = ${Build.BRAND}",
            "厂商 = ${Build.MANUFACTURER}",
            "Android = ${Build.VERSION.RELEASE}",
            "SDK_INT = ${Build.VERSION.SDK_INT}",
            "ROM = ${Build.DISPLAY}",
            "ROM(incremental) = ${Build.VERSION.INCREMENTAL}",
            "语言/地区 = ${Locale.getDefault()}",
            "报告生成时间 = ${DiagStore.now()}",
        )
    }.getOrElse { listOf("===== ① 应用与系统 =====", "读取失败: ${DiagStore.describe(it)}") }

    // ---------------------------------------------------------------- ② 测量与密度

    private fun metricsSection(context: Context): List<String> = runCatching {
        buildList {
            add("===== ② 测量与密度 =====")
            addAll(WidgetUpdater.metricsSummary(context).map { (k, v) -> "$k = $v" })
        }
    }.getOrElse { listOf("===== ② 测量与密度 =====", "读取失败: ${DiagStore.describe(it)}") }

    // ---------------------------------------------------------------- ③ 系统字体相关键

    private fun fontSection(context: Context): List<String> = runCatching {
        listOf(
            "===== ③ 系统字体相关（可能为 null）=====",
            "system.font_scale = ${setting(context, "system", "font_scale")}",
            "system.font_weight_scale = ${setting(context, "system", "font_weight_scale")}",
            "system.font_weight_scale_normal = ${setting(context, "system", "font_weight_scale_normal")}",
            "secure.font_weight_adjustment = ${setting(context, "secure", "font_weight_adjustment")}",
            "secure.elder_care_switch = ${setting(context, "secure", "elder_care_switch")}",
            "secure.big_font_scale = ${setting(context, "secure", "big_font_scale")}",
            "secure.elder_care_save_font_weight = ${setting(context, "secure", "elder_care_save_font_weight")}",
        )
    }.getOrElse { listOf("===== ③ 系统字体相关 =====", "读取失败: ${DiagStore.describe(it)}") }

    // ---------------------------------------------------------------- 地点

    private fun placeSection(context: Context): List<String> = runCatching {
        val place = AppSettings(context).place
        val zoneOffset = LocalZone.offsetSeconds(context, place, java.time.Instant.now())
        val names = DistrictResolver.cachedNamesFor(context, place)
        val weather = WeatherRepository.cached(context, place)
        buildList {
            add("纬度 = ${place.latitude}")
            add("经度 = ${place.longitude}")
            add("来源 = ${place.source}")
            add("名称 = ${names?.full ?: place.label}")
            add("时区偏移 = ${TimeFormat.utcOffsetLabel(zoneOffset)}")
            add("区划缓存 = ${if (names != null) "有（${names.full}）" else "无"}")
            add("天气缓存 = ${if (weather != null) "有" else "无"}")
        }
    }.getOrElse { listOf("读取失败: ${DiagStore.describe(it)}") }

    // ---------------------------------------------------------------- helpers

    /** 读 `Settings.System/Secure` 的一个键；不存在时返回字符串 `null`（不返回空串）。 */
    private fun setting(context: Context, namespace: String, key: String): String = runCatching {
        when (namespace) {
            "system" -> Settings.System.getString(context.contentResolver, key)
            else -> Settings.Secure.getString(context.contentResolver, key)
        } ?: "null"
    }.getOrElse { "读取失败: ${DiagStore.describe(it)}" }
}
