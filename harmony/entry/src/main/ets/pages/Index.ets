import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CityIndex, NearbyCity } from '../core/CityIndex';
import { DEFAULT_ZOOM, MapLayer, MapStyle, MapTile, MapTilesLogic, TILE_PX } from '../core/MapTiles';
import { Place, PlaceSource } from '../core/Place';
import { Shichen } from '../core/Shichen';
import { SolarSnapshot, SolarTimeSnapshot } from '../core/SolarSnapshot';
import { AxisSegment, TakeBand, TakeTimeLogic, TakeTimeSchedule } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { ZoneTable } from '../core/ZoneTable';
import { PolarState, SolarTimeMath } from '../core/SolarTimeMath';
import { HourPoint, WeatherLogic, WeatherSnapshot } from '../core/Weather';
import { MeasureUtils, router } from '@kit.ArkUI';
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
const COLD_BAND_ON_DAY_COLOR: string = '#2E7D32';
const HOT_BAND_ON_DAY_COLOR: string = '#B3261E';
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
 * 宽屏并排时两张卡片的最小高度（vp）。
 *
 * ArkUI 的 Row 没有 Stretch 对齐，两卡自然高度不同就会一高一矮。实测（MatePad Pro 13，
 * 宽 916px/458vp 每栏）：大卡片自然高约 193vp、太阳卡片约 226vp（其中太阳弧线 110vp）。
 * 所以宽屏时把弧线压到 90vp，再给两卡同一个 210vp 的 minHeight —— 两者底边对齐，
 * 大卡片只多一点留白。窄屏传 0，等于不加约束。
 */
