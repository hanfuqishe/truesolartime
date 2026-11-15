package com.realsuntime.solartime.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.takeOrElse
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.realsuntime.solartime.BuildConfig
import com.realsuntime.solartime.MainViewModel
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.TakeTemperature
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarSnapshot
import com.realsuntime.solartime.solar.SolarTimeMath
import com.realsuntime.solartime.solar.SolarTimeSnapshot
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.ui.theme.TrueSolarTimeTheme
import com.realsuntime.solartime.widget.ChimeAlarm
import com.realsuntime.solartime.widget.WidgetAxis
import java.time.LocalTime

/** 宽屏断点：内容区达到这个宽度就把大卡片与太阳卡片并排（与鸿蒙版同一条规则：560）。 */
private val WIDE_LAYOUT_MIN_WIDTH = 560.dp
/** 手机版大卡片的实测宽度：并排时按这个逻辑宽度排版卡片内容，再整体缩放到实际宽度。 */
private val PHONE_CARD_WIDTH = 334.dp
/** 并排两张卡之间的间距。 */
private val CARD_GAP = 12.dp
/** 缩放系数区间：小平板上不至于把字缩到看不清，大屏上也不无限放大。 */
private const val MIN_CARD_SCALE = 0.8f
private const val MAX_CARD_SCALE = 1.6f
/** 半高秒与主数字之间的间隔。 */
private val SECONDS_GAP = 1.dp
/** 时间字号上下限：下限保证字不糊，上限避免大屏上数字夸张。 */
private const val FALLBACK_HERO_CLOCK_SP = 42f
/** 撑满时留 3% 余量：算出来的字宽正好等于栏宽，右栏会紧贴卡片边缘，留一点才不会擦到圆角。 */
private const val CLOCK_FIT_SAFETY = 0.97f
private const val MIN_HERO_CLOCK_SP = 24f
private const val MAX_HERO_CLOCK_SP = 80f
/** 宽屏并排时把太阳弧线压矮：压低后太阳卡比大卡片略矮，行高由大卡片决定，橙色卡片里就不会再留空白。 */
private val WIDE_ARC_HEIGHT = 74.dp
/** 地图视口的宽高比：手机 4:3、平板 16:9（与鸿蒙版一致）。 */
private const val PHONE_MAP_ASPECT_RATIO = 4f / 3f
private const val WIDE_MAP_ASPECT_RATIO = 16f / 9f

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val now by viewModel.now.collectAsStateWithLifecycle()
    val place by viewModel.place.collectAsStateWithLifecycle()
    val trackingGps by viewModel.trackingGps.collectAsStateWithLifecycle()
    val waitingForFix by viewModel.waitingForFix.collectAsStateWithLifecycle()
    val remindersEnabled by viewModel.remindersEnabled.collectAsStateWithLifecycle()
    val keyTimeChimeEnabled by viewModel.keyTimeChimeEnabled.collectAsStateWithLifecycle()
    val districtName by viewModel.districtName.collectAsStateWithLifecycle()

    val zoneOffsetSeconds by viewModel.zoneOffsetSeconds.collectAsStateWithLifecycle()
    val mapStyle by viewModel.mapStyle.collectAsStateWithLifecycle()
    val keepScreenOn by viewModel.keepScreenOn.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()

    val context = LocalContext.current

    // 卡片上的城市：
    // ① 反查到的行政区划优先；
    // ② 反查还没回来/失败时，只有「预设城市」才回退到城市名；
    // ③ 手工坐标与 GPS 定位没有城市名可用（标签是「手动设置」这类占位词，不该显示），
    //    一律显示减号，等反查结果到了再换成区划名。
    val cityText = districtName?.takeIf { it.isNotBlank() }
        ?: place.labelResName?.let { TimeText.placeLabel(context, place) }?.takeIf { it.isNotBlank() }
        ?: stringResource(R.string.city_unknown)
    val snackbarHostState = remember { SnackbarHostState() }
    var showSettings by rememberSaveable { mutableStateOf(false) }

    val snapshot = remember(now, place, zoneOffsetSeconds) {
        SolarTimeSnapshot.compute(now, place.latitude, place.longitude, zoneOffsetSeconds)
    }

    // 大卡片里的日期、天气、逐时预报与关键时段：半分钟刷新一次就够，不必每秒读偏好；
    // 但新数据一到（例如刚换了城市、天气刚取回来）要立刻重算，所以把天气版本号也当键。
    val weatherRevision = WeatherRepository.revision()
    val heroExtras = remember(place, now.epochSecond / 30, weatherRevision, zoneOffsetSeconds) {
        loadHeroExtras(context, place, now, zoneOffsetSeconds)
    }

    val locationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        viewModel.markLocationPermissionRequested()
        if (result.values.any { it }) {
            viewModel.startGpsTracking()
        } else {
            viewModel.postMessage(context.getString(R.string.msg_location_permission))
        }
    }

    val requestGps: () -> Unit = {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            viewModel.startGpsTracking()
        } else {
            locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    // 默认跟随 GPS：首次启动自动申请一次定位权限。
    LaunchedEffect(Unit) {
        if (viewModel.shouldRequestLocationPermission()) {
            locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    val toggleReminders: (Boolean) -> Unit = { enabled ->
        // 交接提醒只播提示音，不需要通知权限；但需要「闹钟和提醒」才能准时响。
        viewModel.setRemindersEnabled(enabled)
        if (enabled && !ChimeAlarm.canScheduleExact(context)) {
            PowerSettings.openExactAlarmSettings(context)
        }
    }

    val toggleKeyTimeChime: (Boolean) -> Unit = { enabled ->
        // 报时只播提示音，不需要通知权限；但需要「闹钟和提醒」才能准时响。
        viewModel.setKeyTimeChimeEnabled(enabled)
        if (enabled && !ChimeAlarm.canScheduleExact(context)) {
            PowerSettings.openExactAlarmSettings(context)
        }
    }

    LaunchedEffect(message) {
        message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    // 屏幕常亮：只加窗口标志，退到后台后系统照旧按自己的超时熄屏。
    val hostView = LocalView.current
    LaunchedEffect(keepScreenOn) {
        val window = hostView.context.findActivity()?.window ?: return@LaunchedEffect
        if (keepScreenOn) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    // 主题跟着太阳走：白天浅色，夜晚整体换深色（不再看系统的深色开关）。
    TrueSolarTimeTheme(darkTheme = !snapshot.isDay) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            snackbarHost = { SnackbarHost(snackbarHostState) },
        ) { padding ->
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
            ) {
                // 平板/宽屏：大卡片与太阳卡片并排（1:1、等高），卡片内容整体缩放到手机上那个比例。
                val wide = maxWidth >= WIDE_LAYOUT_MIN_WIDTH
                // 自适应缩放：让「卡片的逻辑宽度」恒等于手机卡的 334dp，于是无论平板多宽，
                // 卡片里的版式都和手机一模一样，只是整体按比例放大/缩小。
                // （写死 1.35 会在 640dp 的小平板上出问题：分栏后每张卡只有 294dp，内容会被截断。）
                val cardWidth = (maxWidth - CARD_GAP) / 2
                val cardScale = (cardWidth / PHONE_CARD_WIDTH).coerceIn(MIN_CARD_SCALE, MAX_CARD_SCALE)

                Column {
                    Header(
                        badge = if (place.source == PlaceSource.GPS) {
                            stringResource(R.string.location_badge_gps)
                        } else {
                            cityText
                        },
                        onOpenSettings = { showSettings = true },
                    )
                    Spacer(Modifier.height(12.dp))

                    if (wide) {
                        // IntrinsicSize.Max + fillMaxHeight：两卡取较高的那张作行高，底边自然对齐。
                        // LockedCardDensity 放在 Box 里面（与改动前同一层级）：字体缩放锁死，
                        // 同时几何缩放照旧参与固有测量，IntrinsicSize.Max 不受影响。
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(IntrinsicSize.Max),
                            horizontalArrangement = Arrangement.spacedBy(CARD_GAP),
                        ) {
                            Box(Modifier.weight(1f).fillMaxHeight()) {
                                LockedCardDensity(scale = cardScale) {
                                    HeroCard(
                                        snapshot = snapshot,
                                        districtName = cityText,
                                        coordinates = TimeText.coordinates(context, place.latitude, place.longitude),
                                        waitingForFix = waitingForFix,
                                        extras = heroExtras,
                                        modifier = Modifier.fillMaxHeight(),
                                    )
                                }
                            }
                            Box(Modifier.weight(1f).fillMaxHeight()) {
                                LockedCardDensity(scale = cardScale) {
                                    SunCard(
                                        snapshot = snapshot,
                                        modifier = Modifier.fillMaxHeight(),
                                        arcHeight = WIDE_ARC_HEIGHT,
                                    )
                                }
                            }
                        }

                    } else {
                        // 手机：卡片按 100% 排版，字号同样锁死（见 LockedCardDensity）。
                        LockedCardDensity {
                            HeroCard(
                                snapshot = snapshot,
                                districtName = cityText,
                                coordinates = TimeText.coordinates(context, place.latitude, place.longitude),
                                waitingForFix = waitingForFix,
                                extras = heroExtras,
                            )
                        }
                        Spacer(Modifier.height(14.dp))

                        LockedCardDensity {
                            SunCard(snapshot = snapshot)
                        }
                    }
                    Spacer(Modifier.height(14.dp))

                    // 地图卡片同样锁字号：卡上有标题、经纬度、版权三处文本，
                    // 跟着系统放大就会把地图挤小（视口是按 dp 宽高比算的）。
                    LockedCardDensity {
                        MapCard(
                            place = place,
                            mapStyle = mapStyle,
                            mapAspectRatio = if (wide) WIDE_MAP_ASPECT_RATIO else PHONE_MAP_ASPECT_RATIO,
                        )
                    }
                    Spacer(Modifier.height(14.dp))

                    // 页脚与顶部标题不锁：它们不是「版式即内容」的卡片，
                    // 跟随系统字号更符合可读性预期（设置页同理）。
                    Text(
                        text = stringResource(R.string.version_label, BuildConfig.VERSION_NAME),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(28.dp))
                }
            }
        }

        if (showSettings) {
            SettingsSheet(
                place = place,
                trackingGps = trackingGps,
                remindersEnabled = remindersEnabled,
                keyTimeChimeEnabled = keyTimeChimeEnabled,
                keepScreenOn = keepScreenOn,
                mapStyle = mapStyle,
                onDismiss = { showSettings = false },
                onRequestGps = {
                    showSettings = false
                    requestGps()
                },
                onApplyManual = { lat, lon, label -> viewModel.applyManualPlace(lat, lon, label) },
                onSelectPreset = viewModel::usePreset,
                onToggleReminders = toggleReminders,
                onToggleKeyTimeChime = toggleKeyTimeChime,
                onSelectMapStyle = viewModel::setMapStyle,
                onToggleKeepScreenOn = viewModel::setKeepScreenOn,
                    )
        }
    }
}

