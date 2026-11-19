import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CityIndex, NearbyCity } from '../core/CityIndex';
import { DistrictNames } from '../core/DistrictName';
import { DEFAULT_ZOOM, MapLayer, MapStyle, MapTile, MapTilesLogic, TILE_PX } from '../core/MapTiles';
import { MapTileService, MapLoadResult } from '../services/MapTileService';
import { MapUiState, ProbeDecision, sameUiState } from '../core/MapFallback';
import { Place, PlaceSource } from '../core/Place';
import { LocationPlaceholders, UnknownLocationLogic } from '../core/LocationUnknown';
import { PlaceBadgeLogic } from '../core/PlaceBadge';
import { Shichen } from '../core/Shichen';
import { SolarSnapshot, SolarTimeSnapshot } from '../core/SolarSnapshot';
import { AxisSegment, TakeBand, TakeTimeLogic, TakeTimeSchedule } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { CivicTimeLogic } from '../core/CivicTime';
import { DialLabels } from '../core/DialLabels';
import { DistrictLayoutTier } from '../core/DistrictLayout';
import { HorizonSpan, MotionArrow, SunArcSpan, SunLabelAnchors, SunPath, SunPathGeometry } from '../core/SunPath';
import { SunDialColors } from '../core/SunDialColors';
import { PolarState, SolarTimeMath } from '../core/SolarTimeMath';
import { HourPoint, WeatherLogic, WeatherSlot, WeatherSnapshot } from '../core/Weather';
import { ThemeMode } from '../core/ThemeMode';
import { font, MeasureUtils, router } from '@kit.ArkUI';
import { CARD_FONT_MEDIUM, CARD_FONT_REGULAR } from '../common/CardFont';
import { weatherIcon } from '../common/WeatherIcon';
import { AppStore } from '../services/Store';
import { AppInfo } from '../services/AppInfo';
import { CardService } from '../services/CardService';
import { ChimePlayer } from '../services/ChimePlayer';
import { DistrictService } from '../services/DistrictService';
import { KeyTimeService } from '../services/KeyTimeService';
import { LocationService, GeoPoint } from '../services/LocationService';
import { ReminderService } from '../services/ReminderService';
import { KeepAwake } from '../services/KeepAwake';
import { WeatherService } from '../services/WeatherService';
import { AppPalette, paletteFor } from '../common/Theme';

const HERO_COLOR: string = '#F5D68A';
/** 白天橙底上的真太阳时：淡金，比纯白暖一档，又不至于和底色糊在一起。 */
const DAY_ACCENT: string = '#FFE6B4';
const COLD_COLOR: string = '#4CAF7D';
const HOT_COLOR: string = '#D9534F';
/** 大卡片按昼夜换底色：白天暖橙，夜里深蓝（与 Android 卡片同一套配色）。 */
const DAY_TOP_COLOR: string = '#F7A64B';
const DAY_BOTTOM_COLOR: string = '#EA7A2C';
const NIGHT_TOP_COLOR: string = '#2A3B5C';
const NIGHT_BOTTOM_COLOR: string = '#151B2E';
/**
 * 关键时段：数字用与淡金同浓度的淡绿／淡红，色段仍用深一档（淡色在橙底上几乎看不出边界）。
 */
const COLD_INK_ON_DAY_COLOR: string = '#BCF5CA';
const HOT_INK_ON_DAY_COLOR: string = '#FFC4C9';
// 夜间数字也用同一档「最淡」（浓度统一 0%）
const COLD_INK_ON_NIGHT_COLOR: string = '#A6E4C3';
const HOT_INK_ON_NIGHT_COLOR: string = '#F0A9A6';
const COLD_BAND_ON_DAY_COLOR: string = '#2E7D32';
const HOT_BAND_ON_DAY_COLOR: string = '#B3261E';
/** 没有名字可用时的占位符：半角减号（与 Android 的 `city_unknown` 一致，不用全角「—」）。 */
const CITY_UNKNOWN: string = '-';
/** 应用在前台时的定位节奏：每分钟一次（桌面卡片是 5 分钟一次）。 */
const GPS_INTERVAL_MILLIS: number = 60 * 1000;
/**
 * 宽屏断点（vp）：超过它就把「大卡片」与「太阳」两张卡并排。
 *
 * 手机约 366vp、MatePad Pro 13 竖屏约 600vp（app 锁竖屏）、横屏更宽。
 * 单卡横跨 600vp 会把时钟与文字拉得很稀，所以宽屏按 1:1 并排（两卡同高），
 * 同时地图仍占满整宽。
 */
const WIDE_LAYOUT_BREAKPOINT: number = 560;
/**
 * 太阳卡圆盘画布的高度（vp，对应 Android 的 `SUN_DIAL_HEIGHT = 194.dp`）。
 *
 * 画布**满卡片内容宽 + 定高**：几何层取 `radius = 0.38 × min(w, h)`，定高后半径只跟高度走，
 * 手机 294×194 与平板放大后是同一套版式。
 */
const SUN_DIAL_HEIGHT: number = 194;
/**
 * 太阳卡的自然高度（vp，Android ≈282 = 上下内边距 20×2 + 标题行 + 8 + 194 + 4 + 白昼行）。
 *
 * 宽屏并排时 ArkUI 的 Row 没有 Stretch，给两张卡同一个 minHeight 才能底边对齐；
 * 这个值也正好是太阳卡的自然高度，手机上不会多出留白。
 */
const SUN_CARD_HEIGHT: number = 282;
/** 圆盘外侧标签的间距（vp，与 Android 的 SUN_LABEL_* 常量一一对应）。 */
const SUN_LABEL_GAP: number = 10;
const SUN_NOON_LABEL_GAP: number = 8;
const SUN_LABEL_TOP_INSET: number = 18;
const SUN_LABEL_RISE: number = 10;
/** 地平线在画布左右各内缩多少（vp）：与 Android 的 `SUN_HORIZON_INSET = 4.dp` 一致。 */
const SUN_HORIZON_INSET: number = 4;
/** 一天的秒数：极昼时白昼时长按整天算。 */
const DAY_SECONDS: number = 86_400;
/** 真太阳时秒数 → 小时数（0–24，含小数）。 */
const SECONDS_PER_HOUR: number = 3600;
/**
 * 首页大卡片的时间字号规则（与安卓版一致）：
 *   1. 秒恒为主字号的 1/2（半高）；
 *   2. 「时:分:秒」的总宽正好撑满这一栏。
 * 做法：按 100fp 量出「00:00」与「:00」的宽度，得到「每 1fp 占多少 vp」的比例，
 * 再按这一栏的实测宽度反推主字号；等宽数字下与具体时刻无关，所以不会忽大忽小。
 */
const HERO_CLOCK_FALLBACK_FP: number = 42;
const HERO_CLOCK_MIN_FP: number = 24;
const HERO_CLOCK_MAX_FP: number = 96;
/** 撑满时留 3% 余量，免得右栏秒数贴到卡片边缘。 */
const HERO_CLOCK_FIT_SAFETY: number = 0.97;
/** 秒与主数字之间的间隔（vp），算进比例里一起摊掉。 */
const HERO_CLOCK_SECONDS_GAP: number = 1;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 上一秒与这一秒之间是否跨过了 target（真太阳时当天秒数），跨日也处理。 */
function crossed(previous: number, current: number, target: number): boolean {
  if (previous < 0) {
    return false;
  }
  if (current >= previous) {
    return previous < target && target <= current;
  }
  return target > previous || target <= current;
}

function segmentLength(item: string): number {
  const parts: string[] = item.split(',');
  const length: number = Number.parseFloat(parts[0]);
  return isNaN(length) || length <= 0 ? 1 : length;
}

function isBandSegment(item: string): boolean {
  const parts: string[] = item.split(',');
  return parts.length > 1 && parts[1] !== '-1';
}

@Entry
@Component
struct Index {
  @State snapshot: SolarSnapshot = SolarTimeSnapshot.compute(
    Date.now(),
    Place.DEFAULT.latitude,
    Place.DEFAULT.longitude,
    'zh-Hans',
    -1,
    Place.DEFAULT.countryCode
  );
  /** 真太阳时当天秒数，每秒更新；大时钟只依赖它。 */
  @State solarSecond: number = 0;
  /** 北京时间当天秒数，每秒更新。 */
  /** 当地标准时间的当天秒数，每秒更新。 */
  @State standardSecond: number = 0;
  /** 上一次的昼夜判定，用来在日落/日出那一刻切换主题。 */
  private dayThemeCached: boolean = true;
  @State language: string = 'zh-Hans';
  /**
   * 内容区宽度（vp）。用来做平板适配：宽屏把「大卡片」和「太阳」并排，
   * 免得一张卡横跨 600vp 被拉得很稀。手机（约 366vp）保持上下排列。
   */
  @State contentWidth: number = 0;
  /** 大卡片里时钟那一栏的实测宽度（vp）；时间字号按它反推，做到撑满栏宽。 */
  @State clockColumnWidth: number = 0;
  /** 日期/天气那一行的可用宽度（vp）；空间不够时用来决定是否隐藏经纬度。 */
  @State dateRowWidth: number = 0;
  /** 「每 1fp 占多少 vp」的缓存，避免每次重建都去量文本。 */
  private clockRatioCache: number = 0;
  /** 系统字体「行盒 / 字号」比例，量一次缓存（钉卡片行高用）。 */
  private lineBoxRatioCache: number = 0;
  /** 大卡片「地区」字号的缓存键与结果：名字／栏宽／语言变了才重新量。 */
  private districtFontKey: string = '';
  private districtFontFit: number = 0;
  /** 白天／夜间两套主题，按太阳高度角切换（见 common/Theme.ets）。 */
  @State palette: AppPalette = paletteFor(true);
  /** 配色模式：AUTO（按日出日落，默认）/ LIGHT / DARK，见 core/ThemeMode.ets。 */
  @State themeMode: string = ThemeMode.AUTO;
  @State place: Place = Place.DEFAULT;
  @State placeName: string = '';
  @State district: string = '';
  @State districtFull: string = '';
  /** 「跟随 GPS」的意图（持久化，默认 true）与「定位不可用」未知态。 */
  @State gpsIntent: boolean = true;
  @State locationUnknown: boolean = false;
  private unknownTimer: number = -1;
  @State weatherTemperature: string = WeatherLogic.PLACEHOLDER;
  @State weatherText: string = '';
  @State weatherRange: string = '';
  /** 当前地点还没有缓存、正在取数：天气位显示「更新中…」而不是干等占位符。 */
  @State weatherPending: boolean = false;
  @State hourLabels: string[] = [];
  @State hourTemps: string[] = [];
  @State hourIcons: string[] = [];
  @State keyTimeText: string = '';
  @State keyTimeState: string = '';
  @State segments: string[] = [];
  @State temperatureKey: string = '';
  /** 关键时间的时段（分钟区间），与「当前是否落在时段内」分开存：后者要逐秒判定。 */
  @State keyBands: TakeBand[] = [];
  @State inKeyTime: boolean = false;
  @State shichenReminders: boolean = false;
  @State keyTimeChime: boolean = false;
  /** 位置地图：视口内的瓦片、底图来源说明、缩放级别与地图中心（底图坐标系）。 */
  @State mapTiles: MapTile[] = [];
  @State mapAttribution: string = '';
  @State mapZoom: number = DEFAULT_ZOOM;
  /** 实际应用的缩放（自动降级后可能小于请求值），以及「底图不可用」状态。 */
  @State mapAppliedZoom: number = DEFAULT_ZOOM;
  @State mapUnavailable: boolean = false;
  @State mapDegraded: boolean = false;
  /** 探测/首屏加载态：120ms 防闪，6 秒兜底收起。 */
  @State mapShowLoading: boolean = false;
  private mapLoadingTimer: number = -1;
  private mapLoadingFallbackTimer: number = -1;
  @State mapCenterLat: number = 0;
  @State mapCenterLon: number = 0;
  /** 设置页里选的底图标识（见 core/MapTiles 的 MAP_STYLE_OPTIONS）。 */
  @State mapStyleKey: string = 'auto';

