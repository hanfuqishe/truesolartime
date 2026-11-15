package com.realsuntime.solartime.ui

import android.content.ContentResolver
import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontSynthesis
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.realsuntime.solartime.R

/**
 * 卡片里锁死的字号缩放系数。
 *
 * 首页大卡片 / 太阳卡片 / 地图卡片是「版式即内容」的界面：数字必须正好撑满一栏、
 * 行高与竖分隔线的接缝都按固定 em 算出来、顶部标签行还要按文字宽度分四档退化。
 * 系统「字体大小」以及长辈关怀（超大字体）会把 `LocalDensity.fontScale`
 * 调大，上面这些假设全部失效（文字溢出、行高变化、档位判断偏早/偏晚），
 * 所以卡片内部一律按 [CARD_FONT_SCALE] 排版 —— 与日历、时钟类应用的做法一致。
 *
 * 设置页（`SettingsSheet`）**不锁**：那里是长文本、以可读性优先，跟随系统字号。
 */
internal const val CARD_FONT_SCALE = 1f

/**
 * 卡片字重诊断日志的 tag。
 *
 * 华为这类 ROM 的「加粗」不走 AOSP 的 `Configuration.fontWeightAdjustment`，命令行
 * `settings get` 也未必能一次看全（键名、默认值、是否被 `Settings.System` 接管都可能变），
 * 所以 App 自己把「它看到的字重环境 + 一组探针字宽」打成一行，任何时候都能用
 * `adb logcat -s SolarTimeCard:W` 抓到现场事实。这行日志只在启动 / 系统配置变化时打，
 * 不参与任何界面逻辑，留着比删掉有用。
 */
internal const val CARD_FONT_TAG = "SolarTimeCard"

/**
 * 卡片专用字族：App 自带的 Noto Sans SC（SIL OFL 1.1，见 `android/FONT-README.md`）。
 *
 * 为什么自带：华为 EMUI / HarmonyOS 的「字体粗细」滑杆（`font_weight_scale`）不换字面，而是在
 * **渲染层**把笔画描粗（卡片 bbox 与各段 x 范围逐像素不变，只有墨迹上涨）。用系统字族时换字重
 * 躲不掉 —— 系统 `sans-serif` 在这一段只暴露两三个字面，压字重会从 +10% 直接翻到 −11%。
 * 自带字体走 App 自己的 Typeface 与 `res/font` 资源，系统那层描粗管不到，卡片笔画才稳定：
 * 实测滑杆 0.79 → 0.88，卡片三段文字带的逐像素差异为 **0**。
 *
 * 两个字面是有意为之，为的是保住卡片的字重层次（改造前是系统 sans-serif 的 Normal / Medium）：
 * - [FontWeight.Normal] → `card_sans_regular`：只收固定文案用到的 567 个字符（204 KB）；
 * - [FontWeight.Medium] → `card_sans_medium`：收 4000 字（含 GB2312 一级汉字），因为顶部的
 *   「地区名」是运行期定位/逆地理编码拿到的，字符集不封闭，缺字会回落到**系统字体**、又被描粗。
 *
 * 配合 [cardTextStyle] 里的 `fontSynthesis = FontSynthesis.None`：Compose 不会在字重对不上时
 * 合成假粗体，请求什么字重就渲染对应字面的字形。
 *
 * 两个 ttf 的**垂直度量**在本仓库里被改写过（`hhea` 900/−300 = 1.20 em、`head.yMax/yMin`
 * 1160/−288、`OS/2.usWeightClass` 1000）：Compose 的行盒不会小于字体自身的 ascender+descender，
 * 不压紧的话 `lineHeight` 根本写不进去，换字体后的卡片就比原来高 4.9% / 2.7%。详见
 * `android/FONT-README.md` §3.1。
 */
private val CardFontFamily = FontFamily(
    Font(R.font.card_sans_regular, weight = FontWeight.Normal),
    Font(R.font.card_sans_medium, weight = FontWeight.Medium),
)

