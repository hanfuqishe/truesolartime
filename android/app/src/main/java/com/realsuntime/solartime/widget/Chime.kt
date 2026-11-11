package com.realsuntime.solartime.widget

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import kotlin.math.sin

/**
 * 提示音：合成一段固定频率的蜂鸣。
 *
 * 自己算正弦波而不是用 `ToneGenerator`：系统提示音的类型与频率因机型而异，
 * 这里要的是固定频率、固定时长的声音。首尾各加 10 ms 淡入淡出避免爆音。
 */
object Chime {

    /** 蜂鸣频率：比系统提示音（约 800 Hz）高，短促而清楚。 */
    internal const val BEEP_HZ = 2_000.0

    private const val SAMPLE_RATE = 22_050
    private const val TONE_VOLUME = 95
    private const val RELEASE_DELAY_MILLIS = 200L

    /**
     * 播一声 [durationMillis] 长的蜂鸣。
     *
     * 短音效必须自己收尾，否则会一直占着音频通路。
     * [onDone] 在播放结束（并释放音轨）后回调，便于接收器用 `goAsync()` 保住进程。
     */
    fun beep(durationMillis: Int, onDone: () -> Unit = {}) {
        val samples = samples(durationMillis)
        val track = runCatching {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(samples.size * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
        }.getOrNull()
        var started = false
        if (track != null) {
            runCatching {
                started = track.write(samples, 0, samples.size) > 0
                if (started) track.play()
            }
            if (!started) runCatching { track.release() }
        }
        if (!started) {
            // 少数机型上 AudioTrack 不可用，退回系统的高频 pip 音。
            beepWithToneGenerator(durationMillis, onDone)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            runCatching { track?.stop() }
            runCatching { track?.release() }
            onDone()
        }, durationMillis + RELEASE_DELAY_MILLIS)
    }

    /** 指定时长的正弦波，首尾各 10 ms 淡入淡出。 */
    internal fun samples(durationMillis: Int): ShortArray {
        val count = SAMPLE_RATE * durationMillis / 1000
        val fade = SAMPLE_RATE / 100
        return ShortArray(count) { index ->
            val envelope = minOf(1.0, index / fade.toDouble(), (count - 1 - index) / fade.toDouble())
            val wave = sin(2.0 * Math.PI * BEEP_HZ * index / SAMPLE_RATE)
            (wave * envelope * Short.MAX_VALUE * 0.6).toInt().toShort()
        }
    }

    private fun beepWithToneGenerator(durationMillis: Int, onDone: () -> Unit) {
        val tone = runCatching {
            ToneGenerator(AudioManager.STREAM_NOTIFICATION, TONE_VOLUME).also {
                it.startTone(ToneGenerator.TONE_CDMA_PIP, durationMillis)
            }
        }.getOrNull()
        if (tone == null) {
            onDone()
            return
        }
        Handler(Looper.getMainLooper()).postDelayed(
            {
                runCatching { tone.release() }
                onDone()
            },
            durationMillis + RELEASE_DELAY_MILLIS,
        )
    }
}