  private timerId: number = -1;
  /** 上次前台取定位的时刻（毫秒），用于「每分钟一次」的节流。 */
  private lastGpsMillis: number = 0;
  private previousSolarSecond: number = -1;
  private previousShichenIndex: number = -1;
  private lastDerivedMillis: number = 0;
  /** 上次看到的天气／区划名版本号；一变就立刻重算，不用等 30 秒的节流。 */
  private weatherRevision: number = -1;
  private districtRevision: number = -1;
  private context: common.UIAbilityContext | null = null;
  private sunSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private sunCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.sunSettings);
  private sunCtxReady: boolean = false;
  /** 圆盘画布的实测尺寸（vp）：标签锚点靠它算，Canvas 也按它重绘。 */
  @State sunDialW: number = 0;
  @State sunDialH: number = 0;
  /** 地图视口尺寸（像素）与双指缩放前的级别。 */
  private mapWpx: number = 0;
  private mapHpx: number = 0;
  private mapBaseZoom: number = DEFAULT_ZOOM;

  aboutToAppear(): void {
    // 卡片自带字体：在这里（页面侧）注册才真正生效 —— 在 UIAbility 里注册实测不生效
    // （卡片仍用系统字面；见 harmony/docs/font-weight.md）。registerFont 是同步的，
    // 所以第一帧就用的自带字面，不会先按系统字体闪一帧。
    font.registerFont({ familyName: CARD_FONT_REGULAR, familySrc: $rawfile('font/card_sans_regular.ttf') });
    font.registerFont({ familyName: CARD_FONT_MEDIUM, familySrc: $rawfile('font/card_sans_medium.ttf') });
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppStore.init(this.context);
    MapTileService.setProbeListener((decision: ProbeDecision) => this.onProbeUpgrade(decision));
    this.reloadSettings();
    this.weatherRevision = WeatherService.revision();
    this.districtRevision = DistrictService.revision();
    this.refreshDerived();
    this.lastDerivedMillis = Date.now();
    this.tick();
    this.timerId = setInterval(() => {
      this.tick();
    }, 1000);
    this.refreshRemote();
    this.syncGpsSilently();
    KeepAwake.apply(this.context);
  }

  /** 从设置页返回后重新读取偏好（观测点、提醒开关都可能在那边改过）。 */
  onPageShow(): void {
    if (this.context === null) {
      return;
    }
    this.reloadSettings();
    // 回到前台 / 从设置页返回：立刻复核定位权限。意图为真但未授权时马上进入未知态，
    // 不依赖下一次定时器（否则「刚点跟随 GPS 却没权限」还会短暂显示旧地点）。
    this.syncGpsSilently();
    this.weatherRevision = WeatherService.revision();
    this.districtRevision = DistrictService.revision();
    this.lastDerivedMillis = Date.now();
    this.refreshDerived();
    this.refreshRemote();
    // 设置页里可能刚改过「屏幕常亮」。
    KeepAwake.apply(this.context);
  }

  private reloadSettings(): void {
    this.place = AppStore.place();
    this.gpsIntent = AppStore.gpsIntent();
    this.shichenReminders = AppStore.shichenReminders();
    this.keyTimeChime = AppStore.keyTimeChime();
    this.mapStyleKey = AppStore.mapStyle();
    this.themeMode = AppStore.themeMode();
    this.recenterMap();
  }

  /**
   * 跟随 GPS 时的前台定位节奏：应用打开期间每分钟静默取一次（不弹权限框）。
   * 意图为真但未授权 / 20 秒仍无 fix → 进入「定位不可用」未知态。
   */
  private syncGpsSilently(): void {
    if (!this.gpsIntent) {
      this.setLocationUnknown(false);
      return;
    }
    LocationService.hasPermission().then((granted: boolean) => {
      if (!granted) {
        // 未授权：意图仍在，直接进未知态（不用等 20 秒）。
        this.setLocationUnknown(true);
        return;
      }
      LocationService.current().then((point: GeoPoint | null) => {
        if (point === null) {
          this.startUnknownCountdown();
          return;
        }
        this.setLocationUnknown(false);
        if (this.unknownTimer >= 0) {
          clearTimeout(this.unknownTimer);
          this.unknownTimer = -1;
        }
        this.lastGpsMillis = Date.now();
        this.applyPlace(new Place(point.latitude, point.longitude, PlaceSource.GPS, '', ''));
      });
    });
  }

  /**
   * 切换「定位不可用」未知态：进入时把地图视口切到 z3 全球；退出时复位到当前观测点。
   * 只改状态不会重建地图 —— 必须在这里显式处理视口，否则会停在上一个地点。
   */
  private setLocationUnknown(value: boolean): void {
    if (this.locationUnknown === value) {
      return;
    }
    this.locationUnknown = value;
    // 立刻重算所有「与地点相关」的显示（逐时温度、天气、日期行、时段色带、主题），
    // 否则会继续显示上一个地点的真实温度 / 色带。
    this.refreshDerived();
    if (value) {
      this.mapCenterLat = 0;
      this.mapCenterLon = 0;
      this.mapZoom = UnknownLocationLogic.MAP_ZOOM;
      this.lastMapUi = new MapUiState();
      this.refreshMap(true);
    } else {
      this.recenterMap();
    }
  }

  /** 授权后 20 秒仍没有 fix → 未知态。 */
  private startUnknownCountdown(): void {
    if (this.unknownTimer >= 0) {
      clearTimeout(this.unknownTimer);
    }
    this.unknownTimer = setTimeout(() => {
      if (this.gpsIntent && this.place.source !== PlaceSource.GPS) {
        this.setLocationUnknown(true);
      }
    }, UnknownLocationLogic.FIX_TIMEOUT_MILLIS);
  }

  /** 距离上次前台取定位是否已经满一分钟。 */
  private gpsDue(): boolean {
    return Date.now() - this.lastGpsMillis >= GPS_INTERVAL_MILLIS;
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // ---- 数据 ----

  /**
   * 观测点**已知**的国家/地区码：预设城市自带，其次逆地理结果；都没有时为空串。
   *
   * 预设城市的国家码随城市一起内置，选中就能当场算出时区，不必等（也可能失败的）逆地理编码。
   */
  private countryCodeOfPlace(): string {
    return this.place.countryCode.length > 0
      ? this.place.countryCode
      : AppStore.district().countryCode;
  }

  /**
   * 观测点的标准时区偏移（秒）——「所在国的标准时间」，不是坐标所在的 tzdata 时区。
   *
   * 判定统一在 `core/CivicTime`：中国（含港澳台）与中国南极考察站恒 +8，其余按国家表 +
   * 多时区大国经度分段。界面上的 UTC 标签、标准时钟、日出日落与真太阳时基准都用这一个值。
   */
  private zoneOffsetSeconds(): number {
    if (this.locationUnknown) {
      // 未知态用**系统时区**；注意西半球偏移本身是负数，不能拿负数当「没传」。
      return UnknownLocationLogic.offsetSecondsOr(null, Date.now());
    }
    return CivicTimeLogic.standardOffsetSeconds(this.place.latitude, this.place.longitude,
      this.countryCodeOfPlace());
  }

  private tick(): void {
    const now: number = Date.now();
    const seconds: number = Math.floor(SolarTimeMath.trueSolarSecondsOfDay(now, this.place.longitude)) % 86400;
    const shichenIndex: number = Shichen.indexOf(seconds);
    this.checkChime(seconds, shichenIndex);
    this.previousSolarSecond = seconds;
    this.previousShichenIndex = shichenIndex;
    this.solarSecond = seconds;
    const zoneSeconds: number = this.zoneOffsetSeconds();
    this.standardSecond = ((Math.floor(SolarTimeMath.beijingSecondsOfDay(now) + zoneSeconds -
      SolarTimeMath.BEIJING_OFFSET_SECONDS) % 86400) + 86400) % 86400;
    // 太阳落山/升起的那一刻就换主题，不用等下次重算。
    const dayTheme: boolean = this.isDayTheme();
    if (dayTheme !== this.dayThemeCached) {
      this.dayThemeCached = dayTheme;
      this.palette = paletteFor(dayTheme);
    }
    // 关键时间的字色要按秒跟进（进入/离开时段的那一秒就变色），所以放在每秒的 tick 里算。
    this.inKeyTime = TakeTimeLogic.insideBands(this.keyBands, seconds);
    // 跟随 GPS 时前台每分钟取一次定位；桌面卡片侧是 5 分钟一次（CardService）。
    if (this.gpsIntent && this.gpsDue()) {
      this.lastGpsMillis = now;
      this.syncGpsSilently();
    }
    // 圆盘上的太阳点跟着真太阳时走，每秒重画一次。
    this.drawSunDial();
    // 天气／区划名刚一更新（例如刚在设置页换了城市）就立刻反映到界面上，不等 30 秒的节流。
    const weatherRevision: number = WeatherService.revision();
    const districtRevision: number = DistrictService.revision();
    if (weatherRevision !== this.weatherRevision || districtRevision !== this.districtRevision) {
      this.weatherRevision = weatherRevision;
      this.districtRevision = districtRevision;
      this.lastDerivedMillis = now;
      this.refreshDerived();
      return;
    }
    // 分钟级别的数据每 30 秒重算一次，别让每秒的刷新去碰网络与字符串拼接。
    if (now - this.lastDerivedMillis >= 30000) {
      this.lastDerivedMillis = now;
      this.refreshDerived();
    }
  }

  /** 应用在前台时由自己发声（与 Android 端一致：只响铃、不发通知）。 */
  private checkChime(solarSecond: number, shichenIndex: number): void {
    const context: common.UIAbilityContext | null = this.context;
    const previousIndex: number = this.previousShichenIndex;
    if (context === null) {
      return;
    }
    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
    if (this.keyTimeChime && schedule !== null) {
      for (const band of schedule.bands) {
        if (crossed(this.previousSolarSecond, solarSecond, band.startMinute * 60)) {
          ChimePlayer.play(context, 'chime500.wav');
          return;
        }
      }
    }
    if (this.shichenReminders && previousIndex >= 0 && shichenIndex !== previousIndex) {
      ChimePlayer.play(context, 'chime250.wav');
    }
  }

  /** 天气、关键时间、区划名这些「慢变量」。 */
  private refreshDerived(): void {
    const language: string = DistrictService.language();
    const now: number = Date.now();
    this.language = language;
    this.snapshot = SolarTimeSnapshot.compute(now, this.place.latitude, this.place.longitude, language,
      this.zoneOffsetSeconds(), this.countryCodeOfPlace());
    this.palette = paletteFor(this.isDayTheme());
    // 区划名只在「缓存坐标仍属于当前观测点（≤ 5 km）」时才算数：换了城市就立刻变空，
    // 新名字回来之前卡片退回预设城市名 / 减号，不会挂着上一个城市的区划名。
    const names: DistrictNames | null = DistrictService.cachedNamesFor(this.place);
    this.districtFull = names === null ? '' : names.full;
    this.district = names === null ? '' : names.short;
    this.placeName = this.presetName();

    // 未知态不读任何天气缓存：所有与地点相关的天气信息都用占位符。
    const weather: WeatherSnapshot | null = this.locationUnknown ? null : WeatherService.cached(this.place);
    if (this.locationUnknown) {
      const placeholderWeather = UnknownLocationLogic.weatherPlaceholders();
      this.weatherTemperature = placeholderWeather.temperature;
      this.weatherText = placeholderWeather.text;
    } else if (weather !== null) {
      this.weatherTemperature = `${weather.temperatureC}°`;
      this.weatherText = WeatherLogic.conditionLabel(weather.code, language);
    } else {
      this.weatherTemperature = WeatherLogic.PLACEHOLDER;
      this.weatherText = '';
    }
    // 缓存里的来源（主源 / 备用源）只影响逐时步长与诊断；首页页脚不再显示来源文字。
    // 日期与逐时格按**当地标准时**算（与左栏那个时钟同一口径），不是北京时间。
    const zoneSeconds: number = this.zoneOffsetSeconds();
    const date: Date = new Date(now + zoneSeconds * 1000);
    const dayStartUtc: number = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
    const range: number[] | null = this.locationUnknown ? null : WeatherLogic.temperatureRange(
      WeatherService.hourly(this.place),
      dayStartUtc,
      dayStartUtc + 86400000,
      zoneSeconds * 1000
    );
    this.weatherRange = this.locationUnknown ? UnknownLocationLogic.weatherPlaceholders().range
      : (range === null ? '' : `${range[0]}~${range[1]}°`);
    // 六格逐时预报：**槽位数恒为 6**，槽位之间的步长跟着数据源走
    // （主源 1 小时 → 现在/22时/23时/0时/1时/2时；备用源 3 小时 → 现在/23时/2时/5时/8时/11时）。
    // 图标下方显示**温度**（与 Android / iOS 一致）；「现在」格用实时温度，其余用采样点温度。
    const hourLabelList: string[] = [];
    const icons: string[] = [];
    const hourly: HourPoint[] = this.locationUnknown ? [] : WeatherService.hourly(this.place);
    const stepHours: number = this.locationUnknown ? 1 : WeatherService.stepHours();
    const slotList: WeatherSlot[] = WeatherLogic.visibleSlots(
      hourly,
      Math.floor(now / 1000),
      zoneSeconds,
      WeatherLogic.SLOT_COUNT,
      stepHours
    );
    const slotLabels: string[] = WeatherLogic.slotLabels(slotList, zoneSeconds, language);
    const currentCode: number = weather === null ? -1 : weather.code;
    const currentTemperature: number | null = weather === null ? null : weather.temperatureC;
    const temps: (number | null)[] = WeatherLogic.hourTemperatures(
      hourly,
      Math.floor(now / 1000),
      zoneSeconds,
      stepHours,
      currentTemperature
    );
    for (let index = 0; index < slotList.length; index++) {
      const slot: WeatherSlot = slotList[index];
      let point: HourPoint | null = null;
      for (const candidate of hourly) {
        if (candidate.epochSeconds === slot.epochSeconds) {
          point = candidate;
          break;
        }
      }
      let code: number = point === null ? -1 : point.code;
      if (slot.isNow && currentCode >= 0) {
        code = currentCode;
      }
      const localHour: number = WeatherLogic.localHourOf(slot.epochSeconds, zoneSeconds);
      hourLabelList.push(index < slotLabels.length ? slotLabels[index] : WeatherLogic.hourLabel(localHour, language));
      icons.push(code < 0 ? 'unknown' : WeatherLogic.iconKey(code, localHour >= 6 && localHour <= 17));
    }
    this.hourLabels = hourLabelList;
    this.hourTemps = temps.map((value: number | null): string => WeatherLogic.temperatureLabel(value));
    this.hourIcons = icons;
    if (this.locationUnknown) {
      // 未知态：逐时保留六格，首格「现在」+ 按系统时间逐小时（跨午夜回绕），温度 `-°`、不画图标。
      this.hourLabels = UnknownLocationLogic.hourlyLabels(Math.floor(now / 1000), zoneSeconds, language,
        WeatherLogic.SLOT_COUNT);
      this.hourTemps = UnknownLocationLogic.hourlyTemperatures(WeatherLogic.SLOT_COUNT);
      this.hourIcons = [];
      this.weatherTemperature = LocationPlaceholders.DASH;
      this.weatherText = '';
      this.weatherRange = '';
    }
    // 当前地点没有缓存、但正在取数：天气位显示「更新中…」，取完（成败都会落到这里）再改文案。
    this.weatherPending = !this.locationUnknown && weather === null && WeatherService.isRefreshing();

    // 未知态没有天气来源：关键时段（由天气温度算出）自然为空，不去读旧缓存。
    const schedule: TakeTimeSchedule | null = this.locationUnknown ? null : KeyTimeService.schedule();
    if (schedule === null || schedule.bands.length === 0) {
      this.keyTimeText = '';
      this.segments = [];
      this.keyBands = [];
      this.temperatureKey = '';
      this.inKeyTime = false;
      this.keyTimeState = KeyTimeService.remainingValidity() < 0 ? '尚未同步' : '数据已过期';
      return;
    }
    this.keyTimeText = schedule.bands
      .map((band: TakeBand): string => `${TimeFormat.clock(band.startMinute * 60)} – ${TimeFormat.clock(band.endMinute * 60)}`)
      .join('   ');
    this.keyBands = schedule.bands;
    this.temperatureKey = TakeTimeLogic.temperatureToKey(schedule.temperature);
    this.segments = TakeTimeLogic.axisSegments(schedule.bands).map((segment: AxisSegment): string =>
      `${segment.lengthMinutes},${segment.bandIndex}`);
    this.keyTimeState = this.temperatureKey === 'cold' ? '冻或温' : (this.temperatureKey === 'hot' ? '热或温' : '');
    this.inKeyTime = TakeTimeLogic.insideBands(this.keyBands, this.solarSecond);
  }

  private refreshRemote(): void {
    // 当前地点还没有缓存 → 立刻把天气位切成「更新中…」，别让用户盯着占位符猜。
    if (WeatherService.cached(this.place) === null) {
      this.weatherPending = true;
    }
    // 回到前台 / 换了地点：如果手里是低精度数据（7Timer! 3 小时），立刻尝试升级回 1 小时源，
    // **不等退避计时器**（60/120/300 秒）——这条 force 只用于「低精度」这一种情形。
    const force: boolean = WeatherService.shouldForceUpgrade();
    CardService.refresh(force).then(() => {
      this.refreshDerived();
    }).catch((error: BusinessError) => {
      console.warn(`refresh failed: ${error.code} ${error.message}`);
    });
  }

  private applyPlace(place: Place): void {
    this.place = place;
    AppStore.setPlace(place);
    if (place.source === PlaceSource.GPS) {
      AppStore.setGpsIntent(true);
      this.gpsIntent = true;
      this.setLocationUnknown(false);
    }
    this.refreshDerived();
    this.recenterMap();
    this.tick();
    this.refreshRemote();
    this.rescheduleReminders();
  }

  // ---- 位置地图 ----

  /** 当前设置下的底图图层（自动＝境内高德、境外 ESRI；境内/境外按国家码判）。 */
  private mapLayer(): MapLayer {
    const style: MapStyle = MapTilesLogic.styleFromKey(this.mapStyleKey);
    return MapTilesLogic.layerForStyle(style, this.place.latitude, this.place.longitude,
      this.countryCodeOfPlace());
  }

  /** 上一次真正画到界面上的底图快照：相同就完全不 setState（失败计数变化不会触发 UI 更新）。 */
  private lastMapUi: MapUiState = new MapUiState();

  /** 地图中心复位到观测点：换城市、跟随 GPS 更新坐标后都要复位。 */
  private recenterMap(): void {
    const layer: MapLayer = this.mapLayer();
    const point: number[] = MapTilesLogic.displayPoint(layer, this.place.latitude, this.place.longitude);
    this.applyViewport(point[0], point[1], this.mapZoom);
  }

  /**
   * 视口唯一入口：地点 / 缩放变化都只在这里应用，顺序固定
   * `setCenter → setZoom → 再 setCenter`，避免中心与缩放两处互相打断；缩放不挪中心。
   */
  private applyViewport(latitude: number, longitude: number, zoom: number): void {
    this.mapCenterLat = latitude;
    this.mapCenterLon = longitude;
    this.mapZoom = zoom;
    this.mapCenterLat = latitude;
    this.mapCenterLon = longitude;
    this.refreshMap(true);
  }

  /** 重算视口内的瓦片；中心、缩放、视口尺寸任一变化后调用（取数含空白检测与降级）。 */
  private refreshMap(viewportChanged: boolean = false): void {
    if (this.mapWpx <= 0 || this.mapHpx <= 0) {
      return;
    }
    this.startMapLoading();
    if (this.locationUnknown) {
      // 未知态：z3 全球底图，不画标记；有缓存零探测，否则并行探 2 块 z3。
      MapTileService.loadUnknown(this.mapWpx, this.mapHpx).then((result: MapLoadResult) => {
        this.stopMapLoading();
        this.mapTiles = result.tiles;
        this.mapAttribution = result.attribution;
        this.mapAppliedZoom = result.zoom;
        this.mapUnavailable = result.unavailable;
        this.mapDegraded = false;
      }).catch((error: BusinessError) => {
        this.stopMapLoading();
        console.warn(`unknown map failed: ${error.code} ${error.message}`);
      });
      return;
    }
    MapTileService.load(this.place, this.mapStyleKey, this.countryCodeOfPlace(), this.mapCenterLat,
      this.mapCenterLon, this.mapZoom, this.mapWpx, this.mapHpx, viewportChanged)
      .then((result: MapLoadResult) => {
        this.stopMapLoading();
        // 有效 plan 快照没变就什么都不做：失败/空白计数变化不触发 UI 更新，杜绝自激刷新。
        if (sameUiState(this.lastMapUi, result.uiState)) {
          return;
        }
        this.lastMapUi = result.uiState;
        this.mapTiles = result.tiles;
        this.mapAttribution = result.attribution;
        this.mapAppliedZoom = result.zoom;
        this.mapUnavailable = result.unavailable;
        this.mapDegraded = result.degraded;
      }).catch((error: BusinessError) => {
        this.stopMapLoading();
        console.warn(`map load failed: ${error.code} ${error.message}`);
      });
  }

  /** 加载态：120ms 后才显示（快请求不闪），6 秒兜底强制收起。 */
  private startMapLoading(): void {
    this.clearMapLoadingTimers();
    this.mapLoadingTimer = setTimeout(() => {
      this.mapShowLoading = true;
    }, 120);
    this.mapLoadingFallbackTimer = setTimeout(() => {
      this.mapShowLoading = false;
    }, 6000);
  }

  private stopMapLoading(): void {
    this.clearMapLoadingTimers();
    this.mapShowLoading = false;
  }

  private clearMapLoadingTimers(): void {
    if (this.mapLoadingTimer >= 0) {
      clearTimeout(this.mapLoadingTimer);
      this.mapLoadingTimer = -1;
    }
    if (this.mapLoadingFallbackTimer >= 0) {
      clearTimeout(this.mapLoadingFallbackTimer);
      this.mapLoadingFallbackTimer = -1;
    }
  }

  /** 渐进升级：保持视口中心不变，只换源 / 级别；用户已交互过就不再升级。 */
  private onProbeUpgrade(decision: ProbeDecision): void {
    if (this.locationUnknown) {
      return;
    }
    const result: MapLoadResult = MapTileService.upgradeResult(decision);
    if (sameUiState(this.lastMapUi, result.uiState)) {
      return;
    }
    this.lastMapUi = result.uiState;
    this.mapTiles = result.tiles;
    this.mapAttribution = result.attribution;
    this.mapAppliedZoom = result.zoom;
    this.mapUnavailable = result.unavailable;
    this.mapDegraded = false;
  }

  private zoomMapBy(delta: number): void {
    MapTileService.markMapInteraction();
    const next: number = MapTilesLogic.clampZoom(this.mapZoom + delta);
    if (next === this.mapZoom) {
      return;
    }
    this.applyViewport(this.mapCenterLat, this.mapCenterLon, next);
  }

  private rescheduleReminders(): void {
    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
    const bands: TakeBand[] = schedule === null ? [] : schedule.bands;
    ReminderService.reschedule(
      this.place,
      this.shichenReminders,
      this.keyTimeChime,
      bands,
      DistrictService.language()
    ).catch((error: BusinessError) => {
      console.warn(`reschedule failed: ${error.code} ${error.message}`);
    });
  }

  /** 日期 + 当日天气与温度区间，例如「11 月 12 日 · 星期四 · 6° 晴 · 2° ~ 12°」；没有天气时留占位符。 */
  /**
   * 日期/天气与经纬度同排时的取舍：空间不够就**隐藏右侧经纬度**，优先保住日期与天气。
   * 与安卓 `SmallRowLayout.shouldShowTrailing` 同一套规则。
   */
  private coordinatesFit(dateText: string, coordText: string): boolean {
    if (coordText.length === 0 || this.dateRowWidth <= 0) {
      return false;
    }
    const utils: MeasureUtils = this.getUIContext().getMeasureUtils();
    const size: number = this.cs(10);
    // 量宽必须指定卡片自带字族：默认字族会跟着系统「字体粗细」变宽，判断结果就会随设置漂。
    const dateWidth: number = utils.measureTextSize({
      textContent: dateText,
      fontSize: size + 'fp',
      fontFamily: CARD_FONT_REGULAR
    }).width as number;
    const coordWidth: number = utils.measureTextSize({
      textContent: coordText,
      fontSize: size + 'fp',
      fontFamily: CARD_FONT_REGULAR
    }).width as number;
    return dateWidth + coordWidth + vp2px(8) <= vp2px(this.dateRowWidth);
  }

  private dateTail(): string {
    const parts: string[] = [TimeFormat.dateCompact(Date.now(), this.language)];
    if (this.locationUnknown) {
      parts.push(LocationPlaceholders.DASH);
      return parts.join(' · ');
    }
    const hasWeather: boolean = this.weatherTemperature !== WeatherLogic.PLACEHOLDER && this.weatherText.length > 0;
    if (hasWeather) {
      parts.push(`${this.weatherTemperature} ${this.weatherText}`);
    }
    if (this.weatherRange.length > 0) {
      parts.push(this.weatherRange);
    }
    if (!hasWeather) {
      // 换到新城市时缓存属于旧地点（按 ≤5 km 判定为无效）：这里只留占位符，
      // 正在取数就写「更新中…」，绝不用上一个城市的读数顶替。
      parts.push(this.weatherPending ? '更新中…' : WeatherLogic.PLACEHOLDER);
    }
    return parts.join(' · ');
  }

  /**
   * 标题行右侧是否显示「GPS」徽标：只有跟随 GPS 才显示（与 Android `HeaderBadge` 一致）。
   *
   * 预设城市 / 手动输入的经纬度一律不显示 —— 地名已经在大卡片里，标题行不占位。
   */
  private showsGpsBadge(): boolean {
    return !this.locationUnknown && PlaceBadgeLogic.showsGps(this.place.source);
  }

  /**
   * 地名，三段式（与 Android `MainScreen.cityText` 一致）：
   *
   * ① 反查到的行政区划名优先（缓存坐标超过 5 km 就算没有，见 DistrictService.cachedNamesFor）；
   * ② 反查还没回来 / 失败时，只有**预设城市**才回退到城市名（如「纽约」）；
   * ③ 手工坐标与 GPS 定位没有名字可用，显示半角减号，等反查结果到了再换成区划名。
   */
  private districtLabel(): string {
    if (this.locationUnknown) {
      return LocationPlaceholders.UNKNOWN_PLACE;
    }
    if (this.districtFull.length > 0) {
      return this.districtFull;
    }
    if (this.district.length > 0) {
      return this.district;
    }
    return this.placeName.length > 0 ? this.placeName : CITY_UNKNOWN;
  }

  /** 真太阳时（未知态显示 `--:--:--`，宽度与真实时间接近，不跳版）。 */
  private trueSolarText(): string {
    return this.locationUnknown ? LocationPlaceholders.TIME : TimeFormat.clock(this.solarSecond);
  }

  /** 时辰 / 高度角 / 白昼等短字段：未知态一律 `--`。 */
  private shortText(value: string): string {
    return this.locationUnknown ? LocationPlaceholders.SHORT : value;
  }

  /** 顶部信息行的退化档位：先缩字号，再按档 0→1→2→3 退化。 */
  private districtTier(): number {
    const base: number = this.cs(12);
    // 左右两半按时间栏的实测宽度算（竖线与两半结构下的真实可用宽度）。
    const halfWidth: number = this.clockColumnWidth > 0 ? this.clockColumnWidth : this.cs(150);
    const utcWidth: number = TimeFormat.utcOffsetLabel(this.snapshot.localOffsetSeconds).length * base;
    const placeWidth: number = this.districtLabel().length * this.cs(this.districtFontSize());
    const labelWidth: number = 4 * base;
    const shichenWidth: number = this.shortText(this.snapshot.shichenName).length * base;
    return DistrictLayoutTier.ofNameLength(utcWidth, placeWidth, labelWidth, shichenWidth, halfWidth,
      this.districtLabel().length);
  }

  /**
   * 大卡片左栏「地区」的字号：名字太长时按这一栏的可用宽度逐档缩小（12 → 9fp，0.5 一档），
   * 避免「New York, Manhattan」这种长名字被直接截成「New …」。缩到下限仍放不下才交给省略号
   * （与 Android 卡片档 3 的兜底一致）。短名字仍是 12fp，字号不变。
   */
  private districtFontSize(): number {
    const base: number = 12;
    const min: number = 9;
    const name: string = this.districtLabel();
    const key: string = `${name}|${this.clockColumnWidth}|${this.language}|${this.isWideLayout() ? 1 : 0}`;
    if (key === this.districtFontKey && this.districtFontFit > 0) {
      return this.districtFontFit;
    }
    let fitted: number = base;
    if (this.clockColumnWidth > 0 && name.length > 0) {
      const utils: MeasureUtils = this.getUIContext().getMeasureUtils();
      // 量宽必须指定卡片自带字族：默认字族会跟着系统「字体粗细」变宽，判档就会随设置漂。
      const utcWidth: number = utils.measureTextSize({
        textContent: TimeFormat.utcOffsetLabel(this.snapshot.localOffsetSeconds),
        fontSize: this.cs(base) + 'fp',
        fontFamily: CARD_FONT_REGULAR
      }).width as number;
      // 8vp 是地区与 UTC 之间的间隔，再留 2vp 余量，免得刚好贴边被省略。
      const available: number = vp2px(this.clockColumnWidth) - utcWidth - vp2px(10);
      if (available > 0) {
        fitted = min;
        for (let size: number = base; size >= min; size -= 0.5) {
          const width: number = utils.measureTextSize({
            textContent: name,
            fontSize: this.cs(size) + 'fp',
            fontFamily: CARD_FONT_REGULAR
          }).width as number;
          if (width <= available) {
            fitted = size;
            break;
          }
        }
      }
    }
    this.districtFontKey = key;
    this.districtFontFit = fitted;
    return fitted;
  }

  /**
   * 预设城市名：只有「常用城市」点选的坐标才有名字可用，手工坐标 / GPS 一律返回空串。
   * 内置城市自带 label；境外城市按坐标查离线城市表（随界面语言变化）。
   */
  private presetName(): string {
    const preset: Place | null = Place.presetOf(this.place);
    if (preset === null) {
      return '';
    }
    if (preset.label.length > 0) {
      return preset.label;
    }
    const city: NearbyCity | null = CityIndex.nearest(preset.latitude, preset.longitude, DistrictService.language());
    return city === null ? '' : city.name;
  }

  /** 轻提示；UIContext 的 PromptAction 可能抛异常，这里统一兜住。 */
  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.warn(`toast failed: ${message}`);
    }
  }

  /**
   * 是否按「白天（亮色）」绘制。
   *
   * 由设置里的**主题三态**决定：自动＝看太阳是否在地平线之上（旧行为），
   * 亮色/暗色＝强制，忽略日出日落。太阳弧上的圆点位置仍按真实太阳高度角算，不受这里影响。
   */
  private isDayTheme(): boolean {
    if (this.locationUnknown) {
      // 未知态没有日出日落：按系统时区的钟点判白天（6 ≤ 小时 < 18），否则会恒进夜间。
      return ThemeMode.isLight(this.themeMode, UnknownLocationLogic.isDaytimeAt(Date.now(),
        UnknownLocationLogic.systemOffsetSeconds(Date.now())));
    }
    return ThemeMode.isLight(this.themeMode, this.snapshot.isDay());
  }

  /** 真太阳时在白天用白字（橙色底上金色看不清），夜里用金色。 */
  /** 真太阳时在白天用淡金（橙底上纯白太冷、金色又偏糊），夜里用金色。 */
  private solarAccent(): string {
    return this.isDayTheme() ? DAY_ACCENT : HERO_COLOR;
  }

  /** 逐时预报的小字：白天橙色底上要更白一些，夜里沿用弱化色。 */
  private hourlyTextColor(): string {
    return this.isDayTheme() ? '#E6FFFFFF' : this.palette.subtle;
  }

  /** 关键时段在时间轴上的色段与当前时刻圆点的颜色。 */
  private bandColor(): string {
    const day: boolean = this.isDayTheme();
    if (this.temperatureKey === 'cold') {
      return day ? COLD_BAND_ON_DAY_COLOR : COLD_COLOR;
    }
    if (this.temperatureKey === 'hot') {
      return day ? HOT_BAND_ON_DAY_COLOR : HOT_COLOR;
    }
    return this.solarAccent();
  }

  /** 关键时段里真太阳时数字的颜色。 */
  private inkColor(): string {
    const day: boolean = this.isDayTheme();
    if (this.temperatureKey === 'cold') {
      return day ? COLD_INK_ON_DAY_COLOR : COLD_INK_ON_NIGHT_COLOR;
    }
    if (this.temperatureKey === 'hot') {
      return day ? HOT_INK_ON_DAY_COLOR : HOT_INK_ON_NIGHT_COLOR;
    }
    return this.solarAccent();
  }

  /**
   * 真太阳时的字色：落在关键时间段里时跟随时段的冷暖配色，其余时间按昼夜取白／金
   * —— 与 Android 卡片的 `activeKeyColor` 一致。
   */
  private solarColor(): string {
    return this.inKeyTime ? this.inkColor() : this.solarAccent();
  }

  /** 时间轴上代表当前时刻的圆点：跟着真太阳时一起变色（时段外仍是白色）。 */
  private dotColor(): string {
    return this.inKeyTime ? this.bandColor() : '#FFFFFF';
  }

  // ---- 视图 ----

  @Styles
  cardStyle() {
    .width('100%')
    .borderRadius(18)
    .padding(16)
  }

  @Builder
  header() {
    Row() {
      Column() {
        Text('真太阳时时钟')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
        Text('以太阳经过当地子午线的时刻为正午')
          .fontSize(12)
          .fontColor(this.palette.subtle)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      // 标题列吃剩余宽度；右边的「GPS」徽标只在跟随 GPS 时才条件渲染 ——
      // 预设城市 / 手动坐标不显示任何位置标识，也不留占位空隙，标题自然变宽。
      // （规则见 core/PlaceBadge，与 Android HeaderBadge 一致。）
      .layoutWeight(1)
      if (this.showsGpsBadge()) {
        Text(PlaceBadgeLogic.GPS_TEXT)
          .fontSize(12)
          .fontColor(this.palette.accent)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .constraintSize({ maxWidth: '40%' })
          .margin({ right: 6 })
      }
      // 与 Android 一致：齿轮图标按钮，不再用「设置」文字
      SymbolGlyph($r('sys.symbol.gearshape_fill'))
        .fontSize(22)
        .fontColor([this.palette.text])
        .padding(6)
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' }).catch((error: BusinessError) => {
            console.warn(`open settings failed: ${error.code} ${error.message}`);
          });
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /**
   * 档 1/2/3 的整行标签：档 1 = 时区 + 地点居中 + 时辰；档 2/3 = 地点贴左 + 时辰。
   * 这一行在大数字上方，竖线只出现在两个大数字之间，不会上延。
   */
  @Builder
  headerSingleRow() {
    Row() {
      if (this.districtTier() === DistrictLayoutTier.HIDE_LABEL) {
        Text(TimeFormat.utcOffsetLabel(this.snapshot.localOffsetSeconds))
          .fontSize(this.cs(12))
          .fontFamily(this.cardFont(FontWeight.Normal))
          .lineHeight(this.cardLineHeight(this.cs(12)))
          .fontColor('#CCFFFFFF')
          .margin({ right: 8 })
      }
      Text(this.districtLabel())
        .fontSize(this.cs(this.districtFontSize()))
        .fontFamily(this.cardFont(FontWeight.Normal))
        .lineHeight(this.cardLineHeight(this.cs(this.districtFontSize())))
        .fontColor('#B3FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.districtTier() === DistrictLayoutTier.HIDE_LABEL
          ? TextAlign.Center : TextAlign.Start)
        .layoutWeight(1)
      Text(this.shortText(this.snapshot.shichenName))
        .fontSize(this.cs(12))
        .fontFamily(this.cardFont(FontWeight.Normal))
        .lineHeight(this.cardLineHeight(this.cs(12)))
        .fontColor('#B3FFFFFF')
        .maxLines(1)
        .margin({ left: 8 })
    }
    .width('100%')
    .height(this.cs(18))
    .margin({ bottom: 4 })
  }

  /** 首页大卡片：与桌面卡片同款版面，但页面里可以逐秒刷新，所以右栏真太阳时是活的。 */
  @Builder
  heroCard() {
    Column() {
      // 档 1/2/3：整行单列布局（时区/地点/时辰），竖线不会上延到标签行。
      if (this.districtTier() !== DistrictLayoutTier.FULL) {
        this.headerSingleRow()
      }
      Row() {
        // 左：标准时间。档 0 时标签行与数字同栏（左右两半 + 竖线上延）。
        Column() {
          if (this.districtTier() === DistrictLayoutTier.FULL) {
            Row() {
            if (this.districtTier() < DistrictLayoutTier.HIDE_UTC) {
              Text(TimeFormat.utcOffsetLabel(this.snapshot.localOffsetSeconds))
                .fontSize(this.cs(12))
                .fontFamily(this.cardFont(FontWeight.Normal))
                .lineHeight(this.cardLineHeight(this.cs(12)))
                .fontColor('#CCFFFFFF')
            }
            Text(this.districtLabel())
              .fontSize(this.cs(this.districtFontSize()))
              .fontFamily(this.cardFont(FontWeight.Normal))
              .lineHeight(this.cardLineHeight(this.cs(this.districtFontSize())))
              .fontColor('#B3FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(this.districtTier() === DistrictLayoutTier.FULL ? TextAlign.End
                : (this.districtTier() === DistrictLayoutTier.HIDE_LABEL ? TextAlign.Center : TextAlign.Start))
              .layoutWeight(1)
              .margin({ left: this.districtTier() < DistrictLayoutTier.HIDE_UTC ? 8 : 0,
                right: this.districtTier() === DistrictLayoutTier.FULL ? 6 : 0 })
              .onClick(() => {
                // 未知态：「定位不可用」可点，跳到系统应用详情/权限设置。
                if (this.locationUnknown && this.context !== null) {
                  LocationService.openAppSettings(this.context).catch((error: BusinessError) => {
                    console.warn(`open settings failed: ${error.code} ${error.message}`);
                  });
                }
              })
          }
          .width('100%')
          .height(this.cs(18))
          .margin({ bottom: 4 })
          }
          Row() {
            Text(TimeFormat.clock(this.standardSecond))
              .fontSize(this.clockMainSize())
              .fontFamily(this.cardFont(FontWeight.Medium))
              .lineHeight(this.cardLineHeight(this.clockMainSize()))
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
            Text(':')
              .fontSize(this.clockSecondSize())
              .fontFamily(this.cardFont(FontWeight.Medium))
              .lineHeight(this.cardLineHeight(this.clockSecondSize()))
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .margin({ bottom: this.clockSecondLift() })
            Text(pad2(this.standardSecond % 60))
              .fontSize(this.clockSecondSize())
              .fontFamily(this.cardFont(FontWeight.Medium))
              .lineHeight(this.cardLineHeight(this.clockSecondSize()))
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .margin({ bottom: this.clockSecondLift(), left: 1 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            // 记下这一栏的实测宽度：时间字号的唯一依据（左右两栏等宽，量左边即可）。
            const width: number = Number(newValue.width);
            if (Math.abs(width - this.clockColumnWidth) > 1) {
              this.clockColumnWidth = width;
            }
          })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column()
          .width(1)
          // 档 0：竖线从标签行顶端一直延伸到大数字底部；其余档位只在大数字之间。
          .height(this.cs(this.districtTier() === DistrictLayoutTier.FULL ? 76 : 58))
          .backgroundColor('#33FFFFFF')
          .margin({ left: 12, right: 12, top: 0 })

        // 右：真太阳时（逐秒刷新）
        Column() {
          if (this.districtTier() === DistrictLayoutTier.FULL) {
            Row() {
              Text('真太阳时')
                .fontSize(this.cs(12))
                .fontFamily(this.cardFont(FontWeight.Normal))
                .lineHeight(this.cardLineHeight(this.cs(12)))
                .fontColor('#CCFFFFFF')
              Text(this.shortText(this.snapshot.shichenName))
                .fontSize(this.cs(12))
                .fontFamily(this.cardFont(FontWeight.Normal))
                .lineHeight(this.cardLineHeight(this.cs(12)))
                .fontColor('#B3FFFFFF')
                .maxLines(1)
                .textAlign(TextAlign.End)
                .layoutWeight(1)
            }
            .width('100%')
            .height(this.cs(18))
            .margin({ bottom: 4 })
          }
          Row() {
            if (this.locationUnknown) {
              Text(LocationPlaceholders.TIME)
                .fontSize(this.clockMainSize())
                .fontFamily(this.cardFont(FontWeight.Medium))
                .lineHeight(this.cardLineHeight(this.clockMainSize()))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.solarColor())
                .letterSpacing(1)
                .opacity(0.6)
                .maxLines(1)
            } else {
              Text(this.trueSolarText())
                .fontSize(this.clockMainSize())
                .fontFamily(this.cardFont(FontWeight.Medium))
                .lineHeight(this.cardLineHeight(this.clockMainSize()))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.solarColor())
                .maxLines(1)
              Text(':')
                .fontSize(this.clockSecondSize())
                .fontFamily(this.cardFont(FontWeight.Medium))
                .lineHeight(this.cardLineHeight(this.clockSecondSize()))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.solarColor())
                .maxLines(1)
                .margin({ bottom: this.clockSecondLift() })
              Text(pad2(this.solarSecond % 60))
                .fontSize(this.clockSecondSize())
                .fontFamily(this.cardFont(FontWeight.Medium))
                .lineHeight(this.cardLineHeight(this.clockSecondSize()))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.solarColor())
                .maxLines(1)
                .margin({ bottom: this.clockSecondLift(), left: 1 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 日期/天气与经纬度同处一行：左侧日期行占满剩余宽度，右侧经纬度贴右
      Row() {
        Text(this.dateTail())
          .fontSize(this.cs(10))
          .fontFamily(this.cardFont(FontWeight.Normal))
          .lineHeight(this.cardLineHeight(this.cs(10)))
          .fontColor('#B3FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.coordinatesFit(this.dateTail(),
          TimeFormat.coordinates(this.place.latitude, this.place.longitude, this.locationUnknown))) {
          Text(this.shortText(TimeFormat.coordinates(this.place.latitude, this.place.longitude,
            this.locationUnknown)))
            .fontSize(this.cs(10))
            .fontFamily(this.cardFont(FontWeight.Normal))
            .lineHeight(this.cardLineHeight(this.cs(10)))
            .fontColor('#B3FFFFFF')
            .maxLines(1)
            .textAlign(TextAlign.End)
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .margin({ top: 6 })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const width: number = Number(newValue.width);
        if (Math.abs(width - this.dateRowWidth) > 1) {
          this.dateRowWidth = width;
        }
      })

      // 0–24 时时间轴：与桌面卡片、Android WidgetAxis 同款（1vp 细线 + 柔化圆点）
      Stack() {
        Row() {
          ForEach(this.segments, (item: string) => {
            if (isBandSegment(item)) {
              Row()
                .height(1)
                .backgroundColor(this.bandColor())
                .layoutWeight(segmentLength(item))
            } else {
              Row()
                .height(1)
                .layoutWeight(segmentLength(item))
            }
          }, (item: string, index: number) => `${index}-${item}`)
        }
        .width('100%')
        .height(1)
        .backgroundColor('#40FFFFFF')

        Row() {
          Row().layoutWeight(this.solarSecond > 0 ? this.solarSecond / 60 : 0.1)
          // 未知态：只隐藏「现在」圆点。**时间轴的色段必须保留** —— 关键时段标记与地点无关，
          // 这是用户明确选定的方案（A），以后不要顺手把色段也一起隐藏。
          if (!this.locationUnknown) {
            Column()
              .width(this.cs(11))
              .height(this.cs(11))
              .borderRadius(this.cs(5.5))
              // 时间轴「现在」圆点（原样，不要再改）：半径 5.5vp，色标 0 / 0.45 / 1，alpha 1 / 0.45 / 0。
              .radialGradient({
                center: ['50%', '50%'],
                radius: SunDialColors.DOT_RADIUS,
                colors: [
                  [SunDialColors.dotGradientColors(this.dotColor())[0], SunDialColors.DOT_STOPS[0]],
                  [SunDialColors.dotGradientColors(this.dotColor())[1], SunDialColors.DOT_STOPS[1]],
                  [SunDialColors.dotGradientColors(this.dotColor())[2], SunDialColors.DOT_STOPS[2]]
                ]
              })
          }
          Row().layoutWeight(this.solarSecond < 86400 ? (86400 - this.solarSecond) / 60 : 0.1)
        }
        .width('100%')
        .height(this.cs(11))
      }
      .width('100%')
      .height(this.cs(11))
      .margin({ top: 10 })

      // 六格逐时预报
      Row() {
        ForEach(this.hourLabels, (label: string, index: number) => {
          Column() {
            Text(label)
              .fontSize(this.cs(10))
              .fontFamily(this.cardFont(FontWeight.Normal))
              .lineHeight(this.cardLineHeight(this.cs(10)))
              .fontColor(this.hourlyTextColor())
              .maxLines(1)
            if (this.locationUnknown) {
              // 同尺寸占位，保住行高。
              Row()
                .width(this.cs(22))
                .height(this.cs(22))
                .margin({ top: 3 })
            } else {
              Image(weatherIcon(index < this.hourIcons.length ? this.hourIcons[index] : 'unknown'))
                .width(this.cs(22))
                .height(this.cs(22))
                .objectFit(ImageFit.Contain)
                .margin({ top: 3 })
            }
            Text(index < this.hourTemps.length ? this.hourTemps[index] : '')
              .fontSize(this.cs(10))
              .fontFamily(this.cardFont(FontWeight.Normal))
              .lineHeight(this.cardLineHeight(this.cs(10)))
              .fontColor(this.hourlyTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 1 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }, (label: string, index: number) => `${index}-${label}`)
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(this.cs(16))
    .borderRadius(18)
    .alignItems(HorizontalAlign.Start)
    .linearGradient({
      angle: 315,
      colors: this.isDayTheme()
        ? [[DAY_TOP_COLOR, 0], [DAY_BOTTOM_COLOR, 1]]
        : [[NIGHT_TOP_COLOR, 0], [NIGHT_BOTTOM_COLOR, 1]]
    })
    // 宽屏并排时与右侧太阳卡片取同一个最小高度，底边才能对齐（窄屏传 0，等于不约束）
    .constraintSize({ minHeight: this.wideCardMinHeight() })
  }

  /**
   * 太阳卡（v2 版式，对齐 Android 的 SunCard / SunDial）：
   * 标题行 + 满宽定高 194vp 的圆盘 + 画布下方居中的白昼行；
   * 圆盘上只画弧线/地平线/刻度/太阳点，日出·上中天·日落是**真正的 Text** 叠在画布上，
   * 多语言不会被 Canvas 截断。右栏四行已删除，卡片高度 ≈282vp。
   */
  @Builder
  sunCard() {
    Column() {
      Row() {
        Text('太阳位置 · 当地时间')
          .fontSize(this.cs(14))
          .fontFamily(this.cardFont(FontWeight.Medium))
          .lineHeight(this.cardLineHeight(this.cs(14)))
          .fontColor(this.palette.subtle)
          .layoutWeight(1)
        Text(this.shortText(`高度角 ${this.snapshot.altitudeDegrees.toFixed(1)}°`))
          .fontSize(this.cs(12))
          .fontFamily(this.cardFont(FontWeight.Medium))
          .lineHeight(this.cardLineHeight(this.cs(12)))
          .fontColor(this.palette.accent)
      }
      .width('100%')

      Stack() {
        Canvas(this.sunCtx)
          .width('100%')
          .height(this.cs(SUN_DIAL_HEIGHT))
          .onReady(() => {
            this.sunCtxReady = true;
            this.drawSunDial();
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const width: number = Number(newValue.width);
            const height: number = Number(newValue.height);
            if (Math.abs(width - this.sunDialW) > 0.5 || Math.abs(height - this.sunDialH) > 0.5) {
              this.sunDialW = width;
              this.sunDialH = height;
              this.drawSunDial();
            }
          })
        // 标签层：等画布量到尺寸再摆；坐标全部来自 core/SunPath 的纯几何。
        this.sunDialLabelLayer()
      }
      .width('100%')
      .height(this.cs(SUN_DIAL_HEIGHT))
      .margin({ top: this.cs(8) })

      Text(this.shortText(`白昼 ${this.daylightLine()}`))
        .fontSize(this.cs(12))
        .fontFamily(this.cardFont(FontWeight.Normal))
        .lineHeight(this.cardLineHeight(this.cs(12)))
        .fontColor(this.palette.subtle)
        .textAlign(TextAlign.Center)
        .margin({ top: this.cs(4) })
        .width('100%')
    }
    .width('100%')
    .borderRadius(18)
    .padding(this.cs(20))
    .backgroundColor(this.palette.card)
    // 圆盘定高后卡片自然高度 ≈282vp；宽屏并排时两卡取同一个最小高度，底边对齐。
    .constraintSize({ minHeight: this.cs(SUN_CARD_HEIGHT) })
  }

  /**
   * 圆盘上的文字标签层：日出、日落、上中天（居中）、极昼／极夜（圆心）。
   *
   * 锚点由 `SunPathGeometry.labelAnchors` 算出，用 `position` + `markAnchor` 定位：
   * 北半球日出在左（右对齐）、日落在右（左对齐）；南半球镜像后日出在右（左对齐）、
   * 日落在左（右对齐）—— 对齐方式跟着换边，标签始终落在圆外。上中天是水平中心+底边、
   * 极昼极夜是文字中心，南北半球不变。
   */
  @Builder
  sunDialLabelLayer() {
    // 未知态：不画日出/日落/上中天标签。
    if (!this.locationUnknown && this.sunDialW > 0 && this.sunDialH > 0) {
      if (this.snapshot.polar === PolarState.NORMAL) {
        Text(DialLabels.sunrise(this.language, TimeFormat.clock(this.snapshot.sunriseLocalSeconds)))
          .fontSize(this.cs(11))
          .fontFamily(this.cardFont(FontWeight.Medium))
          .lineHeight(this.cardLineHeight(this.cs(11)))
          .fontColor(this.palette.text)
          .maxLines(1)
          .position({ x: this.sunAnchors().sunriseX, y: this.sunAnchors().sunriseY })
          .markAnchor({ x: this.isSouthernHemisphere() ? 0 : '100%', y: '50%' })
        Text(DialLabels.sunset(this.language, TimeFormat.clock(this.snapshot.sunsetLocalSeconds)))
          .fontSize(this.cs(11))
          .fontFamily(this.cardFont(FontWeight.Medium))
          .lineHeight(this.cardLineHeight(this.cs(11)))
          .fontColor(this.palette.text)
          .maxLines(1)
          .position({ x: this.sunAnchors().sunsetX, y: this.sunAnchors().sunsetY })
          .markAnchor({ x: this.isSouthernHemisphere() ? '100%' : 0, y: '50%' })
      } else {
        Text(DialLabels.polar(this.snapshot.polar === PolarState.MIDNIGHT_SUN, this.language))
          .fontSize(this.cs(11))
          .fontFamily(this.cardFont(FontWeight.Medium))
          .lineHeight(this.cardLineHeight(this.cs(11)))
          .fontColor(this.palette.accent)
          .maxLines(1)
          .position({ x: this.sunAnchors().polarX, y: this.sunAnchors().polarY })
          .markAnchor({ x: '50%', y: '50%' })
      }
      // 极夜没有上中天（太阳整日不升），极昼保留。
      if (this.snapshot.polar !== PolarState.POLAR_NIGHT) {
        Text(DialLabels.noon(this.language, TimeFormat.clock(this.snapshot.solarNoonLocalSeconds)))
          .fontSize(this.cs(11))
          .fontFamily(this.cardFont(FontWeight.Medium))
          .lineHeight(this.cardLineHeight(this.cs(11)))
          .fontColor(this.palette.text)
          .maxLines(1)
          .position({ x: this.sunAnchors().noonX, y: this.sunAnchors().noonY })
          .markAnchor({ x: '50%', y: '100%' })
      }
    }
  }

  /**
   * 位置地图：与 Android 的 MapCard 同款——标题 + 坐标、190 高的地图、底图来源。
   * 境内用高德栅格瓦片（中文路网），境外自动用 Esri 街道图（兜底 OSM、高德）；标点固定在地图中心，
   * 支持双指缩放与双击放大（页面本身可上下滚动，所以不做拖动平移）。
   */
  @Builder
  mapCard() {
    Column() {
      Row() {
        Text('位置地图')
          .fontSize(13)
          .fontFamily(this.cardFont(FontWeight.Normal))
          .lineHeight(this.cardLineHeight(13))
          .fontColor(this.palette.subtle)
          .layoutWeight(1)
        Text(TimeFormat.coordinates(this.place.latitude, this.place.longitude, this.locationUnknown))
          .fontSize(11)
          .fontFamily(this.cardFont(FontWeight.Normal))
          .lineHeight(this.cardLineHeight(11))
          .fontColor(this.palette.subtle)
      }
      .width('100%')

      Stack({ alignContent: Alignment.Center }) {
        ForEach(this.mapTiles, (tile: MapTile) => {
          Image(tile.url)
            .width(px2vp(TILE_PX))
            .height(px2vp(TILE_PX))
            .objectFit(ImageFit.Fill)
            .draggable(false)
            .position({ x: px2vp(tile.leftPx), y: px2vp(tile.topPx) })
        // key 必须带上位置：只按 URL 的话，视口尺寸/中心变化后同一个瓦片的节点会被复用，
        // `.position()` 不会更新，旧瓦片留在旧偏移上 —— 表现为地图中间出现一条空白带。
      }, (tile: MapTile) => `${tile.url}|${Math.round(tile.leftPx)}|${Math.round(tile.topPx)}`)
        // z3 全球底图也没有内容：明确写出来，不留一块纯空白。
        if (this.mapShowLoading) {
          Column() {
            Text('正在载入底图…')
              .fontSize(11)
              .fontFamily(this.cardFont(FontWeight.Normal))
              .lineHeight(this.cardLineHeight(11))
              .fontColor(this.palette.subtle)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.palette.chip)
        }
        if (this.mapUnavailable) {
          Text('底图不可用')
            .fontSize(12)
            .fontFamily(this.cardFont(FontWeight.Normal))
            .lineHeight(this.cardLineHeight(12))
            .fontColor(this.palette.subtle)
        }
        // 标点：始终落在视口正中，对应上面的坐标；未知态不画标记。
        if (!this.locationUnknown) {
          Column()
            .width(16)
            .height(16)
            .borderRadius(8)
            .backgroundColor('#FFFFFF')
            .border({ width: 4, color: this.palette.accent })
            .shadow({ radius: 8, color: '#A6000000' })
        }
      }
      .width('100%')
      .aspectRatio(this.mapAspectRatio())
      .clip(true)
      .borderRadius(12)
      .backgroundColor(this.palette.chip)
      .margin({ top: 8 })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.mapWpx = vp2px(Number(newValue.width));
        this.mapHpx = vp2px(Number(newValue.height));
        this.refreshMap(true);
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.mapBaseZoom = this.mapZoom;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (event.scale > 0) {
                const next: number = MapTilesLogic.clampZoom(this.mapBaseZoom + Math.log2(event.scale));
                if (next !== this.mapZoom) {
                  // 用户手动缩放：冻结后续探测升级。
                  MapTileService.markMapInteraction();
                  this.applyViewport(this.mapCenterLat, this.mapCenterLon, next);
                }
              }
            }),
          TapGesture({ count: 2 })
            .onAction(() => {
              this.zoomMapBy(1);
            })
        )
      )

      Text(`${this.mapAttribution} · ${this.mapAppliedZoom} 级${this.mapDegraded ? '（已降级）' : ''} · 双指缩放`)
        .fontSize(10)
        .fontFamily(this.cardFont(FontWeight.Normal))
        .lineHeight(this.cardLineHeight(10))
        .fontColor(this.palette.subtle)
        .margin({ top: 6 })
        .width('100%')
    }
    .cardStyle()
    .backgroundColor(this.palette.card)
  }

  /** 白昼读数：极昼按整天算、极夜按 0，其余用日出日落算出来的秒数。 */
  private daylightLine(): string {
    if (this.snapshot.polar === PolarState.MIDNIGHT_SUN) {
      return TimeFormat.duration(DAY_SECONDS, this.language);
    }
    if (this.snapshot.polar === PolarState.POLAR_NIGHT) {
      return TimeFormat.duration(0, this.language);
    }
    return this.snapshot.daylightSeconds >= 0
      ? TimeFormat.duration(this.snapshot.daylightSeconds, this.language)
      : '--';
  }

  /** 是否南半球：决定圆盘 x 轴是否镜像（日出在右、日落在左）。 */
  private isSouthernHemisphere(): boolean {
    return this.place.latitude < 0;
  }

  /** 圆盘几何的入口：画布尺寸 + 日出/日落/当前真太阳时（小时数）。 */
  private sunDialPath(): SunPath {
    const width: number = this.sunDialW > 0 ? this.sunDialW : this.cs(294);
    const height: number = this.sunDialH > 0 ? this.sunDialH : this.cs(SUN_DIAL_HEIGHT);
    return SunPathGeometry.compute(width, height, this.sunriseDialHour(), this.sunsetDialHour(),
      this.snapshot.trueSolarSeconds / SECONDS_PER_HOUR,
      this.snapshot.polar === PolarState.MIDNIGHT_SUN,
      this.snapshot.polar === PolarState.POLAR_NIGHT,
      // 南半球观察者面朝北，东在右、西在左：圆盘 x 轴镜像（日出在右、日落在左）。
      this.isSouthernHemisphere());
  }

  /** 三个时间标签 + 极昼极夜文案的锚点。 */
  private sunAnchors(): SunLabelAnchors {
    const texts: string[] = [
      DialLabels.sunrise(this.language, TimeFormat.clock(this.snapshot.sunriseLocalSeconds)),
      DialLabels.sunset(this.language, TimeFormat.clock(this.snapshot.sunsetLocalSeconds)),
      DialLabels.noon(this.language, TimeFormat.clock(this.snapshot.solarNoonLocalSeconds))
    ];
    return SunPathGeometry.labelAnchors(this.sunDialPath(), this.sunriseDialHour(), this.sunsetDialHour(),
      this.cs(SUN_LABEL_GAP), this.cs(SUN_NOON_LABEL_GAP), this.cs(SUN_LABEL_TOP_INSET),
      this.cs(SUN_LABEL_RISE), this.cs(11), this.cs(4), 5, texts, this.cs(14));
  }

  /** 日出对应的**当地真太阳时**（小时数）；极昼/极夜没有日出，返回 null。 */
  private sunriseDialHour(): number | null {
    return this.snapshot.polar === PolarState.NORMAL
      ? this.snapshot.sunriseTrueSolarSeconds / SECONDS_PER_HOUR
      : null;
  }

  /** 日落对应的**当地真太阳时**（小时数）；极昼/极夜没有日落，返回 null。 */
  private sunsetDialHour(): number | null {
    return this.snapshot.polar === PolarState.NORMAL
      ? this.snapshot.sunsetTrueSolarSeconds / SECONDS_PER_HOUR
      : null;
  }

  /**
   * 画圆盘（Canvas 只画图形，文字标签在 `sunDialLabelLayer` 里用真正的 Text 叠上去）：
   * 白天实线弧 / 夜晚虚线弧、地平线（画布左右各内缩 4vp）、日出日落刻度、当前太阳点。
   * 圆盘边界只保留这两条弧，不再画圆外那圈细描边（「表圈」已按用户反馈去掉）。
   * 颜色全部取 `palette`（白天/夜间两套），坐标全部来自 `core/SunPath.ets`。
   */
  private drawSunDial(): void {
    if (!this.sunCtxReady || this.sunDialW <= 0 || this.sunDialH <= 0) {
      return;
    }
    const path: SunPath = this.sunDialPath();
    const ctx: CanvasRenderingContext2D = this.sunCtx;
    const width: number = this.sunDialW;
    const height: number = this.sunDialH;
    const outline: string = this.palette.subtle;
    // 白天弧专用色：白天是淡金色（仅作路径示意），夜间仍是金色实色。
    // 地平线 / 运动箭头都不用 arcColor，保持 subtle；日出日落交点不再画刻度点。
    const arcColor: string = this.palette.sunArc;
    const full: number = Math.PI * 2;
    ctx.clearRect(0, 0, width, height);

    // 未知态：昼弧 180° 实线 + 夜弧 180° 虚线、地平线过圆心；无太阳点/箭头/标签。
    if (this.locationUnknown) {
      const centerX: number = width / 2;
      const centerY: number = height / 2;
      const radius: number = SunPathGeometry.RADIUS_RATIO * Math.min(width, height);
      ctx.beginPath();
      ctx.arc(centerX, centerY, radius, Math.PI, full, false);
      ctx.strokeStyle = arcColor;
      ctx.lineWidth = SunDialColors.DAY_ARC_WIDTH;
      ctx.setLineDash([]);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(centerX, centerY, radius, 0, Math.PI, false);
      ctx.strokeStyle = outline;
      ctx.lineWidth = SunDialColors.NIGHT_ARC_WIDTH;
      ctx.setLineDash([SunDialColors.NIGHT_DASH_LENGTH, SunDialColors.NIGHT_DASH_LENGTH]);
      ctx.stroke();
      ctx.setLineDash([]);
      const horizon: HorizonSpan = SunPathGeometry.horizonSpan(width, this.cs(SUN_HORIZON_INSET));
      ctx.beginPath();
      ctx.strokeStyle = outline;
      ctx.lineWidth = 1;
      ctx.moveTo(horizon.startX, centerY);
      ctx.lineTo(horizon.endX, centerY);
      ctx.stroke();
      return;
    }

    // 白天弧 / 夜晚弧；极昼极夜没有「日出→日落」那一段，整圆一种性质。
    // 南半球（southernHemisphere）扫角为负 → 用 anticlockwise 反向画，整圆也一样。
    const southern: boolean = path.southernHemisphere;
    const span: SunArcSpan | null = SunPathGeometry.dayArcSpan(this.sunriseDialHour(),
      this.sunsetDialHour(), southern);
    if (span === null) {
      ctx.beginPath();
      ctx.arc(path.centerX, path.centerY, path.radius, 0, full, southern);
      if (path.isWholeCircleDay()) {
        ctx.strokeStyle = arcColor;
        ctx.lineWidth = SunDialColors.DAY_ARC_WIDTH;
        ctx.setLineDash([]);
      } else {
        ctx.strokeStyle = outline;
        ctx.lineWidth = SunDialColors.NIGHT_ARC_WIDTH;
        ctx.setLineDash([SunDialColors.NIGHT_DASH_LENGTH, SunDialColors.NIGHT_DASH_LENGTH]);
      }
      ctx.stroke();
    } else {
      const start: number = span.startDegrees * Math.PI / 180;
      const sweep: number = span.sweepDegrees * Math.PI / 180;
      const anticlockwise: boolean = sweep < 0;
      // 夜晚弧「从日落点绕回日出点」：北半球到 start+2π、南半球到 start−2π。
      // 这样弧长 = 2π − |sweep|；写成 `sweep ± full` 会让弧长恒等于 2π，整圈虚线压在白天的金色实线上。
      const nightEnd: number = start + (anticlockwise ? -full : full);
      ctx.beginPath();
      ctx.arc(path.centerX, path.centerY, path.radius, start, start + sweep, anticlockwise);
      ctx.strokeStyle = arcColor;
      // 轨迹线要细：白天弧 1.6vp、夜晚虚线 1.5vp（虚线 4/4vp），极昼极夜同样细线。
      ctx.lineWidth = SunDialColors.DAY_ARC_WIDTH;
      ctx.lineCap = 'round';
      ctx.setLineDash([]);
      ctx.stroke();
      // 夜晚弧从外扩后的终点接上：夜晚扫角 = 360 − 白天扫角（为 0 时不画）。
      const nightSweep: number = full - Math.abs(sweep);
      if (nightSweep > 1e-4) {
        ctx.beginPath();
        ctx.arc(path.centerX, path.centerY, path.radius, start + sweep, nightEnd, anticlockwise);
        ctx.strokeStyle = outline;
        ctx.lineWidth = SunDialColors.NIGHT_ARC_WIDTH;
        ctx.lineCap = 'butt';
        ctx.setLineDash([SunDialColors.NIGHT_DASH_LENGTH, SunDialColors.NIGHT_DASH_LENGTH]);
        ctx.stroke();
        ctx.setLineDash([]);
      }
    }

    // 地平线：固定长度的一条横线（画布左右各内缩 4vp），高度由日出时刻决定。
    // 普通日 / 短昼 / 极昼 / 极夜 / 0:00 相切全部画满这一条，一路贯穿、同色同宽 ——
    // 圆内那一段就是「弦」，但不再单独加强，否则短昼时会看起来断成两截。
    // 颜色用 subtle（相当于 Android 的 onSurfaceVariant）：divider 在夜间太暗，几乎看不见。
    const horizon: HorizonSpan = SunPathGeometry.horizonSpan(width, this.cs(SUN_HORIZON_INSET));
    ctx.beginPath();
    ctx.strokeStyle = outline;
    ctx.lineWidth = 1;
    ctx.moveTo(horizon.startX, path.horizonY);
    ctx.lineTo(horizon.endX, path.horizonY);
    ctx.stroke();

    // 太阳运动方向：圆内侧 0.72R 的一段 30° 短弧 + 末端实心小三角（北半球顺时针、南半球逆时针）。
    // 颜色与地平线同源（palette.subtle），线宽 1.5；弧在 0.72R，不会碰到 R 上的太阳点（4.5vp + 柔光）。
    const arrowHour: number = this.snapshot.trueSolarSeconds / SECONDS_PER_HOUR;
    const arrow: MotionArrow = SunPathGeometry.motionArrow(path, arrowHour);
    const arrowRadius: number = path.radius * 0.72;
    const arrowCenterAngle: number = SunPathGeometry.arcAngleOfDayHour(arrowHour, southern);
    const arrowHalfSpan: number = 15 * Math.PI / 180;
    const arrowStartAngle: number = southern
      ? arrowCenterAngle + arrowHalfSpan
      : arrowCenterAngle - arrowHalfSpan;
    const arrowEndAngle: number = southern
      ? arrowCenterAngle - arrowHalfSpan
      : arrowCenterAngle + arrowHalfSpan;
    ctx.beginPath();
    ctx.arc(path.centerX, path.centerY, arrowRadius, arrowStartAngle, arrowEndAngle, southern);
    ctx.strokeStyle = outline;
    ctx.lineWidth = 1.5;
    ctx.setLineDash([]);
    ctx.stroke();
    // 箭头：沿 start→end（即运动方向）画一个长 5vp、半宽 2.5vp 的实心小三角，尖端 = end。
    const arrowDirX: number = arrow.endX - arrow.startX;
    const arrowDirY: number = arrow.endY - arrow.startY;
    const arrowDirLength: number = Math.sqrt(arrowDirX * arrowDirX + arrowDirY * arrowDirY);
    if (arrowDirLength > 0) {
      const ux: number = arrowDirX / arrowDirLength;
      const uy: number = arrowDirY / arrowDirLength;
      const backX: number = -ux * 5;
      const backY: number = -uy * 5;
      const perpX: number = -uy * 2.5;
      const perpY: number = ux * 2.5;
      ctx.beginPath();
      ctx.moveTo(arrow.tipX, arrow.tipY);
      ctx.lineTo(arrow.tipX + backX + perpX, arrow.tipY + backY + perpY);
      ctx.lineTo(arrow.tipX + backX - perpX, arrow.tipY + backY - perpY);
      ctx.closePath();
      ctx.fillStyle = outline;
      ctx.fill();
    }

    // 日出 / 日落交点不再画刻度圆点：白天弧已外扩 0.8° 略穿过地平线（与安卓一致）。

    // 当前太阳点：纯色核心 + 独立光晕。
    //   ① 光晕：从核心半径 2.5vp 到 5.5vp 的独立径向渐变（alpha 0.35 → 0），先画；
    //   ② 核心：半径 2.5vp（≈ 时间轴半径 5.5 × 0.45）的纯色圆，alpha 1.0，不渐变。
    // 地平线以下同尺寸同结构，只把颜色换成低对比色（palette.subtle）。
    const dotColor: string = path.isSunUp() ? this.palette.sunDot : this.palette.subtle;
    const glowColors: string[] = SunDialColors.sunGlowColors(dotColor);
    const glowGradient = ctx.createRadialGradient(
      path.sunX, path.sunY, SunDialColors.SUN_DOT_GLOW_START_RADIUS,
      path.sunX, path.sunY, SunDialColors.SUN_DOT_GLOW_RADIUS);
    glowGradient.addColorStop(0, glowColors[0]);
    glowGradient.addColorStop(1, glowColors[1]);
    ctx.beginPath();
    ctx.fillStyle = glowGradient;
    ctx.arc(path.sunX, path.sunY, SunDialColors.SUN_DOT_GLOW_RADIUS, 0, full);
    ctx.fill();
    ctx.beginPath();
    ctx.fillStyle = SunDialColors.withAlpha(dotColor, SunDialColors.SUN_DOT_CORE_ALPHA);
    ctx.arc(path.sunX, path.sunY, SunDialColors.SUN_DOT_CORE_RADIUS, 0, full);
    ctx.fill();
  }

  /**
   * 宽屏并排时两张卡片的最小高度（vp）：都取太阳卡的自然高度，底边自然对齐。
   * 窄屏返回 0 —— `constraintSize({ minHeight: 0 })` 等于不加约束。
   */
  private wideCardMinHeight(): number {
    return this.isWideLayout() ? this.cs(SUN_CARD_HEIGHT) : 0;
  }
  /**
   * 地图视口的宽高比：手机 4:3、平板（并排两栏时）16:9 —— 与安卓版同一套规则。
   * 用比例而不是固定高度，不同尺寸的屏幕/分屏下都不会变形或过矮。
   */
  private mapAspectRatio(): number {
    return this.isWideLayout() ? 16 / 9 : 4 / 3;
  }

  /**
   * 大卡片内容的缩放系数。
   *
   * 手机宽约 366vp、卡片约 334vp；平板并排后每张卡有 458vp。字号原本是固定 vp，
   * 卡变宽而字号不变，内容只占 65% 宽，看上去就"小一号"。宽屏时把卡片内的
   * 字号/图标/细线统一放大到 458/334 ≈ 1.35 倍，卡片高度自然长到 ~260vp，
   * 与手机版的比例一致；太阳卡片用同一系数，两张卡仍然等高。
   */
  private cardScale(): number {
    return this.isWideLayout() ? 1.35 : 1;
  }

  /** 按卡片缩放系数换算尺寸（字号、图标、内边距都用它）。 */
  private cs(value: number): number {
    return Math.round(value * this.cardScale() * 10) / 10;
  }

  /** 是否走宽屏并排布局（内容区 ≥ 560vp）。 */
  private isWideLayout(): boolean {
    return this.contentWidth >= WIDE_LAYOUT_BREAKPOINT;
  }

  /** 每 1fp 对应的宽度（vp）。量一次就缓存：等宽数字下与实际时刻无关。 */
  private clockWidthRatio(): number {
    if (this.clockRatioCache > 0) {
      return this.clockRatioCache;
    }
    const utils: MeasureUtils = this.getUIContext().getMeasureUtils();
    const probe: number = 100;
    // measureTextSize 的返回值是 **px**（fontSize 的 number 单位是 fp），所以比例是「px / 1fp」；
    // 下面算可用宽度时也用 px，两边单位必须一致（踩过坑：拿 vp 除 px 比例，字号会被压到下限）。
    const mainW: number = utils.measureTextSize({
      textContent: '00:00',
      fontSize: probe,
      fontFamily: CARD_FONT_MEDIUM
    }).width as number;
    const secW: number = utils.measureTextSize({
      textContent: ':00',
      fontSize: probe / 2,
      fontFamily: CARD_FONT_MEDIUM
    }).width as number;
    const ratio: number = (mainW + secW + vp2px(HERO_CLOCK_SECONDS_GAP)) / probe;
    this.clockRatioCache = ratio;
    return ratio;
  }

  /** 时间主字号（fp）：让「时:分:秒」正好撑满时钟那一栏。 */
  private clockMainSize(): number {
    const ratio: number = this.clockWidthRatio();
    if (this.clockColumnWidth <= 0 || ratio <= 0) {
      return HERO_CLOCK_FALLBACK_FP;
    }
    const fitted: number = vp2px(this.clockColumnWidth) / ratio * HERO_CLOCK_FIT_SAFETY;
    return Math.max(HERO_CLOCK_MIN_FP, Math.min(HERO_CLOCK_MAX_FP, fitted));
  }

  /** 秒（连同它前面的冒号）恒为主字号的一半。 */
  private clockSecondSize(): number {
    return this.clockMainSize() / 2;
  }

  /** 半高秒往上抬一点，让它的基线与主数字对齐（按主字号等比）。 */
  private clockSecondLift(): number {
    return Math.round(this.clockMainSize() * 0.12);
  }

  /**
   * 系统字体的「行盒 / 字号」比例（只量一次）。
   *
   * 卡片改用自带字体后，行盒高会跟着字体自身的 hhea/typo 度量走（这两份子集是 1.20em），
   * 与系统字体的行盒不同 → 卡片高度会变。这里量的是**系统字体**的比例，
   * 再把卡片文本的 `lineHeight` 钉到同一个比例，版面与改造前一致；
   * 不在代码里写死 1.265 / 1.347 这类具体数字。
   */
  private systemLineBoxRatio(): number {
    if (this.lineBoxRatioCache > 0) {
      return this.lineBoxRatioCache;
    }
    const utils: MeasureUtils = this.getUIContext().getMeasureUtils();
    const probe: number = 100;
    // measureTextSize 的高度是 px、fontSize 的 number 单位是 fp，先换算到同一单位再取比值。
    const lineHeightPx: number =
      utils.measureTextSize({ textContent: 'Hg', fontSize: probe }).height as number;
    const ratio: number = lineHeightPx > 0 ? lineHeightPx / vp2px(probe) : 0;
    if (ratio > 0) {
      this.lineBoxRatioCache = ratio;
    }
    return ratio;
  }

  /** 卡片文本的行高（fp）：字号 × 系统字体行盒比例，保证行盒与系统字体时一致。 */
  private cardLineHeight(size: number): number {
    const ratio: number = this.systemLineBoxRatio();
    if (ratio <= 0) {
      return size;
    }
    return Math.round(size * ratio * 10) / 10;
  }

  /** 卡片文本的字族：按请求字重选自带字面，避免系统在缺字重时合成粗体。 */
  private cardFont(weight: FontWeight): string {
    return weight === FontWeight.Medium ? CARD_FONT_MEDIUM : CARD_FONT_REGULAR;
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 12 }) {
          // 平板/宽屏：大卡片与太阳卡片按 1:1 并排、底边对齐（靠两卡同一个 minHeight）；
          // 手机仍上下排列。阈值 560vp：手机约 366vp、MatePad Pro 13 竖屏约 600vp、横屏更宽。
          if (this.contentWidth >= WIDE_LAYOUT_BREAKPOINT) {
            Row({ space: 12 }) {
              Column() {
                this.heroCard()
              }
              .layoutWeight(1)

              Column() {
                this.sunCard()
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            this.heroCard()
            this.sunCard()
          }
          this.mapCard()
          // 首页只在页脚留版本号；天气数据来源署名放在设置页「关于」里（许可要求，不在这里重复）。
          Text(`v${AppInfo.versionName()}`)
            .fontSize(10)
            .fontColor(this.palette.subtle)
            .margin({ top: 4, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const width: number = Number(newValue.width);
          // 只在宽度真的变了才更新，避免每帧都触发一次布局。
          if (!Number.isNaN(width) && Math.abs(width - this.contentWidth) > 1) {
            this.contentWidth = width;
          }
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.page)
  }
}