/** 华为 EMUI / HarmonyOS「加粗字体」写在 `Settings.System` 里的乘法字重键。 */
private const val HUAWEI_WEIGHT_SCALE_KEY = "font_weight_scale"

/** 同上的「正常态参照值」键（部分 EMUI 版本会额外写一份 1.0 的基准）。 */
private const val HUAWEI_WEIGHT_SCALE_NORMAL_KEY = "font_weight_scale_normal"

/** AOSP Android 12+ 的加法字重键（`Configuration.fontWeightAdjustment` 的来源）。 */
private const val AOSP_WEIGHT_ADJUSTMENT_KEY = "font_weight_adjustment"

/**
 * 卡片排版看到的「系统字重环境」。
 *
 * [weightAdjustment] 是加法通道（AOSP 的 `fontWeightAdjustment`）；
 * [scaleRatio] 是乘法通道的**比值**（华为 `font_weight_scale / font_weight_scale_normal`，正常态 1）。
 *
 * 为什么要存比值而不是原始值：这台华为的正常态是 `font_weight_scale = 0.79`、
 * `font_weight_scale_normal = 0.79`，绝对值和 1 差得很远。把 0.79 当倍率会把正常态的卡片
 * 反过来加粗 1.27 倍 —— 必须相对 normal 取比值，「加粗」才体现为 ratio > 1。
 * 原始值留着给诊断日志。
 */
internal data class CardFontEnv(
    val weightAdjustment: Int = 0,
    val scaleRatio: Float = 1f,
    val rawScale: Float? = null,
    val rawScaleNormal: Float? = null,
) {
    /** 系统是否正开着某种「加粗」。 */
    val boldActive: Boolean
        get() = weightAdjustment != 0 ||
            (scaleRatio.isFinite() && scaleRatio > 0f && scaleRatio != 1f)

    /** 把期望字重换算成应该请求的字重。 */
    fun weightFor(nominal: FontWeight): FontWeight =
        FontWeight(CardFontMath.requestWeight(nominal.weight, weightAdjustment, scaleRatio))
}

/**
 * 供卡片内部读取的字重环境；由 [LockedCardDensity] 提供，默认值表示「系统没加粗」。
 *
 * 卡片全部包在 [LockedCardDensity] 里，所以这个默认值只在「万一有人把卡片文本拿到
 * 锁密度之外渲染」时生效 —— 那时退回「不补偿」，至少不会把字重算错。
 */
internal val LocalCardFontEnv = staticCompositionLocalOf { CardFontEnv() }

/**
 * 把 [content] 内的 `LocalDensity` 换成「[scale] 倍的几何缩放 + 字号不缩放」，
 * 同时把系统「加粗」的字重环境算好放进 [LocalCardFontEnv]。
 *
 * 只改 `fontScale`，不动 `density`：dp 尺寸、圆角、间距、`Modifier.height(IntrinsicSize.Max)`
 * 的固有测量全部保持原样，被替换的只有 sp → px 的换算（`fontScale` 恒为 1）。
 *
 * [scale] 给宽屏并排时用：卡片内容先按手机那个逻辑宽度（334dp）排版，再整体等比放大，
 * 于是平板上的版式与手机完全一致，只是尺码不同。
 */
@Composable
internal fun LockedCardDensity(
    scale: Float = 1f,
    content: @Composable () -> Unit,
) {
    val base = LocalDensity.current
    val locked = remember(base, scale) {
        Density(
            density = base.density * scale,
            fontScale = CARD_FONT_SCALE,
        )
    }
    val env = rememberCardFontEnv()
    CompositionLocalProvider(
        LocalDensity provides locked,
        LocalCardFontEnv provides env,
        content = {
            // 诊断日志（每个配置只打一行），必须在锁过的 density 里量探针，
            // 才能和卡片里真实的 sp → px 换算一致。
            CardFontDiagnostics(env)
            content()
        },
    )
}