/**
 * 顶部：标题、副标题，右侧是位置标识与设置按钮。
 *
 * 位置标识与鸿蒙版一致：跟随 GPS 时显示「GPS」，指定坐标时显示反查到的行政区划。
 */
@Composable
private fun Header(badge: String, onOpenSettings: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 标题与右侧地名都要限宽：地名是不定宽文本，早先它按内容取宽，长地址（例如
        // "Donghuamen Subdistrict, Dongcheng District"）会把左边的标题挤成一字一行。
        // 两者都给权重，地名右对齐、超出省略，标题至少拿 60% 宽度。
        Column(Modifier.weight(1.5f)) {
            Text(
                text = stringResource(R.string.app_name),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = stringResource(R.string.screen_subtitle),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (badge.isNotBlank()) {
            Text(
                text = badge,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.End,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 8.dp, end = 6.dp),
            )
        }
        IconButton(onClick = onOpenSettings) {
            Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.action_settings))
        }
    }
}

@Composable
private fun HeroCard(
    snapshot: SolarSnapshot,
    districtName: String?,
    coordinates: String,
    waitingForFix: Boolean,
    extras: HeroExtras,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val solarSeconds = snapshot.trueSolarTime.toSecondOfDay().toDouble()
    val isDay = snapshot.isDay
    // 真太阳时落在关键时间段里时，数字与时间轴圆点一起换成该时段的配色。
    val inKeyTime = !waitingForFix && extras.bands.any { it.contains(solarSeconds / 60.0) }
    val accent = HeroPalette.accent(isDay)
    // 关键时段的色段一直画出来（与桌面卡片一致），只有「当前正落在某个关键时段里」时才把
    // 真太阳时数字与时间轴圆点也换成该时段的配色。
    val bandTint = if (waitingForFix) null else HeroPalette.band(extras.temperature, isDay)
    val inkTint = if (waitingForFix) null else HeroPalette.ink(extras.temperature, isDay)
    val solarColor = if (inKeyTime) inkTint ?: accent else accent
    val dateTail = listOf(extras.dateText, extras.weatherText, extras.rangeText)
        .filter { it.isNotBlank() }
        .joinToString(" · ")

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Brush.linearGradient(HeroPalette.gradient(isDay)))
            .padding(16.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            // 顶部这一行（`UTC+8` · 地区 · `真太阳时` · 时辰）是**整行一个逻辑单元**：四段文本的
            // 相对位置随行宽分 4 档退化，规则在 SmallRowLayout.cityRowTier 里（纯函数，有单测）：
            //   档 0 左半 `UTC` 贴左、地区贴右｜右半 `真太阳时` 贴左、时辰贴右（两半各占整行一半）；
            //   档 1 收掉「真太阳时」：`UTC` 贴左、地区在 UTC 与时辰之间居中、时辰贴右；
            //   档 2 再收掉 UTC：地区贴左、时辰贴右；
            //   档 3 同档 2，地区尾部省略号。
            // 这一行必须横跨整行、放在下方两列时间内容的上方 —— 档 1 的「居中」是相对整行说的，
            // 仍嵌在左半列里就没有可居中的余地。
            // 行宽只能用 onSizeChanged 取（不能用 BoxWithConstraints：卡片在 IntrinsicSize.Max 里，
            // SubcomposeLayout 参与固有测量会抛异常），再用 TextMeasurer 量各段文本的自然宽度。
            var cityRowWidthPx by remember { mutableStateOf(0f) }
            val cityRowMeasurer = rememberTextMeasurer()
            // 字重显式写死（labelMedium 的默认值就是 Medium），并用 cardFontWeight 抵掉系统
            // 「粗体字」的字重调整：不抵掉的话同一行在这台机器上比在别的机器上宽，
            // 四档退化会提前/延后。
            val cityRowStyle = cardTextStyle(MaterialTheme.typography.labelMedium, FontWeight.Medium)
            val cityRowGap = 8.dp
            val cityRowGapPx = with(LocalDensity.current) { cityRowGap.toPx() }
            // 档 0 左半：地区文字与竖线之间留出的间隙。竖线正落在两半分界上，
            // 右半「真太阳时」从分界右侧 8dp 起排，左侧再留 6dp，线两侧都不会贴着字。
            val cityEndInset = 6.dp
            val cityEndInsetPx = with(LocalDensity.current) { cityEndInset.toPx() }
            val utcLabel = TimeFormat.utcOffsetLabel(snapshot.localOffsetSeconds)
            val cityLabel = districtName ?: ""
            val solarLabel = stringResource(R.string.widget_label_solar)
            // 时辰名走本地化字符串（英文本地化成 "Si hour"），与桌面卡片用同一套；
            // `snapshot.shichenName` 是固定的中文名，不能直接用，否则英文界面下两边写法不一致。
            val shichenLabel = stringResource(
                R.string.hero_shichen,
                TimeText.shichenName(context, snapshot.shichenIndex),
                TimeText.shichenHalf(context, snapshot.secondHalf),
            )
            val utcWidthPx = cityRowMeasurer.measure(utcLabel, cityRowStyle).size.width.toFloat()
            val cityWidthPx = if (cityLabel.isEmpty()) {
                0f
            } else {
                // 档 0 里地区右侧还要让出 cityEndInset，判档时一并算进宽度，
                // 否则那一档会「看起来刚好放下、实际被挤掉 6dp」。
                cityRowMeasurer.measure(cityLabel, cityRowStyle).size.width.toFloat() +
                    cityEndInsetPx
            }
            val solarLabelWidthPx =
                cityRowMeasurer.measure(solarLabel, cityRowStyle).size.width.toFloat()
            val shichenWidthPx =
                cityRowMeasurer.measure(shichenLabel, cityRowStyle).size.width.toFloat()
            val cityRowTier = SmallRowLayout.cityRowTier(
                wUtc = utcWidthPx,
                wCity = cityWidthPx,
                // 档 0 右半的内容从分界处起排，分界处还要留一个间距，这里一并算进标签宽度。
                wLabel = solarLabelWidthPx + cityRowGapPx,
                wShichen = shichenWidthPx,
                rowWidth = cityRowWidthPx,
                gap = cityRowGapPx,
            )

            // 兜底的一档：到了档 1~3，「地区名」已经被挤成整行里唯一可压缩的文本。
            // 这时不再只靠省略号砍字尾，而是**按自己这一行的可用宽度反算字号**：
            // 缩小到放得下为止（下限 MIN_FIT_FONT_SIZE），连下限都放不下才交给省略号。
            // 行高不跟着变（见 fitTextStyle），所以标签行高度、下面两列与竖线的位置都不动。
            // 档 0 是「两半各自排」的宽屏形态，地区只在半行里有固定权位，维持原来的省略号策略。
            val cityFitStyle = when (cityRowTier) {
                0 -> cityRowStyle
                1 -> fitTextStyle(
                    measurer = cityRowMeasurer,
                    text = cityLabel,
                    style = cityRowStyle,
                    maxWidthPx = (
                        cityRowWidthPx - utcWidthPx - shichenWidthPx - cityRowGapPx * 2f
                        ).coerceAtLeast(0f),
                )
                else -> fitTextStyle(
                    measurer = cityRowMeasurer,
                    text = cityLabel,
                    style = cityRowStyle,
                    maxWidthPx = (cityRowWidthPx - shichenWidthPx - cityRowGapPx).coerceAtLeast(0f),
                )
            }

            // 竖分隔线的上端跟着档位走：
            //   档 0 —— 标签行仍是左右两半（左半地区贴右、右半「真太阳时」贴左），两半的分界就是
            //           下面两列的分界，所以线要从标签行顶部一路画下来才连得上；
            //   档 1~3 —— 标签行已合并成一整行，线只盖下方两列（与以前一样）。
            // 两段线共用下面这套尺寸（左右各让 12dp，中心仍落在整行 50% 上）。
            val dividerColor = Color(0x33FFFFFF)
            val dividerWidth = 1.dp
            val dividerSideInset = 12.dp
            // 两列行里的那条线从 3dp 处起画，档 0 的上延段要接到它的顶端，所以多补 3dp。
            val dividerTopPadding = 3.dp
            val dividerColumnHeight = 58.dp
            var labelRowHeightPx by remember { mutableStateOf(0f) }
            // 上延段的顶端要和**标签文字的上沿**齐平（不是标签行的顶边）：文字画在行盒（lineHeight）
            // 里、上下各留一半行距，所以字形上沿比行盒顶边还要低 (行高 − 字号) / 2；
            // 标签行万一比文本本身更高（居中对齐），再补上差值的一半。
            // 字号/行高都从同一套 style 里取；卡片内 fontScale 已锁成 1，所以这里的 px 与
            // 系统字体缩放无关。
            val insetDensity = LocalDensity.current
            val labelTextHeightPx = cityRowMeasurer
                .measure(solarLabel, cityRowStyle, maxLines = 1)
                .size.height.toFloat()
            val labelFontSizePx = with(insetDensity) { cityRowStyle.fontSize.toPx() }
            val labelLineHeightPx = with(insetDensity) {
                cityRowStyle.lineHeight.takeOrElse { cityRowStyle.fontSize }.toPx()
            }
            val dividerTopInsetPx = ((labelLineHeightPx - labelFontSizePx) / 2f).coerceAtLeast(0f) +
                ((labelRowHeightPx - labelTextHeightPx) / 2f).coerceAtLeast(0f)
            // 标签行与两列放进同一个 Box，档 0 那条线才能当 overlay 画到标签行顶部。
            // 高度只能用 onSizeChanged 量（不能用 BoxWithConstraints：卡片在 IntrinsicSize.Max 里，
            // SubcomposeLayout 参与固有测量会抛异常）。
            Box(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .onSizeChanged {
                                cityRowWidthPx = it.width.toFloat()
                                labelRowHeightPx = it.height.toFloat()
                            },
                        verticalAlignment = Alignment.CenterVertically,
                        // 档 0 是两半各自排（间距在两半内部），档 1~3 才需要元素之间统一留间距。
                        horizontalArrangement = if (cityRowTier == 0) {
                            Arrangement.Start
                        } else {
                            Arrangement.spacedBy(cityRowGap)
                        },
                    ) {
                        if (cityRowTier == 0) {
                            // 档 0：左右两半各占整行一半（与下面两列等宽）。
                            // 左半 `UTC` 贴左、地区贴右（贴着两半的分界）；右半「真太阳时」贴左、时辰贴右。
                            Row(
                                modifier = Modifier.weight(1f),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(cityRowGap),
                            ) {
                                Text(
                                    text = utcLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL,
                                    maxLines = 1,
                                )
                                Text(
                                    text = cityLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL_DIM,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.End,
                                    // 吃满 UTC 之后的剩余宽度，`TextAlign.End` 才有把文字推到分界处的余量；
                                    // 尾部再让出 6dp，地区与竖线之间留出明显间隙（不与线贴在一起）。
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(end = cityEndInset),
                                )
                            }
                            Row(
                                modifier = Modifier
                                    .weight(1f)
                                    // 两半各自贴着分界，这里再留一个间距，否则地区与「真太阳时」会挤在一起。
                                    .padding(start = cityRowGap),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(cityRowGap),
                            ) {
                                Text(
                                    text = solarLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL,
                                    maxLines = 1,
                                )
                                Text(
                                    text = shichenLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL_DIM,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.End,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        } else {
                            // 档 1：收掉「真太阳时」，整行当一个整体 —— UTC 贴左、时辰贴右、地区居中。
                            // 档 2/3：再收掉 UTC —— 地区贴左（档 3 尾部省略号）。任何档位时辰都贴整行最右。
                            if (cityRowTier == 1) {
                                Text(
                                    text = utcLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL,
                                    maxLines = 1,
                                )
                            }
                            Text(
                                text = cityLabel,
                                style = cityFitStyle,
                                color = HeroPalette.LABEL_DIM,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = if (cityRowTier == 1) TextAlign.Center else TextAlign.Start,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                text = shichenLabel,
                                style = cityRowStyle,
                                color = HeroPalette.LABEL_DIM,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = TextAlign.End,
                            )
                        }
                    }

                    // 下面两列时间内容：左标准时、右真太阳时。
                    // 两列之间那条竖线在这里；档 0 时它还要向上延伸到标签行顶部（见上面
                    // Box 里的 overlay）。
                    Row(modifier = Modifier.fillMaxWidth()) {
                        // 左：当地标准时间（所在地的法定时区；中国境内就是北京时间，
                        // 出国或手工指定外地坐标时换成当地标准时。时区标签在上面的整行里）
                        Column(modifier = Modifier.weight(1f)) {
                            HeroClock(
                                text = TimeFormat.clock(snapshot.localStandardTime),
                                seconds = snapshot.localStandardTime.second,
                                color = Color.White,
                            )
                        }

                        Box(
                            modifier = Modifier
                                .padding(
                                    start = dividerSideInset,
                                    end = dividerSideInset,
                                    top = dividerTopPadding,
                                )
                                .width(dividerWidth)
                                .height(dividerColumnHeight)
                                .background(dividerColor),
                        )

                        // 右：真太阳时（逐秒刷新）
                        Column(modifier = Modifier.weight(1f)) {
                            if (waitingForFix) {
                                HeroClock(text = "--:--", seconds = null, color = solarColor)
                            } else {
                                HeroClock(
                                    text = "%02d:%02d".format(snapshot.trueSolarTime.hour, snapshot.trueSolarTime.minute),
                                    seconds = snapshot.trueSolarTime.second,
                                    color = solarColor,
                                )
                            }
                        }
                    }
                }

                // 档 0 的上延段：从**标签文字上沿**补到两列那条线的起点，两段接起来是一条从
                // 文字顶部通到两列底部的整线。这里用与下面两列**同一套**排布（左右各 weight 1、
                // 中间 1dp + 左右各 12dp）来摆这一小段线，四舍五入后 x 与下面那条严格重合，
                // 接缝处不会错开 1px。
                if (cityRowTier == 0 && labelRowHeightPx > 0f) {
                    // 顶端下移 dividerTopInsetPx（= 行盒里字形上沿之上的空白），高度同比减掉，
                    // 底端仍接在两列那条线上。
                    val overlayHeightPx = (
                        labelRowHeightPx +
                            with(insetDensity) { dividerTopPadding.toPx() } -
                            dividerTopInsetPx
                        ).coerceAtLeast(0f)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = with(insetDensity) { dividerTopInsetPx.toDp() }),
                    ) {
                        Spacer(Modifier.weight(1f))
                        Box(
                            modifier = Modifier
                                .padding(start = dividerSideInset, end = dividerSideInset)
                                .width(dividerWidth)
                                .height(with(insetDensity) { overlayHeightPx.toDp() })
                                .background(dividerColor),
                        )
                        Spacer(Modifier.weight(1f))
                    }
                }
            }

            Spacer(Modifier.height(6.dp))

            // 日期/天气与经纬度同一行：日期行吃满剩余宽度，经纬度贴右。
            // 放不下「日期/天气」与经纬度两者时，优先保住日期与天气，把右侧经纬度隐藏。
            // 宽度用 onSizeChanged 取（不能用 BoxWithConstraints：卡片在 IntrinsicSize.Max 里，
            // SubcomposeLayout 参与固有测量会抛异常），再用 TextMeasurer 量两者自然宽度。
            var statsRowWidthPx by remember { mutableStateOf(0f) }
            val rowMeasurer = rememberTextMeasurer()
            // 同上：日期行/经纬度也把字重钉死（并抵掉系统加粗），避免这一行被撑宽、把经纬度挤掉。
            val labelStyle = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium)
            val gapPx = with(LocalDensity.current) { 8.dp.toPx() }
            val dateWidthPx = rowMeasurer.measure(dateTail, labelStyle).size.width.toFloat()
            val coordWidthPx = if (coordinates.isEmpty()) {
                0f
            } else {
                rowMeasurer.measure(coordinates, labelStyle).size.width.toFloat()
            }
            val showCoordinates = SmallRowLayout.shouldShowTrailing(
                leadingWidthPx = dateWidthPx,
                trailingWidthPx = coordWidthPx,
                gapPx = gapPx,
                availablePx = statsRowWidthPx,
            )
            // 同理兜底：日期行也可能放不下（长城市名 + 天气 + 温度区间，再被经纬度挤）。
            // 能收起经纬度就先收；收完还放不下就把日期行字号按可用宽度缩下来，
            // 缩到下限仍放不下才交给省略号。行高不变，所以下面时间轴/逐时的位置不跳。
            val dateFitStyle = fitTextStyle(
                measurer = rowMeasurer,
                text = dateTail,
                style = labelStyle,
                maxWidthPx = (
                    statsRowWidthPx - if (showCoordinates) coordWidthPx + gapPx else 0f
                    ).coerceAtLeast(0f),
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .onSizeChanged { statsRowWidthPx = it.width.toFloat() },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = dateTail,
                    style = dateFitStyle,
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (showCoordinates) {
                    Text(
                        text = coordinates,
                        style = labelStyle,
                        color = HeroPalette.LABEL_DIM,
                        maxLines = 1,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }

            Spacer(Modifier.height(10.dp))

            // 0–24 时时间轴：与桌面卡片、鸿蒙版同款（1vp 细线 + 柔化圆点）
            HeroAxis(
                solarSecondsOfDay = if (waitingForFix) 0.0 else solarSeconds,
                bands = if (waitingForFix) emptyList() else extras.bands,
                bandColor = bandTint,
                dotColor = if (inKeyTime && bandTint != null) bandTint else HeroPalette.DOT,
            )
            if (!waitingForFix && extras.hourly.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
                HeroHourly(extras.hourly)
            }
        }
    }
}

