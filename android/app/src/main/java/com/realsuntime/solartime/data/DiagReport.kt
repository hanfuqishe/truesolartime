package com.realsuntime.solartime.data

import android.content.Context
import android.os.Build
import android.provider.Settings
import com.realsuntime.solartime.map.MapFallback
import com.realsuntime.solartime.map.MapFallbackDiagnostics
import com.realsuntime.solartime.map.MapFallbackSession
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.widget.WidgetUpdater
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 诊断页的纯文本报告。**只读**，每一行都是 `键 = 值`，方便对方整段复制后我们肉眼对。
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
        addAll(weatherSection(context))
        add("")
        addAll(mapSection(context))
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
            "主题模式 = ${AppSettings(context).themeMode.name.lowercase(Locale.ROOT)}（auto = 按日出日落）",
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

    // ---------------------------------------------------------------- ⑥ 天气数据源

    /**
     * 天气用哪个源、几小时一格、数据有多旧、什么时候会再试 —— 排查「天气不刷新 / 时间对不上」先看这几行。
     *
     * `weather_source` / `weather_step` / `weather_age_minutes` 三个键名与
     * [DiagStore.recordWeather] 写入的完全一致，可以直接对 log 与用户截图。
     * 「上次主源尝试 / 连续失败 / 下次重试」是取数时序的现场：低精度时前台按 60 → 120 → 300 秒
     * 退避、后台 10 分钟，主源一成功立刻切回并清零退避（见 [WeatherRepository.nextRetryLabel]）。
     */
    private fun weatherSection(context: Context): List<String> = runCatching {
        val place = AppSettings(context).place
        val source = WeatherRepository.source(context)
        val step = WeatherRepository.stepHours(context)
        val age = WeatherRepository.ageMillis(context)
        val stale = WeatherRepository.staleLabel(age)
        val lowPrecision = WeatherRepository.isLowPrecision(source, step)
        val points = WeatherRepository.hourly(context, place).points
        val lastAttempt = WeatherRepository.lastAttemptMillis(context)
        val sinceAttempt = WeatherRepository.sinceAttemptMillis(context)
        val failures = WeatherRepository.lowPrecisionFailures(context)
        val foreground = WeatherRepository.isForeground()
        buildList {
            add("===== ⑥ 天气数据源 =====")
            add("当前源 = ${source.id}（$step 小时粒度）")
            add("weather_source = ${source.id}")
            add("weather_step = $step 小时")
            add("weather_age_minutes = ${(age ?: 0L) / 60_000L}")
            add("数据状态 = ${stale ?: WeatherRepository.ageNote(age)}")
            add(
                "上次主源尝试 = " + (
                    lastAttempt?.let { at ->
                        "${SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(Date(at))}（" +
                            "${(sinceAttempt ?: 0L) / 1000L} 秒前）"
                    } ?: "无记录"
                    ),
            )
            add("连续失败 = $failures 次（前台退避 ${WeatherRepository.nextLowPrecisionRetryDelayMillis(failures, true) / 1000} 秒 / 后台 10 分钟）")
            add(
                "下次重试 = " + WeatherRepository.nextRetryLabel(
                    ageMillis = age ?: 0L,
                    sinceAttemptMillis = sinceAttempt ?: Long.MAX_VALUE,
                    lowPrecision = lowPrecision,
                    lowPrecisionFailures = failures,
                    isForeground = foreground,
                ),
            )
            add(
                "低精度数据 = " +
                    if (lowPrecision) {
                        "是（3 小时粒度，前台按 60/120/300 秒退避重试主源，后台 10 分钟；成功即刻切回）"
                    } else {
                        "否（主源 1 小时粒度）"
                    },
            )
            add("逐时点数 = ${points.size}")
            add("最近一次取数：")
            add(DiagStore.lastWeather(context))
        }
    }.getOrElse { listOf("===== ⑥ 天气数据源 =====", "读取失败: ${DiagStore.describe(it)}") }

    // ---------------------------------------------------------------- ⑦ 地图底图

    /**
     * 地图这一块：现在用哪个底图源、是不是回退来的、缩放有没有降级、OSM 失败几次、下次什么时候探测。
     *
     * 对应报障「境外出差 / 大陆网络下地图是空白」：一眼能看出是 OSM 被墙后回退到高德，
     * 还是连高德都没有瓦片（真没网），不用再猜。
     */
    private fun mapSection(context: Context): List<String> = runCatching {
        val settings = AppSettings(context)
        val place = settings.place
        val tracker = MapFallbackSession.tracker
        val state = tracker.snapshot()
        val plan = MapFallback.plan(settings.mapStyle, place.latitude, place.longitude, state)
        val zoomPlan = MapFallback.zoomPlan(
            plan,
            tracker.appliedZoom() ?: MapFallback.DEFAULT_ZOOM,
            state,
        )
        buildList {
            add("===== ⑦ 地图底图 =====")
            addAll(MapFallbackDiagnostics.lines(plan, zoomPlan, state, System.currentTimeMillis()))
            // 未知态（定位不可用）的 z3 快路径：显示实际会用的那个源（缓存/探测结果都写在这里）。
            add("未知态底图 = ${settings.unknownMapSource?.label ?: "无（还没成功过）"}")
        }
    }.getOrElse { listOf("===== ⑦ 地图底图 =====", "读取失败: ${DiagStore.describe(it)}") }

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
            add("天气来源 = ${WeatherRepository.source(context).id}")
            add("天气步长 = ${WeatherRepository.stepHours(context)} 小时")
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