/**
 * 读一次系统字重环境。
 *
 * 加法通道直接取 `Configuration.fontWeightAdjustment`（它由框架从
 * `Settings.Secure.font_weight_adjustment` 同步过来，API < 31 没有这个字段）。
 *
 * 乘法通道读华为的两个键并取**比值**：`font_weight_scale / font_weight_scale_normal`。
 * 这台 ELS-AN00 上正常态两个都是 0.79，所以比值正常态是 1.0；只有「加粗」把它抬上去，
 * 比值才 > 1 —— 直接拿 0.79 当倍率会把正常态反过来加粗，是错的。
 * 两个键任一缺失都退回 1f（不补偿），保证小米/原生这类没有这套键的 ROM 完全不受影响。
 */
private fun readCardFontEnv(context: Context): CardFontEnv {
    val adjustment = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        try {
            context.resources.configuration.fontWeightAdjustment
        } catch (t: Throwable) {
            0
        }
    } else {
        0
    }
    val scale = readSystemFloat(context, HUAWEI_WEIGHT_SCALE_KEY)
    val normal = readSystemFloat(context, HUAWEI_WEIGHT_SCALE_NORMAL_KEY)
    return CardFontEnv(
        weightAdjustment = adjustment,
        scaleRatio = CardFontMath.huaweiScaleRatio(scale, normal),
        rawScale = scale,
        rawScaleNormal = normal,
    )
}

/** 读 `Settings.System` 里的浮点键；键不存在或读不到时返回 null（**不是** 1f）。 */
private fun readSystemFloat(context: Context, name: String): Float? {
    return try {
        val cr = context.contentResolver
        if (Settings.System.getString(cr, name) == null) {
            null
        } else {
            Settings.System.getFloat(cr, name, 1f).takeIf { it.isFinite() && it > 0f }
        }
    } catch (t: Throwable) {
        // 个别 ROM 上读系统设置会抛 SecurityException / IllegalArgumentException（值不是数字）。
        null
    }
}

/**
 * 订阅系统字重设置，变化时让卡片重新排版。
 *
 * 关键：华为的「加粗字体」**不一定**会改 `Configuration`，Activity 也就不一定重建。
 * 如果只在组合时读一次，用户开加粗后卡片会一直沿用旧字重（看起来就是「补偿没生效」）。
 * 所以这里额外挂一个 `ContentObserver` 直接盯那几个键，变了就把 [CardFontEnv] 换成新值，
 * 依赖它的 `cardTextStyle` 会立刻重算字重。
 */
@Composable
private fun rememberCardFontEnv(): CardFontEnv {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    var env by remember { mutableStateOf(readCardFontEnv(context)) }

    // 配置变化（Activity 重建 / onConfigurationChanged）时重读一次，覆盖加法通道。
    LaunchedEffect(configuration) {
        val fresh = readCardFontEnv(context)
        if (fresh != env) env = fresh
    }

    DisposableEffect(context) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                val fresh = readCardFontEnv(context)
                if (fresh != env) {
                    Log.w(
                        CARD_FONT_TAG,
                        "font env changed: adjustment=${fresh.weightAdjustment} ratio=${fresh.scaleRatio}" +
                            " raw=${fresh.rawScale}/${fresh.rawScaleNormal}",
                    )
                    env = fresh
                }
            }
        }
        val cr: ContentResolver = context.contentResolver
        try {
            cr.registerContentObserver(Settings.System.getUriFor(HUAWEI_WEIGHT_SCALE_KEY), false, observer)
            cr.registerContentObserver(Settings.System.getUriFor(HUAWEI_WEIGHT_SCALE_NORMAL_KEY), false, observer)
            cr.registerContentObserver(Settings.Secure.getUriFor(AOSP_WEIGHT_ADJUSTMENT_KEY), false, observer)
        } catch (t: Throwable) {
            Log.w(CARD_FONT_TAG, "register font observer failed: $t")
        }
        onDispose {
            try {
                cr.unregisterContentObserver(observer)
            } catch (t: Throwable) {
                // 进程退出时 contentResolver 可能已失效，忽略。
            }
        }
    }
    return env
}