/** 大卡片用的配色：白天暖橙底、白字；夜里深蓝底、金色真太阳时。 */
private object HeroPalette {
    val LABEL: Color = Color(0xCCFFFFFF)
    val LABEL_DIM: Color = Color(0xB3FFFFFF)
    val DOT: Color = Color.White
    private val GOLD: Color = Color(0xFFF5D68A)
    /** 白天橙底上的真太阳时：淡金，比纯白暖一档，又不至于和底色糊在一起。 */
    private val DAY_ACCENT: Color = Color(0xFFFFE6B4)
    private val COLD: Color = Color(0xFF4CAF7D)
    private val HOT: Color = Color(0xFFD9534F)
    // 白天数字色的两个端点：0% 用「最淡」，100% 用时间轴色段的深色；默认取中间偏浓。
    // 白天/夜间都用「最淡」一档：浓度统一 0%（用户确认）。
    private val COLD_INK_DAY: Color = Color(0xFFBCF5CA)
    private val HOT_INK_DAY: Color = Color(0xFFFFC4C9)
    private val COLD_INK_NIGHT: Color = Color(0xFFA6E4C3)
    private val HOT_INK_NIGHT: Color = Color(0xFFF0A9A6)
    // 时间轴上的色段、圆点仍用深一档，淡色在橙底上几乎看不出边界。
    private val COLD_BAND_ON_DAY: Color = Color(0xFF2E7D32)
    private val HOT_BAND_ON_DAY: Color = Color(0xFFB3261E)

