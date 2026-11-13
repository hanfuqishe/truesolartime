import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CityIndex, NearbyCity } from '../core/CityIndex';
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

const HERO_COLOR: string = '#F5D68A';
const TEXT_COLOR: string = '#E8EDF7';
const SUBTLE_COLOR: string = '#9AA7BF';
const CARD_COLOR: string = '#16203A';
const PAGE_COLOR: string = '#0B1220';
const COLD_COLOR: string = '#4CAF7D';
const HOT_COLOR: string = '#D9534F';

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
  @State place: Place = Place.DEFAULT;
  @State placeName: string = '';
  @State presetLabels: string[] = [];
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
  @State shichenReminders: boolean = false;
  @State keyTimeChime: boolean = false;

  private timerId: number = -1;
  private previousSolarSecond: number = -1;
  private previousShichenIndex: number = -1;
  private lastDerivedMillis: number = 0;
  private context: common.UIAbilityContext | null = null;
  private sunSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private sunCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.sunSettings);
  private sunCtxReady: boolean = false;
  private sunW: number = 0;
  private sunH: number = 0;

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
  }

  /**
   * 跟随 GPS 时，每次打开应用静默刷新一次坐标（不弹权限框；没授权就跳过）。
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
    this.districtFull = DistrictService.cachedName();
    this.district = DistrictService.cachedShortName();
    this.placeName = this.placeLabel(this.place);

    const labels: string[] = [];
    for (const preset of Place.PRESETS) {
      labels.push(this.placeLabel(preset));
    }
    this.presetLabels = labels;

    const weather: WeatherSnapshot | null = WeatherService.cached();
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
      WeatherService.hourly(),
      dayStartUtc,
      dayStartUtc + 86400000,
      SolarTimeMath.BEIJING_OFFSET_MILLIS
    );
    this.weatherRange = range === null ? '' : `${range[0]}~${range[1]}°`;
    // 六格逐时预报（首格标「现在」并用实时天气码），与桌面卡片同一套取数规则。
    const hourLabelList: string[] = [];
    const conditions: string[] = [];
    const icons: string[] = [];
    const hourly: HourPoint[] = WeatherService.hourly();
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
      conditions.push(code < 0 ? '' : WeatherLogic.conditionLabel(code, language));
      icons.push(code < 0 ? 'unknown' : WeatherLogic.iconKey(code, localHour >= 6 && localHour <= 17));
    }
    this.hourLabels = hourLabelList;
    this.hourConds = conditions;
    this.hourIcons = icons;

    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
    if (schedule === null || schedule.bands.length === 0) {
      this.keyTimeText = '';
      this.segments = [];
      this.temperatureKey = '';
      this.keyTimeState = KeyTimeService.remainingValidity() < 0 ? '尚未同步' : '数据已过期';
      return;
    }
    this.keyTimeText = schedule.bands
      .map((band: TakeBand): string => `${TimeFormat.clock(band.startMinute * 60)} – ${TimeFormat.clock(band.endMinute * 60)}`)
      .join('   ');
    this.temperatureKey = TakeTimeLogic.temperatureToKey(schedule.temperature);
    this.segments = TakeTimeLogic.axisSegments(schedule.bands).map((segment: AxisSegment): string =>
      `${segment.lengthMinutes},${segment.bandIndex}`);
    this.keyTimeState = this.temperatureKey === 'cold' ? '冻或温' : (this.temperatureKey === 'hot' ? '热或温' : '');
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
    this.tick();
    this.refreshRemote();
    this.rescheduleReminders();
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

  /** 日期 + 当日天气与温度区间，例如「11 月 12 日 · 星期四 · 6° 晴 · 2° ~ 12°」。 */
  private dateTail(): string {
    const parts: string[] = [TimeFormat.dateCompact(Date.now(), this.language)];
    if (this.weatherTemperature !== '--' && this.weatherText.length > 0) {
      parts.push(`${this.weatherTemperature} ${this.weatherText}`);
    }
    if (this.weatherRange.length > 0) {
      parts.push(this.weatherRange);
    }
    return parts.join(' · ');
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

  private bandColor(): string {
    if (this.temperatureKey === 'cold') {
      return COLD_COLOR;
    }
    if (this.temperatureKey === 'hot') {
      return HOT_COLOR;
    }
    return HERO_COLOR;
  }

  /** 距下个时辰交接的秒数，按每秒更新的真太阳时算，倒计时才会走。 */
  private secondsToNextShichen(): number {
    const shifted: number = (((this.solarSecond + 3600) % 86400) + 86400) % 86400;
    return 7200 - (shifted % 7200);
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
    .backgroundColor(CARD_COLOR)
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
          .fontColor(TEXT_COLOR)
        Text('以太阳为准的时间')
          .fontSize(12)
          .fontColor(SUBTLE_COLOR)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.placeName)
        .fontSize(12)
        .fontColor(HERO_COLOR)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ right: 10 })
      Text('设置')
        .fontSize(12)
        .fontColor(TEXT_COLOR)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor('#24304F')
        .borderRadius(12)
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
            Text(this.district.length > 0 ? this.district : this.placeName)
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
              .fontColor(HERO_COLOR)
              .maxLines(1)
            Text(':')
              .fontSize(23)
              .fontWeight(FontWeight.Lighter)
              .fontColor(HERO_COLOR)
              .maxLines(1)
              .margin({ bottom: 5 })
            Text(pad2(this.solarSecond % 60))
              .fontSize(23)
              .fontWeight(FontWeight.Lighter)
              .fontColor(HERO_COLOR)
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
              colors: [['#FFFFFFFF', 0], ['#FFFFFFFF', 0.45], ['#00FFFFFF', 1]]
            })
          Row().layoutWeight(this.solarSecond < 86400 ? (86400 - this.solarSecond) / 60 : 0.1)
        }
        .width('100%')
        .height(11)
      }
      .width('100%')
      .height(11)
      .padding({ left: 6, right: 6 })
      .margin({ top: 10 })

      Row() {
        Text(`距下个时辰 ${TimeFormat.countdown(this.secondsToNextShichen())}`)
          .fontSize(11)
          .fontColor(SUBTLE_COLOR)
          .layoutWeight(1)
        Text(`与北京时间 ${TimeFormat.signedDuration(this.snapshot.offsetSeconds, this.language)}`)
          .fontSize(11)
          .fontColor(SUBTLE_COLOR)
      }
      .width('100%')
      .margin({ top: 8 })

      // 时差构成与时辰进度：原先「时差构成」卡的内容并进来
      Row() {
        Text(`经度修正 ${TimeFormat.signedDuration(this.snapshot.longitudeOffsetSeconds, this.language)} · ` +
          `均时差 ${TimeFormat.signedDuration(this.snapshot.equationOfTimeSeconds, this.language)}`)
          .fontSize(10)
          .fontColor(SUBTLE_COLOR)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`第 ${this.snapshot.shichenQuarter} 刻`)
          .fontSize(10)
          .fontColor(SUBTLE_COLOR)
      }
      .width('100%')
      .margin({ top: 4 })

      // 六格逐时预报
      Row() {
        ForEach(this.hourLabels, (label: string, index: number) => {
          Column() {
            Text(label)
              .fontSize(10)
              .fontColor(SUBTLE_COLOR)
              .maxLines(1)
            Image(weatherIcon(index < this.hourIcons.length ? this.hourIcons[index] : 'unknown'))
              .width(22)
              .height(22)
              .objectFit(ImageFit.Contain)
              .margin({ top: 3 })
            Text(index < this.hourConds.length ? this.hourConds[index] : '')
              .fontSize(10)
              .fontColor(SUBTLE_COLOR)
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
    .linearGradient({ angle: 315, colors: [['#2A3B5C', 0], ['#151B2E', 1]] })
  }

  /** 太阳弧线：与 Android 的 SunArc 同款——虚线弧 + 地平线 + 柔光圆点标出当前太阳位置。 */
  @Builder
  sunCard() {
    Column() {
      Row() {
        Text('太阳')
          .fontSize(13)
          .fontColor(SUBTLE_COLOR)
          .layoutWeight(1)
        Text(`高度角 ${this.snapshot.altitudeDegrees.toFixed(1)}°`)
          .fontSize(11)
          .fontColor(HERO_COLOR)
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
              .fontColor(SUBTLE_COLOR)
            Text(TimeFormat.clock(this.snapshot.sunriseBeijingSeconds))
              .fontSize(17)
              .fontColor(TEXT_COLOR)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Column() {
            Text('上中天')
              .fontSize(10)
              .fontColor(SUBTLE_COLOR)
            Text(TimeFormat.clock(this.snapshot.solarNoonBeijingSeconds))
              .fontSize(17)
              .fontColor(TEXT_COLOR)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Column() {
            Text('日落')
              .fontSize(10)
              .fontColor(SUBTLE_COLOR)
            Text(TimeFormat.clock(this.snapshot.sunsetBeijingSeconds))
              .fontSize(17)
              .fontColor(TEXT_COLOR)
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
          .fontColor('#5A6885')
          .margin({ top: 8 })
          .width('100%')
      } else {
        Text(this.sunSummary())
          .fontSize(11)
          .fontColor(SUBTLE_COLOR)
          .margin({ top: 8 })
          .width('100%')
      }
    }
    .cardStyle()
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
    const trackColor: string = '#3A4763';

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
          Text(`v1.0.0 · 数据来源 Open-Meteo（CC BY 4.0）`)
            .fontSize(10)
            .fontColor('#5A6885')
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
    .backgroundColor(PAGE_COLOR)
  }
}