/**
 * 卡片文本样式的唯一入口：把系统「加粗」抵消掉，并禁止字形合成。
 *
 * 做三件事：
 * 1. `fontWeight` 用 [CardFontEnv.weightFor] 反解成请求字重 —— 抵掉加法 / 乘法两层加粗；
 * 2. `fontSynthesis = FontSynthesis.None` —— Compose 在字族里找不到目标字重时会**合成**粗体
 *    （把字形描粗），那会让「减字重」失效：请求 200 也照样被描成 Medium 的观感。
 *    这里明确禁止合成，请求什么字重就渲染什么字重；
 * 3. `fontFamily` 钉成自带的 [CardFontFamily]（Noto Sans SC Regular 子集）—— 不再让系统
 *    字族参与，华为那层渲染期描粗就落在 App 自带字形之外；同时也把「默认族」变成「写明」，
 *    防止 ROM 改动默认族时把卡片带偏。
 *
 * [base] 一般传 `MaterialTheme.typography.xxx`，[nominal] 传「不想被系统加粗影响」的目标字重
 * （卡片里是 Medium / Normal）。设置页不经过这里，照旧跟随系统加粗。
 */
@Composable
internal fun cardTextStyle(base: TextStyle, nominal: FontWeight): TextStyle {
    val env = LocalCardFontEnv.current
    return base.copy(
        fontWeight = env.weightFor(nominal),
        fontSynthesis = FontSynthesis.None,
        fontFamily = CardFontFamily,
    ).pinSystemLineBox(rememberSystemLineBoxEm())
}

/**
 * 「系统字族（原来那套字体）的行盒 ÷ 字号」，随机器而变：实测华为 ELS-AN00 的 HarmonyOS Sans
 * ≈ **1.265 em**、小米 2312DRA50C 的 MiSans ≈ **1.347 em**；自带 Noto Sans SC 原始 hhea 是
 * **1.448 em**（本仓库已把它压到 1.20 em，见 `android/FONT-README.md` §3.1）。
 *
 * 为什么需要它：换字体之后，凡是**没有显式 `lineHeight`** 的 `TextStyle`，行盒会跟着 Noto 的
 * 行距一起变高 —— 实测卡片高度华为 618 → 648（+4.9%）、小米 660 → 678（+2.7%）。要钉回原尺寸，
 * 最稳的办法不是写死一个「1.25em」之类的经验值（两台机器的原字体不同，写死必有一台对不上），
 * 而是在运行时用**同一个** `TextMeasurer` 量一次系统字族在同一字号下的行盒，取比值当
 * `lineHeight` 系数：换字体之前卡片用的就是这个行盒，所以量出来的高度与原版一致
 * （实测两台机器的卡片 bbox 都正好回到 1088×618 / 1100×660）。
 *
 * 注意探针必须走 `FontFamily.Default`（= 系统字族）。华为的「字体粗细」只在**渲染层**描粗，
 * 不改字形度量，所以这个比值与系统是否开着加粗无关、可以缓存。
 */
@Composable
internal fun rememberSystemLineBoxEm(): Float {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    return remember(measurer, density) {
        // 字号取大一点（100sp），把整数取整带来的相对误差压到 0.2% 以下。
        val probeSp = 100f
        val height = measurer.measure(
            text = "88:88",
            style = TextStyle(
                fontFamily = FontFamily.Default,
                fontSize = probeSp.sp,
                fontFeatureSettings = "tnum",
            ),
            maxLines = 1,
        ).size.height.toFloat()
        val probePx = with(density) { probeSp.sp.toPx() }
        if (height > 0f && probePx > 0f) height / probePx else 0f
    }
}