    fun gradient(isDay: Boolean): List<Color> = if (isDay) {
        listOf(Color(0xFFF7A64B), Color(0xFFEA7A2C))
    } else {
        listOf(Color(0xFF2A3B5C), Color(0xFF151B2E))
    }

    /** 真太阳时的强调色：白天用白字，夜里用金色。 */
    fun accent(isDay: Boolean): Color = if (isDay) DAY_ACCENT else GOLD

    /**
     * 关键时段里真太阳时数字的颜色。
     *
     * [intensity] 只影响白天：0 = 最淡（[COLD_INK_DAY_PALE] / [HOT_INK_DAY_PALE]），
     * 1 = 与时间轴色段同色（[COLD_BAND_ON_DAY] / [HOT_BAND_ON_DAY]）。夜间始终用 [COLD] / [HOT]。
     */
    fun ink(temperature: TakeTemperature?, isDay: Boolean): Color? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_INK_DAY else COLD_INK_NIGHT
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_INK_DAY else HOT_INK_NIGHT
        else -> null
    }

    /** 关键时段在时间轴上的色段与圆点颜色。 */
    fun band(temperature: TakeTemperature?, isDay: Boolean): Color? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_BAND_ON_DAY else COLD
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_BAND_ON_DAY else HOT
        else -> null
    }
}

