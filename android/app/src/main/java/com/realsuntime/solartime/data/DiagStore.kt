package com.realsuntime.solartime.data

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 「最近一次」诊断快照：只覆盖同一个键，**不累积、不会无限增长**。
 *
 * 为什么落盘：小组件构建失败时进程可能马上被系统回收，内存里的诊断会丢；而且用户报障时
 * 往往先看桌面、再进 App，落盘才能保证 App 里读到的是「桌面那一次」的真实参数。
 *
 * 所有写入/读取都吞异常：诊断自身绝不能影响主流程，也绝不能把诊断页搞崩。
 */
internal object DiagStore {
    private const val PREFS = "diagnostics"
    private const val KEY_BUILD = "last_widget_build"
    private const val KEY_REFRESH = "last_refresh"

    /** 单份快照的字符上限：异常 message 可能很长，兜一下。 */
    private const val MAX_CHARS = 6000

    /** 异常描述的最大长度（类名 + message）。 */
    private const val MAX_MESSAGE = 200

    fun now(): String = runCatching {
        SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(Date())
    }.getOrElse { "?" }

    /** `java.lang.IllegalStateException: xxx`（截断到 200 字）。 */
    fun describe(error: Throwable?): String = runCatching {
        if (error == null) {
            "-"
        } else {
            val message = error.message?.takeIf { it.isNotBlank() } ?: ""
            val name = error.javaClass.simpleName.ifBlank { error.javaClass.name }
            "$name: $message".take(MAX_MESSAGE)
        }
    }.getOrElse { "读取失败: $it" }

    fun recordWidgetBuild(context: Context, lines: List<Pair<String, String>>) {
        write(context, KEY_BUILD, lines)
    }

    fun recordWidgetBuildFailure(context: Context, appWidgetId: Int, error: Throwable) {
        recordWidgetBuild(
            context,
            listOf(
                "时间" to now(),
                "AppWidget id" to appWidgetId.toString(),
                "结果" to "失败（已退回最小版面）",
                "异常" to describe(error),
            ),
        )
    }

    fun recordRefresh(context: Context, lines: List<Pair<String, String>>) {
        write(context, KEY_REFRESH, lines)
    }

    fun lastWidgetBuild(context: Context): String = read(context, KEY_BUILD)

    fun lastRefresh(context: Context): String = read(context, KEY_REFRESH)

    private fun write(context: Context, key: String, lines: List<Pair<String, String>>) {
        runCatching {
            val text = lines
                .joinToString("\n") { "${it.first} = ${it.second}" }
                .take(MAX_CHARS)
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(key, text)
                .apply()
        }.onFailure { android.util.Log.w("SolarDiag", "write($key) failed", it) }
    }

    private fun read(context: Context, key: String): String = runCatching {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(key, null)
            ?: "（还没有记录）"
    }.getOrElse { "读取失败: $it" }
}
