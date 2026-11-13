import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CityIndex, NearbyCity } from '../core/CityIndex';
import { DEFAULT_ZOOM, MapLayer, MapTile, MapTilesLogic, TILE_PX } from '../core/MapTiles';
import { Place, PlaceSource } from '../core/Place';
import { Shichen } from '../core/Shichen';
import { SolarSnapshot, SolarTimeSnapshot } from '../core/SolarSnapshot';
import { AxisSegment, TakeBand, TakeTimeLogic, TakeTimeSchedule } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { PolarState, SolarTimeMath } from '../core/SolarTimeMath';
import { HourPoint, WeatherLogic, WeatherSnapshot } from '../core/Weather';
import { router } from '@kit.ArkUI';
import { weatherIcon } from '../common/WeatherIcon';
import { AppStore } from '../services/Store';
import { CardService } from '../services/CardService';
import { ChimePlayer } from '../services/ChimePlayer';
import { DistrictService } from '../services/DistrictService';
import { KeyTimeService } from '../services/KeyTimeService';
import { LocationService, GeoPoint } from '../services/LocationService';
import { ReminderService } from '../services/ReminderService';
import { WeatherService } from '../services/WeatherService';
import { AppPalette, paletteFor } from '../common/Theme';

const HERO_COLOR: string = '#F5D68A';
const COLD_COLOR: string = '#4CAF7D';
const HOT_COLOR: string = '#D9534F';
/** 大卡片按昼夜换底色：白天暖橙，夜里深蓝（与 Android 卡片同一套配色）。 */
const DAY_TOP_COLOR: string = '#F7A64B';
const DAY_BOTTOM_COLOR: string = '#EA7A2C';
const NIGHT_TOP_COLOR: string = '#2A3B5C';
const NIGHT_BOTTOM_COLOR: string = '#151B2E';
/** 白天橙色底上金色看不清，关键时段的色段也换成更暗的一档。 */
const COLD_ON_DAY_COLOR: string = '#2E7D32';
const HOT_ON_DAY_COLOR: string = '#B3261E';
/** 应用在前台时的定位节奏：每分钟一次（桌面卡片是 5 分钟一次）。 */
const GPS_INTERVAL_MILLIS: number = 60 * 1000;

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
  @State beijingSecond: number = 0;
  @State language: string = 'zh-Hans';
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

  private timerId: number = -1;
  /** 上次前台取定位的时刻（毫秒），用于「每分钟一次」的节流。 */
  private lastGpsMillis: number = 0;
  private previousSolarSecond: number = -1;
  private previousShichenIndex: number = -1;
  private lastDerivedMillis: number = 0;
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
    this.refreshDerived();
    this.lastDerivedMillis = Date.now();
    this.tick();
    this.timerId = setInterval(() => {
      this.tick();
    }, 1000);
    this.refreshRemote();
    this.syncGpsSilently();
  }

  /** 从设置页返回后重新读取偏好（观测点、提醒开关都可能在那边改过）。 */
  onPageShow(): void {
    if (this.context === null) {
      return;
    }
    this.reloadSettings();
    this.refreshDerived();
    this.refreshRemote();
  }

  private reloadSettings(): void {
    this.place = AppStore.place();
    this.shichenReminders = AppStore.shichenReminders();
    this.keyTimeChime = AppStore.keyTimeChime();
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

  private tick(): void {
    const now: number = Date.now();
    const seconds: number = Math.floor(SolarTimeMath.trueSolarSecondsOfDay(now, this.place.longitude)) % 86400;
    const shichenIndex: number = Shichen.indexOf(seconds);
    this.checkChime(seconds, shichenIndex);
    this.previousSolarSecond = seconds;
    this.previousShichenIndex = shichenIndex;
    this.solarSecond = seconds;
    this.beijingSecond = Math.floor(SolarTimeMath.beijingSecondsOfDay(now)) % 86400;
    // 关键时间的字色要按秒跟进（进入/离开时段的那一秒就变色），所以放在每秒的 tick 里算。
    this.inKeyTime = TakeTimeLogic.insideBands(this.keyBands, seconds);
    // 跟随 GPS 时前台每分钟取一次定位；桌面卡片侧是 5 分钟一次（CardService）。
    if (this.place.source === PlaceSource.GPS && this.gpsDue()) {
      this.lastGpsMillis = now;
      this.syncGpsSilently();
    }
    // 太阳弧线上的圆点跟着真太阳时走，每秒重画一次。
    this.drawSunArc();
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
    this.snapshot = SolarTimeSnapshot.compute(now, this.place.latitude, this.place.longitude, language);
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

  /** 地图中心复位到观测点：换城市、跟随 GPS 更新坐标后都要复位。 */
  private recenterMap(): void {
    const layer: MapLayer = MapTilesLogic.layerFor(this.place.latitude, this.place.longitude);
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
    const layer: MapLayer = MapTilesLogic.layerFor(this.place.latitude, this.place.longitude);
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
  private solarAccent(): string {
    return this.isDayTheme() ? '#FFFFFF' : HERO_COLOR;
  }

  /** 逐时预报的小字：白天橙色底上要更白一些，夜里沿用弱化色。 */
  private hourlyTextColor(): string {
    return this.isDayTheme() ? '#E6FFFFFF' : this.palette.subtle;
  }

  private bandColor(): string {
    const day: boolean = this.isDayTheme();
    if (this.temperatureKey === 'cold') {
      return day ? COLD_ON_DAY_COLOR : COLD_COLOR;
    }
    if (this.temperatureKey === 'hot') {
      return day ? HOT_ON_DAY_COLOR : HOT_COLOR;
    }
    return this.solarAccent();
  }

  /**
   * 真太阳时的字色：落在关键时间段里时跟随时段的冷暖配色，其余时间按昼夜取白／金
   * —— 与 Android 卡片的 `activeKeyColor` 一致。
   */
  private solarColor(): string {
    return this.inKeyTime ? this.bandColor() : this.solarAccent();
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
        Text('真太阳时')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
        Text('以太阳经过当地子午线的时刻为正午')
          .fontSize(12)
          .fontColor(this.palette.subtle)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.locationBadge())
        .fontSize(12)
        .fontColor(this.palette.accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
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
            Text('标准时间')
              .fontSize(12)
              .fontColor('#CCFFFFFF')
            Text(this.districtLabel())
              .fontSize(12)
              .fontColor('#B3FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          Row() {
            Text(TimeFormat.clock(this.beijingSecond))
              .fontSize(42)
              .fontWeight(FontWeight.Lighter)
              .fontColor('#FFFFFF')
              .maxLines(1)
            Text(':')
              .fontSize(23)
              .fontWeight(FontWeight.Lighter)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .margin({ bottom: 5 })
            Text(pad2(this.beijingSecond % 60))
              .fontSize(23)
              .fontWeight(FontWeight.Lighter)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .margin({ bottom: 5, left: 1 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column()
          .width(1)
          .height(58)
          .backgroundColor('#33FFFFFF')
          .margin({ left: 12, right: 12, top: 3 })

        // 右：真太阳时（逐秒刷新）
        Column() {
          Row() {
            Text('真太阳时')
              .fontSize(12)
              .fontColor('#CCFFFFFF')
            Text(`${this.snapshot.shichenName} · ${this.snapshot.shichenHalf}`)
              .fontSize(12)
              .fontColor('#B3FFFFFF')
              .maxLines(1)
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          Row() {
            Text(TimeFormat.clock(this.solarSecond))
              .fontSize(42)
              .fontWeight(FontWeight.Lighter)
              .fontColor(this.solarColor())
              .maxLines(1)
            Text(':')
              .fontSize(23)
              .fontWeight(FontWeight.Lighter)
              .fontColor(this.solarColor())
              .maxLines(1)
              .margin({ bottom: 5 })
            Text(pad2(this.solarSecond % 60))
              .fontSize(23)
              .fontWeight(FontWeight.Lighter)
              .fontColor(this.solarColor())
              .maxLines(1)
              .margin({ bottom: 5, left: 1 })
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
          .fontSize(10)
          .fontColor('#B3FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(TimeFormat.coordinates(this.place.latitude, this.place.longitude))
          .fontSize(10)
          .fontColor('#B3FFFFFF')
          .maxLines(1)
          .textAlign(TextAlign.End)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 6 })

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
            .width(11)
            .height(11)
            .borderRadius(5.5)
            .radialGradient({
              center: ['50%', '50%'],
              radius: 5.5,
              colors: [[this.dotColor(), 0], [this.dotColor(), 0.45], [`#00${this.dotColor().substring(1)}`, 1]]
            })
          Row().layoutWeight(this.solarSecond < 86400 ? (86400 - this.solarSecond) / 60 : 0.1)
        }
        .width('100%')
        .height(11)
      }
      .width('100%')
      .height(11)
      .margin({ top: 10 })

      // 六格逐时预报
      Row() {
        ForEach(this.hourLabels, (label: string, index: number) => {
          Column() {
            Text(label)
              .fontSize(10)
              .fontColor(this.hourlyTextColor())
              .maxLines(1)
            Image(weatherIcon(index < this.hourIcons.length ? this.hourIcons[index] : 'unknown'))
              .width(22)
              .height(22)
              .objectFit(ImageFit.Contain)
              .margin({ top: 3 })
            Text(index < this.hourConds.length ? this.hourConds[index] : '')
              .fontSize(10)
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
    .padding(16)
    .borderRadius(18)
    .alignItems(HorizontalAlign.Start)
    .linearGradient({
      angle: 315,
      colors: this.isDayTheme()
        ? [[DAY_TOP_COLOR, 0], [DAY_BOTTOM_COLOR, 1]]
        : [[NIGHT_TOP_COLOR, 0], [NIGHT_BOTTOM_COLOR, 1]]
    })
  }

  /** 太阳弧线：与 Android 的 SunArc 同款——虚线弧 + 地平线 + 柔光圆点标出当前太阳位置。 */
  @Builder
  sunCard() {
    Column() {
      Row() {
        Text('太阳')
          .fontSize(13)
          .fontColor(this.palette.subtle)
          .layoutWeight(1)
        Text(`高度角 ${this.snapshot.altitudeDegrees.toFixed(1)}°`)
          .fontSize(11)
          .fontColor(this.palette.accent)
      }
      .width('100%')

      Canvas(this.sunCtx)
        .width('100%')
        .height(110)
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
              .fontSize(10)
              .fontColor(this.palette.subtle)
            Text(TimeFormat.clock(this.snapshot.sunriseBeijingSeconds))
              .fontSize(17)
              .fontColor(this.palette.text)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Column() {
            Text('上中天')
              .fontSize(10)
              .fontColor(this.palette.subtle)
            Text(TimeFormat.clock(this.snapshot.solarNoonBeijingSeconds))
              .fontSize(17)
              .fontColor(this.palette.text)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Column() {
            Text('日落')
              .fontSize(10)
              .fontColor(this.palette.subtle)
            Text(TimeFormat.clock(this.snapshot.sunsetBeijingSeconds))
              .fontSize(17)
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
          .fontSize(10)
          .fontColor(this.palette.subtle)
          .margin({ top: 8 })
          .width('100%')
      } else {
        Text(this.sunSummary())
          .fontSize(11)
          .fontColor(this.palette.subtle)
          .margin({ top: 8 })
          .width('100%')
      }
    }
    .cardStyle()
    .backgroundColor(this.palette.card)
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
        }, (tile: MapTile) => `${tile.url}`)
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
      .height(190)
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
    ctx.setLineDash([10, 10]);
    ctx.lineWidth = 2.5;
    ctx.strokeStyle = trackColor;
    ctx.stroke();

    ctx.beginPath();
    ctx.setLineDash([]);
    ctx.moveTo(0, horizonY);
    ctx.lineTo(width, horizonY);
    ctx.lineWidth = 2;
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
      ctx.arc(sunX, sunY, 20, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.beginPath();
    ctx.fillStyle = sunColor;
    ctx.arc(sunX, sunY, 7, 0, Math.PI * 2);
    ctx.fill();
  }
  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 12 }) {
          this.heroCard()
          this.sunCard()
          this.mapCard()
          Text(`v1.0.0 · 数据来源 Open-Meteo（CC BY 4.0）`)
            .fontSize(10)
            .fontColor(this.palette.subtle)
            .margin({ top: 4, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
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