/** 时间轴：1vp 轨道 + 关键时段的色段 + 当前时刻的柔化圆点。 */
@Composable
private fun HeroAxis(
    solarSecondsOfDay: Double,
    bands: List<TakeBand>,
    bandColor: Color?,
    dotColor: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier.fillMaxWidth().height(11.dp)) {
        val middle = size.height / 2f
        val thickness = 1.dp.toPx()
        drawRect(
            color = Color(0x40FFFFFF),
            topLeft = Offset(0f, middle - thickness / 2f),
            size = Size(size.width, thickness),
        )
        if (bandColor != null) {
            WidgetAxis.spans(bands).forEach { span ->
                val left = size.width * (span.startMinutes / MINUTES_PER_DAY).toFloat()
                val right = size.width * (span.endMinutes / MINUTES_PER_DAY).toFloat()
                drawRect(
                    color = bandColor,
                    topLeft = Offset(left, middle - thickness / 2f),
                    size = Size(right - left, thickness),
                )
            }
        }
        val radius = 5.5.dp.toPx()
        val center = Offset(
            x = (size.width * (solarSecondsOfDay / SECONDS_PER_DAY).toFloat()).coerceIn(0f, size.width),
            y = middle,
        )
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(dotColor, dotColor.copy(alpha = 0.45f), dotColor.copy(alpha = 0f)),
                center = center,
                radius = radius,
            ),
            radius = radius,
            center = center,
        )
    }
}