/**
 * 把 [TextStyle] 的行高钉成「系统字族在同一字号下的行盒」，于是自带字体更高的 ascender
 * 不再撑高卡片。只处理**没写 `lineHeight`** 的样式：
 *
 * - 已写死的（Material 的 `labelMedium` / `labelSmall` / `bodySmall` … 全都有 `lineHeight`）
 *   一个字节都不动 —— 它们本来就不受换字体影响；
 * - `fontSize` 还没定的（例如 `HeroClock` 先拿到 `baseStyle`、字号后面才算出来）原样返回，
 *   由调用方在算完字号之后自己调 [pinSystemLineBox]。
 */
internal fun TextStyle.pinSystemLineBox(em: Float): TextStyle {
    if (em <= 0f) return this
    if (lineHeight != TextUnit.Unspecified) return this
    if (fontSize == TextUnit.Unspecified) return this
    return copy(
        lineHeight = (fontSize.value * em).sp,
        // 行盒比字形高出来的那一截怎么分：居中（上下各一半）。写字形位置时明写出来，
        // 免得 Compose 改默认值时卡片里的文字悄悄上下漂。
        lineHeightStyle = LineHeightStyle(
            alignment = LineHeightStyle.Alignment.Center,
            trim = LineHeightStyle.Trim.None,
        ),
    )
}

/** 卡片文本「按可用宽度缩字号」时的下限：9sp（卡片里 fontScale=1，等于 9dp）。 */
internal val MIN_FIT_FONT_SIZE: TextUnit = 9.sp

/**
 * 把 [style] 的字号按可用宽度往下调，直到 [text] 单行放得下（最多迭代两次）。
 *
 * 为什么需要它：卡片已经锁了 `fontScale`，所以「系统字体大小」不会撑破版式；但「地区名」
 * 这类**内容不定长**的文本仍可能超宽（长地名、系统加粗让笔画变宽、外文字符串更长）。
 * 以前只能靠 `TextOverflow.Ellipsis` 砍字尾，用户看到的是「被省略」；这里改成先缩字号，
 * 缩到 [minFontSize] 还放不下才交回给省略号。
 *
 * 只改 `fontSize`、**不动 `lineHeight`**：行高仍是原样式的那一档，所以标签行的高度、
 * 下面两列的位置、竖线接缝都不会因为缩字号而变化 —— 「版式不破」优先于「字大」。
 *
 * 线性缩放（新字号 = 旧字号 × 可用/实测）在 1~3% 的调整范围内足够准；连测两轮是为了
 * 兜住 hinting/字距带来的非线性残差。这里**不能**用 `BoxWithConstraints`：
 * 卡片在宽屏分支里处于 `IntrinsicSize.Max` 下，SubcomposeLayout 参与固有测量会抛异常。
 */
internal fun fitTextStyle(
    measurer: TextMeasurer,
    text: String,
    style: TextStyle,
    maxWidthPx: Float,
    minFontSize: TextUnit = MIN_FIT_FONT_SIZE,
): TextStyle {
    if (text.isEmpty() || maxWidthPx <= 0f) return style
    if (style.fontSize == TextUnit.Unspecified) return style
    var current = style
    repeat(2) {
        val width = measurer.measure(
            text = text,
            style = current,
            maxLines = 1,
            softWrap = false,
        ).size.width.toFloat()
        if (width <= maxWidthPx) return current
        val factor = maxWidthPx / width
        val next = current.fontSize * factor
        if (next.value <= minFontSize.value) {
            return if (current.fontSize.value <= minFontSize.value) {
                current
            } else {
                current.copy(fontSize = minFontSize)
            }
        }
        current = current.copy(fontSize = next)
    }
    return current
}

/** 探针字重：覆盖 Normal / Medium 附近，够看出「系统把字重加了多少」。 */
private val PROBE_WEIGHTS = listOf(100, 300, 400, 500, 600, 700, 900)