const WIDE_CARD_MIN_HEIGHT: number = 252;
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
    'zh-Hans'
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
  /** 白天／夜间两套主题，按太阳高度角切换（见 common/Theme.ets）。 */
  @State palette: AppPalette = paletteFor(true);
  @State place: Place = Place.DEFAULT;
  @State placeName: string = '';
  @State district: string = '';
  @State districtFull: string = '';
  @State weatherTemperature: string = '--';
  @State weatherText: string = '';
  @State weatherRange: string = '';
  @State hourLabels: string[] = [];
  @State hourConds: string[] = [];
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
  private sunW: number = 0;
  private sunH: number = 0;
  /** 地图视口尺寸（像素）与双指缩放前的级别。 */
  private mapWpx: number = 0;
  private mapHpx: number = 0;
  private mapBaseZoom: number = DEFAULT_ZOOM;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppStore.init(this.context);
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
    this.shichenReminders = AppStore.shichenReminders();
    this.keyTimeChime = AppStore.keyTimeChime();
    this.mapStyleKey = AppStore.mapStyle();
    this.recenterMap();
  }

  /**
   * 跟随 GPS 时的前台定位节奏：应用打开期间每分钟静默取一次（不弹权限框；没授权就跳过）。
   * 桌面卡片走的是另一条路径，每 5 分钟一次，见 CardService.syncGpsPlace。
   */
  private syncGpsSilently(): void {
    if (this.place.source !== PlaceSource.GPS) {
      return;
    }
    LocationService.hasPermission().then((granted: boolean) => {
      if (!granted) {
        return;
      }
      LocationService.current().then((point: GeoPoint | null) => {
        if (point === null) {
          return;
        }
        this.applyPlace(new Place(point.latitude, point.longitude, PlaceSource.GPS, '', ''));
      });
    });
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

  /** 观测点的标准时区偏移（秒）：优先查国家表，查不到按经度近似。 */
  private zoneOffsetSeconds(): number {
    return ZoneTable.offsetSeconds(AppStore.district().countryCode, this.place.longitude,
      SolarTimeMath.standardZoneOffsetSeconds(this.place.latitude, this.place.longitude));
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
    if (this.place.source === PlaceSource.GPS && this.gpsDue()) {
      this.lastGpsMillis = now;
      this.syncGpsSilently();
    }
    // 太阳弧线上的圆点跟着真太阳时走，每秒重画一次。
    this.drawSunArc();
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
      this.zoneOffsetSeconds());
    this.palette = paletteFor(this.isDayTheme());
    this.districtFull = DistrictService.cachedName();
    this.district = DistrictService.cachedShortName();
    this.placeName = this.placeLabel(this.place);

    const weather: WeatherSnapshot | null = WeatherService.cached(this.place);
    if (weather !== null) {
      this.weatherTemperature = `${weather.temperatureC}°`;
      this.weatherText = WeatherLogic.conditionLabel(weather.code, language);
    } else {
      this.weatherTemperature = '--';
      this.weatherText = '';
    }

    const date: Date = new Date(now + SolarTimeMath.BEIJING_OFFSET_MILLIS);
    const dayStartUtc: number = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
    const range: number[] | null = WeatherLogic.temperatureRange(
      WeatherService.hourly(this.place),
      dayStartUtc,
      dayStartUtc + 86400000,
      SolarTimeMath.BEIJING_OFFSET_MILLIS
    );
    this.weatherRange = range === null ? '' : `${range[0]}~${range[1]}°`;
    // 六格逐时预报（首格标「现在」并用实时天气码），与桌面卡片同一套取数规则。
    const hourLabelList: string[] = [];
    const conditions: string[] = [];
    const icons: string[] = [];
    const hourly: HourPoint[] = WeatherService.hourly(this.place);
    const slots: number[] = WeatherLogic.slots(
      Math.floor(now / 1000),
      SolarTimeMath.BEIJING_OFFSET_MILLIS / 1000,
      6,
      1
    );
    const currentCode: number = weather === null ? -1 : weather.code;
    for (let index = 0; index < slots.length; index++) {
      const slot: number = slots[index];
      let point: HourPoint | null = null;
      for (const candidate of hourly) {
        if (candidate.epochSeconds === slot) {
          point = candidate;
          break;
        }
      }
      let code: number = point === null ? -1 : point.code;
      if (index === 0 && currentCode >= 0) {
        code = currentCode;
      }
      const localHour: number = Math.floor(((slot + SolarTimeMath.BEIJING_OFFSET_MILLIS / 1000) % 86400) / 3600);
      hourLabelList.push(index === 0 ? '现在' : `${localHour}时`);
      conditions.push(code < 0 ? WeatherLogic.PLACEHOLDER : WeatherLogic.conditionLabel(code, language));
      icons.push(code < 0 ? 'unknown' : WeatherLogic.iconKey(code, localHour >= 6 && localHour <= 17));
    }
    this.hourLabels = hourLabelList;
    this.hourConds = conditions;
    this.hourIcons = icons;

    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
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
    CardService.refresh().then(() => {
      this.refreshDerived();
    }).catch((error: BusinessError) => {
      console.warn(`refresh failed: ${error.code} ${error.message}`);
    });
  }

  private applyPlace(place: Place): void {
    this.place = place;
    AppStore.setPlace(place);
    this.refreshDerived();
    this.recenterMap();
    this.tick();
    this.refreshRemote();
    this.rescheduleReminders();
  }

  // ---- 位置地图 ----

  /** 当前设置下的底图图层（自动＝境内高德、境外 OSM）。 */
  private mapLayer(): MapLayer {
    const style: MapStyle = MapTilesLogic.styleFromKey(this.mapStyleKey);
    return MapTilesLogic.layerForStyle(style, this.place.latitude, this.place.longitude);
  }

  /** 地图中心复位到观测点：换城市、跟随 GPS 更新坐标后都要复位。 */
  private recenterMap(): void {
    const layer: MapLayer = this.mapLayer();
    const point: number[] = MapTilesLogic.displayPoint(layer, this.place.latitude, this.place.longitude);
    this.mapCenterLat = point[0];
    this.mapCenterLon = point[1];
    this.refreshMap();
  }

  /** 重算视口内的瓦片；中心、缩放、视口尺寸任一变化后调用。 */
  private refreshMap(): void {
    if (this.mapWpx <= 0 || this.mapHpx <= 0) {
      return;
    }
    const layer: MapLayer = this.mapLayer();
    this.mapAttribution = layer.attribution;
    this.mapTiles = MapTilesLogic.visibleTiles(layer, this.mapCenterLat, this.mapCenterLon,
      this.mapZoom, this.mapWpx, this.mapHpx);
  }

  private zoomMapBy(delta: number): void {
    const next: number = MapTilesLogic.clampZoom(this.mapZoom + delta);
    if (next === this.mapZoom) {
      return;
    }
    this.mapZoom = next;
    this.refreshMap();
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
    const dateWidth: number = utils.measureTextSize({
      textContent: dateText,
      fontSize: size + 'fp'
    }).width as number;
    const coordWidth: number = utils.measureTextSize({
      textContent: coordText,
      fontSize: size + 'fp'
    }).width as number;
    return dateWidth + coordWidth + vp2px(8) <= vp2px(this.dateRowWidth);
  }

  private dateTail(): string {
    const parts: string[] = [TimeFormat.dateCompact(Date.now(), this.language)];
    const hasWeather: boolean = this.weatherTemperature !== '--' && this.weatherText.length > 0;
    if (hasWeather) {
      parts.push(`${this.weatherTemperature} ${this.weatherText}`);
    }
    if (this.weatherRange.length > 0) {
      parts.push(this.weatherRange);
    }
    if (!hasWeather && this.weatherRange.length === 0) {
      parts.push(WeatherLogic.PLACEHOLDER);
    }
    return parts.join(' · ');
  }

  /** 右上角的位置标识：跟随 GPS 时显示「GPS」，其余情况显示当前地名。 */
  private locationBadge(): string {
    return this.place.source === PlaceSource.GPS ? 'GPS' : this.placeName;
  }

  /** 地名：优先完整区划名（市+区），其次区县名，最后退回城市名。 */
  private districtLabel(): string {
    if (this.districtFull.length > 0) {
      return this.districtFull;
    }
    if (this.district.length > 0) {
      return this.district;
    }
    return this.placeName;
  }

  private placeLabel(place: Place): string {
    const city: NearbyCity | null = CityIndex.nearest(place.latitude, place.longitude, DistrictService.language());
    if (city !== null) {
      return city.name;
    }
    return TimeFormat.coordinates(place.latitude, place.longitude);
  }

  /** 轻提示；UIContext 的 PromptAction 可能抛异常，这里统一兜住。 */
  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.warn(`toast failed: ${message}`);
    }
  }

  /** 是否按白天主题绘制：白天浅色纸面 + 橙卡，夜间整体深蓝。 */
  private isDayTheme(): boolean {
    return this.snapshot.isDay();
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
      return day ? COLD_INK_ON_DAY_COLOR : COLD_COLOR;
    }
    if (this.temperatureKey === 'hot') {
      return day ? HOT_INK_ON_DAY_COLOR : HOT_COLOR;
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

  private sunSummary(): string {
    if (this.snapshot.polar === PolarState.MIDNIGHT_SUN) {
      return '极昼：太阳整日不落';
    }
    if (this.snapshot.polar === PolarState.POLAR_NIGHT) {
      return '极夜：太阳整日不升';
    }
    return this.snapshot.hasSunrise() ? '' : '当天没有日出日落';
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
      // 地名要限宽：早先它没有约束、按内容取宽，长地名会把标题与副标题挤成窄条
      // （Android 版修过同一个问题）。这里给标题列吃剩余宽度、地名最多占 40%，
      // 超出右对齐省略——地名短时副标题仍能整行显示。
      .layoutWeight(1)
      Text(this.locationBadge())
        .fontSize(12)
        .fontColor(this.palette.accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .constraintSize({ maxWidth: '40%' })
        .margin({ right: 6 })
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

  /** 首页大卡片：与桌面卡片同款版面，但页面里可以逐秒刷新，所以右栏真太阳时是活的。 */
  @Builder
  heroCard() {
    Column() {
      Row() {
        // 左：标准时间
        Column() {
          Row() {
            Text(TimeFormat.utcOffsetLabel(this.snapshot.localOffsetSeconds))
              .fontSize(this.cs(12))
              .fontColor('#CCFFFFFF')
            Text(this.districtLabel())
              .fontSize(this.cs(12))
              .fontColor('#B3FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          Row() {
            Text(TimeFormat.clock(this.standardSecond))
              .fontSize(this.clockMainSize())
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
            Text(':')
              .fontSize(this.clockSecondSize())
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .margin({ bottom: this.clockSecondLift() })
            Text(pad2(this.standardSecond % 60))
              .fontSize(this.clockSecondSize())
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
          .height(this.cs(58))
          .backgroundColor('#33FFFFFF')
          .margin({ left: 12, right: 12, top: 3 })

        // 右：真太阳时（逐秒刷新）
        Column() {
          Row() {
            Text('真太阳时时钟')
              .fontSize(this.cs(12))
              .fontColor('#CCFFFFFF')
            Text(`${this.snapshot.shichenName} · ${this.snapshot.shichenHalf}`)
              .fontSize(this.cs(12))
              .fontColor('#B3FFFFFF')
              .maxLines(1)
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          Row() {
            Text(TimeFormat.clock(this.solarSecond))
              .fontSize(this.clockMainSize())
              .fontWeight(FontWeight.Medium)
              .fontColor(this.solarColor())
              .maxLines(1)
            Text(':')
              .fontSize(this.clockSecondSize())
              .fontWeight(FontWeight.Medium)
              .fontColor(this.solarColor())
              .maxLines(1)
              .margin({ bottom: this.clockSecondLift() })
            Text(pad2(this.solarSecond % 60))
              .fontSize(this.clockSecondSize())
              .fontWeight(FontWeight.Medium)
              .fontColor(this.solarColor())
              .maxLines(1)
              .margin({ bottom: this.clockSecondLift(), left: 1 })
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
          .fontColor('#B3FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.coordinatesFit(this.dateTail(), TimeFormat.coordinates(this.place.latitude, this.place.longitude))) {
          Text(TimeFormat.coordinates(this.place.latitude, this.place.longitude))
            .fontSize(this.cs(10))
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
          Column()
            .width(this.cs(11))
            .height(this.cs(11))
            .borderRadius(this.cs(5.5))
            .radialGradient({
              center: ['50%', '50%'],
              radius: 5.5,
              colors: [[this.dotColor(), 0], [this.dotColor(), 0.45], [`#00${this.dotColor().substring(1)}`, 1]]
            })
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
              .fontColor(this.hourlyTextColor())
              .maxLines(1)
            Image(weatherIcon(index < this.hourIcons.length ? this.hourIcons[index] : 'unknown'))
              .width(this.cs(22))
              .height(this.cs(22))
              .objectFit(ImageFit.Contain)
              .margin({ top: 3 })
            Text(index < this.hourConds.length ? this.hourConds[index] : '')
              .fontSize(this.cs(10))
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

  /** 太阳弧线：与 Android 的 SunArc 同款——虚线弧 + 地平线 + 柔光圆点标出当前太阳位置。 */
  @Builder
  sunCard() {
    Column() {
      Row() {
        Text('太阳')
          .fontSize(this.cs(13))
          .fontColor(this.palette.subtle)
          .layoutWeight(1)
        Text(`高度角 ${this.snapshot.altitudeDegrees.toFixed(1)}°`)
          .fontSize(this.cs(11))
          .fontColor(this.palette.accent)
      }
      .width('100%')

      Canvas(this.sunCtx)
        .width('100%')
        // 宽屏缩放后取 84×1.35 ≈ 113vp，正好让太阳卡的自然高度与左侧大卡片齐平；窄屏仍 110vp。
        .height(this.isWideLayout() ? this.cs(84) : 110)
        .margin({ top: 6 })
        .onReady(() => {
          this.sunCtxReady = true;
          this.drawSunArc();
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.sunW = Number(newValue.width);
          this.sunH = Number(newValue.height);
          this.drawSunArc();
        })

      if (this.snapshot.polar === PolarState.NORMAL) {
        Row() {
          Column() {
            Text('日出')
              .fontSize(this.cs(10))
              .fontColor(this.palette.subtle)
            Text(TimeFormat.clock(this.snapshot.sunriseLocalSeconds))
              .fontSize(this.cs(17))
              .fontColor(this.palette.text)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Column() {
            Text('上中天')
              .fontSize(this.cs(10))
              .fontColor(this.palette.subtle)
            Text(TimeFormat.clock(this.snapshot.solarNoonLocalSeconds))
              .fontSize(this.cs(17))
              .fontColor(this.palette.text)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Column() {
            Text('日落')
              .fontSize(this.cs(10))
              .fontColor(this.palette.subtle)
            Text(TimeFormat.clock(this.snapshot.sunsetLocalSeconds))
              .fontSize(this.cs(17))
              .fontColor(this.palette.text)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .margin({ top: 10 })
        Text(`白昼 ${this.snapshot.daylightSeconds >= 0
          ? TimeFormat.duration(this.snapshot.daylightSeconds, this.language)
          : '--'} · 真太阳时 ${TimeFormat.clock(this.snapshot.sunriseTrueSolarSeconds)} / ` +
          `${TimeFormat.clock(this.snapshot.sunsetTrueSolarSeconds)}`)
          .fontSize(this.cs(10))
          .fontColor(this.palette.subtle)
          .margin({ top: 8 })
          .width('100%')
      } else {
        Text(this.sunSummary())
          .fontSize(this.cs(11))
          .fontColor(this.palette.subtle)
          .margin({ top: 8 })
          .width('100%')
      }
    }
    .cardStyle()
    .backgroundColor(this.palette.card)
    // 与左侧大卡片同一个最小高度：宽屏并排时底边对齐（窄屏传 0，等于不约束）
    .constraintSize({ minHeight: this.wideCardMinHeight() })
  }

  /**
   * 位置地图：与 Android 的 MapCard 同款——标题 + 坐标、190 高的地图、底图来源。
   * 境内用高德栅格瓦片（中文路网），境外用 OpenStreetMap；标点固定在地图中心，
   * 支持双指缩放与双击放大（页面本身可上下滚动，所以不做拖动平移）。
   */
  @Builder
  mapCard() {
    Column() {
      Row() {
        Text('位置地图')
          .fontSize(13)
          .fontColor(this.palette.subtle)
          .layoutWeight(1)
        Text(TimeFormat.coordinates(this.place.latitude, this.place.longitude))
          .fontSize(11)
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
        // 标点：始终落在视口正中，对应上面的坐标。
        Column()
          .width(16)
          .height(16)
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
          .border({ width: 4, color: this.palette.accent })
          .shadow({ radius: 8, color: '#A6000000' })
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
        this.refreshMap();
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
                  this.mapZoom = next;
                  this.refreshMap();
                }
              }
            }),
          TapGesture({ count: 2 })
            .onAction(() => {
              this.zoomMapBy(1);
            })
        )
      )

      Text(`${this.mapAttribution} · ${this.mapZoom} 级 · 双指缩放`)
        .fontSize(10)
        .fontColor(this.palette.subtle)
        .margin({ top: 6 })
        .width('100%')
    }
    .cardStyle()
    .backgroundColor(this.palette.card)
  }

  /** 白昼进度：真太阳时在日出与日落之间的比例；没有日出日落时取 0.5。 */
  private daylightProgress(): number {
    const sunrise: number = this.snapshot.sunriseTrueSolarSeconds;
    const sunset: number = this.snapshot.sunsetTrueSolarSeconds;
    if (sunrise < 0 || sunset < 0) {
      return 0.5;
    }
    const start: number = sunrise;
    let end: number = sunset;
    if (end <= start) {
      end += 86400;
    }
    let current: number = this.solarSecond;
    if (current < start) {
      current += 86400;
    }
    const span: number = end - start;
    if (span <= 0) {
      return 0.5;
    }
    return Math.min(1, Math.max(0, (current - start) / span));
  }

  /**
   * 画弧：起点 (6%, 88%)、终点 (94%, 88%)、控制点 (50%, -42%) 的二次曲线，
   * 与 Android 的 SunArc 参数一致；太阳位置按白昼进度取曲线上的点。
   */
  private drawSunArc(): void {
    if (!this.sunCtxReady) {
      return;
    }
    const width: number = this.sunW;
    const height: number = this.sunH;
    if (width <= 0 || height <= 0) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.sunCtx;
    // Android 的 SunArc 画在 Compose Canvas 上，线宽与虚线间隔都是**像素**；
    // 这里的 Canvas 用 vp，所以统一按屏幕密度换算，两边看起来才是同一套虚线。
    const density: number = vp2px(1);
    const horizonY: number = height * 0.88;
    const startX: number = width * 0.06;
    const endX: number = width * 0.94;
    const controlX: number = width / 2;
    const controlY: number = -height * 0.42;
    const trackColor: string = this.palette.divider;

    ctx.clearRect(0, 0, width, height);

    ctx.beginPath();
    ctx.moveTo(startX, horizonY);
    ctx.quadraticCurveTo(controlX, controlY, endX, horizonY);
    ctx.setLineDash([10 / density, 10 / density]);
    ctx.lineWidth = 2.5 / density;
    ctx.strokeStyle = trackColor;
    ctx.stroke();

    ctx.beginPath();
    ctx.setLineDash([]);
    ctx.moveTo(0, horizonY);
    ctx.lineTo(width, horizonY);
    ctx.lineWidth = 2 / density;
    ctx.strokeStyle = trackColor;
    ctx.stroke();

    const t: number = this.daylightProgress();
    const u: number = 1 - t;
    const sunX: number = u * u * startX + 2 * u * t * controlX + t * t * endX;
    const sunY: number = u * u * horizonY + 2 * u * t * controlY + t * t * horizonY;
    const isDay: boolean = this.snapshot.isDay();
    const sunColor: string = isDay ? '#FFB300' : '#9AA7BF';
    if (isDay) {
      ctx.beginPath();
      ctx.fillStyle = '#2EFFB300';
      ctx.arc(sunX, sunY, 20 / density, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.beginPath();
    ctx.fillStyle = sunColor;
    ctx.arc(sunX, sunY, 7 / density, 0, Math.PI * 2);
    ctx.fill();
  }
  /**
   * 宽屏并排时两张卡片的最小高度（vp）：两者取同一个值，底边自然对齐。
   * 窄屏返回 0 —— `constraintSize({ minHeight: 0 })` 等于不加约束。
   */
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
    const mainW: number = utils.measureTextSize({ textContent: '00:00', fontSize: probe }).width as number;
    const secW: number = utils.measureTextSize({ textContent: ':00', fontSize: probe / 2 }).width as number;
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

  private wideCardMinHeight(): number {
    return this.contentWidth >= WIDE_LAYOUT_BREAKPOINT ? WIDE_CARD_MIN_HEIGHT : 0;
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
          Text(`v${AppInfo.versionName()} · 数据来源 Open-Meteo（CC BY 4.0）`)
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