/** 六格逐时预报：时刻、天气图标、天气名称，与桌面卡片同一套取数规则。 */
@Composable
private fun HeroHourly(cells: List<HourCell>) {
    Row(modifier = Modifier.fillMaxWidth()) {
        cells.forEach { cell ->
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = cell.label,
                    style = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium),
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                )
                Image(
                    painter = painterResource(cell.iconRes),
                    contentDescription = null,
                    modifier = Modifier.padding(top = 3.dp).size(22.dp),
                )
                Text(
                    text = cell.condition,
                    style = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium),
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 1.dp),
                )
            }
        }
    }
}

private const val MINUTES_PER_DAY: Double = 24.0 * 60.0
private const val SECONDS_PER_DAY: Double = 24.0 * 3600.0

/**
 * 首页大卡片里的一格时间（`HH:mm` + 半高秒）。
 *
 * 两条硬规则：
 * 1. **秒是半高**：秒字号恒为主字号的 1/2；
 * 2. **整段时间正好撑满可用宽度**：用固定样本按 100sp 量出「主字号 + 半高秒」的实际宽度，
 *    再按这一栏的可用宽度反推主字号 —— 数字是等宽（`tnum`），所以不同时刻的宽度一致，
 *    不会忽宽忽窄。这样手机、平板（并排两栏、卡片被缩放）都自动铺满，不需要手调参数。
 *
 * 字号反推只在 `fontScale == 1` 时成立：探针按 sp 量、最终也按 sp 渲染，两者之间差的就是
 * `fontScale`；外层 `LockedCardDensity` 已把它锁成 1，所以「1sp = 1dp」在这里恒成立
 * （秒数那个 `(mainSp * 0.12f).dp` 的下沉量也是按这条前提写的：1sp 与 1dp 等值）。
 * 字重走 `cardFontWeight`：显式给出目标字重，并把系统「粗体字」的调整量抵掉。
 */