/** 上次打印过的那行，避免每个 `LockedCardDensity` 实例都重复打一遍。 */
private var lastDiagnosticLine: String? = null

/**
 * 把「App 看到的字重环境」打成一行日志（`adb logcat -s SolarTimeCard:W`）。
 *
 * 探针在**锁过的** `LocalDensity` 里量：`88:88` / 100sp / `tnum`，这里量出来的宽度与卡片里
 * 真实渲染用的是同一套换算。宽度随字重单调变化，于是对比加粗开/关两组宽度就能反推
 * 「系统实际用了几号字重」，比只看设置值更硬 —— 有些 ROM 会把我们的请求钳到可用字重档位上。
 *
 * 第二行把**所有**名字里带 font / weight / bold 的设置键原样 dump 出来（System + Secure +
 * Global 三张表）。华为/EMUI 的「加粗」到底是哪个键，不必猜：开一次加粗再抓一次日志，
 * 两行一 diff 就看见了。这也顺带验证了「我们订的那几个键」确实是变化的那些键。
 */
@Composable
private fun CardFontDiagnostics(env: CardFontEnv) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val measurer = rememberTextMeasurer()
    LaunchedEffect(env, configuration) {
        val probeStyle = TextStyle(fontSize = 100.sp, fontFeatureSettings = "tnum")
        val widths = PROBE_WEIGHTS.joinToString(separator = ",") { weight ->
            val w = measurer.measure(
                text = "88:88",
                style = probeStyle.copy(fontWeight = FontWeight(weight)),
                maxLines = 1,
            ).size.width
            "$weight:$w"
        }
        val line = buildString {
            append("mfr=").append(Build.MANUFACTURER)
            append(" model=").append(Build.MODEL)
            append(" sdk=").append(Build.VERSION.SDK_INT)
            append(" fontScale=").append(configuration.fontScale)
            append(" adjustment=").append(env.weightAdjustment)
            append(" ratio=").append(env.scaleRatio)
            append(" raw=").append(env.rawScale).append('/').append(env.rawScaleNormal)
            append(" cardMedium=").append(env.weightFor(FontWeight.Medium).weight)
            append(" cardNormal=").append(env.weightFor(FontWeight.Normal).weight)
            append(" probe{").append(widths).append('}')
        }
        if (line != lastDiagnosticLine) {
            lastDiagnosticLine = line
            Log.w(CARD_FONT_TAG, line)
            Log.w(CARD_FONT_TAG, "font settings: " + fontSettingDump(context))
        }
    }
}

/**
 * 三张设置表里所有 font / weight / bold 相关键，排序后拼成一行。
 *
 * 只挑名字里带这三个词的键，所以不会把账号、ID 之类的东西写进日志。
 * 用 `ContentResolver.query` 直接读设置表（`Settings.System.getAll` 是 @hide），
 * 这样「ROM 到底用哪个键表示加粗」由日志自己回答，不用猜。
 */
private fun fontSettingDump(context: Context): String {
    val sb = StringBuilder()
    fun scan(prefix: String, uri: Uri) {
        try {
            val values = LinkedHashMap<String, String>()
            context.contentResolver.query(uri, arrayOf("name", "value"), null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val name = c.getString(0) ?: continue
                    values[name] = c.getString(1) ?: ""
                }
            }
            values.entries
                .filter { (k, _) ->
                    val key = k.lowercase()
                    key.contains("font") || key.contains("weight") || key.contains("bold")
                }
                .sortedBy { it.key }
                .forEach { (k, v) -> sb.append(prefix).append('.').append(k).append('=').append(v).append(' ') }
        } catch (t: Throwable) {
            sb.append(prefix).append(".error=").append(t).append(' ')
        }
    }
    scan("sys", Settings.System.CONTENT_URI)
    scan("secure", Settings.Secure.CONTENT_URI)
    scan("global", Settings.Global.CONTENT_URI)
    return sb.toString().trim()
}