@Composable
private fun HeroClock(text: String, seconds: Int?, color: Color, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val baseStyle = cardTextStyle(
        TextStyle(fontFeatureSettings = "tnum"),
        FontWeight.Medium,
    )
    val probeSp = 100f
    // 用「88:88」与「:88」作样本：等宽数字下与实际渲染同宽，和具体时刻无关。
    val mainProbePx = measurer
        .measure("88:88", baseStyle.copy(fontSize = probeSp.sp), maxLines = 1)
        .size.width.toFloat()
    val secondsProbePx = if (seconds == null) {
        0f
    } else {
        measurer
            .measure(":88", baseStyle.copy(fontSize = (probeSp / 2f).sp), maxLines = 1)
            .size.width.toFloat()
    }
    val gapPx = if (seconds == null) 0f else with(density) { SECONDS_GAP.toPx() }
    val totalRatio = (mainProbePx + secondsProbePx + gapPx) / probeSp // 每 1sp 对应的像素宽

    // 用 onSizeChanged 取这一栏的可用宽度（不能用 BoxWithConstraints：它是 SubcomposeLayout，
    // 外面 Row 的 IntrinsicSize.Max 会向它要固有尺寸，直接抛 IllegalStateException）。
    var availablePx by remember { mutableIntStateOf(0) }
    // totalRatio 已经是「每 1sp 占多少像素」（探针按 100sp 量出来），所以直接相除就是 sp；
    // 不能再走 toSp() —— 那会再除一次 density × fontScale，字号会被压小一半。
    val mainSp = if (totalRatio > 0f && availablePx > 0) {
        availablePx / totalRatio * CLOCK_FIT_SAFETY
    } else {
        FALLBACK_HERO_CLOCK_SP
    }.coerceIn(MIN_HERO_CLOCK_SP, MAX_HERO_CLOCK_SP)
    val secondsSp = mainSp / 2f

    Row(
        verticalAlignment = Alignment.Bottom,
        modifier = modifier
            .fillMaxWidth()
            .onSizeChanged { availablePx = it.width },
    ) {
        Text(
            text = text,
            style = baseStyle.copy(fontSize = mainSp.sp),
            color = color,
            maxLines = 1,
        )
        if (seconds != null) {
            Text(
                text = ":%02d".format(seconds),
                style = baseStyle.copy(fontSize = secondsSp.sp),
                color = color,
                maxLines = 1,
                // 秒是半高，往上抬一点让它与主数字的基线齐平（间距按主字号等比）。
                modifier = Modifier.padding(start = SECONDS_GAP, bottom = (mainSp * 0.12f).dp),
            )
        }
    }
}

@Composable
private fun SunCard(
    snapshot: SolarSnapshot,
    modifier: Modifier = Modifier,
    arcHeight: Dp = 110.dp,
) {
    val context = LocalContext.current
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.sun_section_title),
                    // 字重显式写出（titleSmall 默认就是 Medium），并由 cardTextStyle 抵掉
                    // 系统「加粗」的加法 / 乘法两层调整。
                    style = cardTextStyle(MaterialTheme.typography.titleSmall, FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = stringResource(R.string.altitude, snapshot.altitudeDegrees),
                    style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Medium),
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            Spacer(Modifier.height(10.dp))

            SunArc(
                progress = daylightProgress(snapshot),
                isDay = snapshot.isDay,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(arcHeight),
            )

            Spacer(Modifier.height(10.dp))

            if (snapshot.polar == SolarTimeMath.PolarState.NORMAL) {
                Row(Modifier.fillMaxWidth()) {
                    SunTimeItem(stringResource(R.string.sunrise), snapshot.sunriseLocal, Modifier.weight(1f))
                    SunTimeItem(stringResource(R.string.solar_noon), snapshot.solarNoonLocal, Modifier.weight(1f))
                    SunTimeItem(stringResource(R.string.sunset), snapshot.sunsetLocal, Modifier.weight(1f))
                }
                Spacer(Modifier.height(10.dp))
                Text(
                    text = stringResource(
                        R.string.daylight_line,
                        TimeText.duration(context, snapshot.daylightSeconds),
                        TimeFormat.clock(snapshot.sunriseTrueSolar),
                        TimeFormat.clock(snapshot.sunsetTrueSolar),
                    ),
                    style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Normal),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text(
                    text = if (snapshot.polar == SolarTimeMath.PolarState.MIDNIGHT_SUN) {
                        stringResource(
                            R.string.polar_day,
                            TimeFormat.clock(snapshot.solarNoonLocal),
                        )
                    } else {
                        stringResource(
                            R.string.polar_night,
                            TimeFormat.clock(snapshot.solarNoonLocal),
                        )
                    },
                    style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Normal),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SunTimeItem(label: String, time: LocalTime?, modifier: Modifier = Modifier) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = label,
            style = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = TimeFormat.clock(time),
            style = cardTextStyle(
                TextStyle(fontSize = 17.sp, fontFeatureSettings = "tnum"),
                FontWeight.Medium,
            ),
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SunArc(progress: Float, isDay: Boolean, modifier: Modifier = Modifier) {
    val trackColor = MaterialTheme.colorScheme.outlineVariant
    val sunColor = if (isDay) Color(0xFFFFB300) else MaterialTheme.colorScheme.outline

    Canvas(modifier) {
        val horizonY = size.height * 0.88f
        val start = Offset(size.width * 0.06f, horizonY)
        val end = Offset(size.width * 0.94f, horizonY)
        val control = Offset(size.width / 2f, -size.height * 0.42f)

        val arc = Path().apply {
            moveTo(start.x, start.y)
            quadraticTo(control.x, control.y, end.x, end.y)
        }
        drawPath(
            path = arc,
            color = trackColor,
            style = Stroke(width = 2.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f))),
        )
        drawLine(trackColor, Offset(0f, horizonY), Offset(size.width, horizonY), strokeWidth = 2f)

        val t = progress.coerceIn(0f, 1f)
        val u = 1f - t
        val sunX = u * u * start.x + 2f * u * t * control.x + t * t * end.x
        val sunY = u * u * start.y + 2f * u * t * control.y + t * t * end.y
        val center = Offset(sunX, sunY)
        if (isDay) {
            drawCircle(sunColor.copy(alpha = 0.18f), radius = 20f, center = center)
        }
        drawCircle(sunColor, radius = 7f, center = center)
    }
}

private fun daylightProgress(snapshot: SolarSnapshot): Float {
    val sunrise = snapshot.sunriseTrueSolar ?: return 0.5f
    val sunset = snapshot.sunsetTrueSolar ?: return 0.5f
    val start = sunrise.toSecondOfDay().toFloat()
    var end = sunset.toSecondOfDay().toFloat()
    if (end <= start) end += 86_400f
    var current = snapshot.trueSolarTime.toSecondOfDay().toFloat()
    if (current < start) current += 86_400f
    return ((current - start) / (end - start)).coerceIn(0f, 1f)
}

/** Compose 的 LocalView.context 可能是 ContextWrapper 包了几层，取出宿主 Activity。 */
private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
