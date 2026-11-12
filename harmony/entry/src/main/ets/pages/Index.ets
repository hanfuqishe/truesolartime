import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { CityIndex, NearbyCity } from '../core/CityIndex';
import { Place, PlaceSource } from '../core/Place';
import { Shichen } from '../core/Shichen';
import { SolarSnapshot, SolarTimeSnapshot } from '../core/SolarSnapshot';
import { AxisSegment, TakeBand, TakeTimeLogic, TakeTimeSchedule } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { PolarState, SolarTimeMath } from '../core/SolarTimeMath';
import { WeatherLogic, WeatherSnapshot } from '../core/Weather';
import { AppStore } from '../services/Store';
import { CardService } from '../services/CardService';
import { ChimePlayer } from '../services/ChimePlayer';
import { DistrictService } from '../services/DistrictService';
import { KeyTimeService } from '../services/KeyTimeService';
import { LocationService } from '../services/LocationService';
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
  @State keyTimeText: string = '';
  @State keyTimeState: string = '';
  @State segments: string[] = [];
  @State temperatureKey: string = '';
  @State shichenReminders: boolean = false;
  @State keyTimeChime: boolean = false;
  @State locating: boolean = false;
  @State manualLatitude: string = '';
  @State manualLongitude: string = '';
  @State showManualInput: boolean = false;
  @State hint: string = '';

  private timerId: number = -1;
  private previousSolarSecond: number = -1;
  private previousShichenIndex: number = -1;
  private lastDerivedMillis: number = 0;
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
    AppStore.init(this.context);
    this.place = AppStore.place();
    this.shichenReminders = AppStore.shichenReminders();
    this.keyTimeChime = AppStore.keyTimeChime();
    this.refreshDerived();
    this.lastDerivedMillis = Date.now();
    this.tick();
    this.timerId = setInterval(() => {
      this.tick();
    }, 1000);
    this.refreshRemote();
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
    this.weatherRange = range === null ? '' : `${range[0]}° ~ ${range[1]}°`;

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

  private async locate(): Promise<void> {
    const context: common.UIAbilityContext | null = this.context;
    if (context === null || this.locating) {
      return;
    }
    this.locating = true;
    try {
      const granted: boolean = await LocationService.ensurePermission(context);
      AppStore.setLocationAsked(true);
      if (!granted) {
        promptAction.showToast({ message: '未授予定位权限，可在设置里手动输入坐标' });
        return;
      }
      const point = await LocationService.current();
      if (point === null) {
        promptAction.showToast({ message: '暂时取不到位置，请稍后再试' });
        return;
      }
      this.applyPlace(new Place(point.latitude, point.longitude, PlaceSource.GPS, '', ''));
    } finally {
      this.locating = false;
    }
  }

  private applyManual(): void {
    const latitude: number = Number.parseFloat(this.manualLatitude);
    const longitude: number = Number.parseFloat(this.manualLongitude);
    if (!Place.isValidLatitude(latitude) || !Place.isValidLongitude(longitude)) {
      promptAction.showToast({ message: '请输入有效的经纬度' });
      return;
    }
    this.showManualInput = false;
    this.applyPlace(new Place(latitude, longitude, PlaceSource.MANUAL, '', ''));
  }

  private placeLabel(place: Place): string {
    const city: NearbyCity | null = CityIndex.nearest(place.latitude, place.longitude, DistrictService.language());
    if (city !== null) {
      return city.name;
    }
    return TimeFormat.coordinates(place.latitude, place.longitude);
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
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  heroCard() {
    Column() {
      Row() {
        Text(this.district.length > 0 ? this.district : this.placeName)
          .fontSize(13)
          .fontColor(TEXT_COLOR)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`${this.snapshot.shichenName} · ${this.snapshot.shichenHalf}`)
          .fontSize(13)
          .fontColor(HERO_COLOR)
      }
      .width('100%')

      Row() {
        Text(TimeFormat.clock(this.solarSecond))
          .fontSize(66)
          .fontWeight(FontWeight.Bold)
          .fontColor(HERO_COLOR)
        Text(':')
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor(HERO_COLOR)
          .margin({ bottom: 12 })
        Text(pad2(this.solarSecond % 60))
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor(HERO_COLOR)
          .margin({ left: 2 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(`${this.snapshot.shichenName} ${this.snapshot.shichenRange} · 第 ${this.snapshot.shichenQuarter} 刻`)
          .fontSize(11)
          .fontColor(SUBTLE_COLOR)
          .layoutWeight(1)
        Text(TimeFormat.signedDuration(this.snapshot.offsetSeconds, this.language))
          .fontSize(11)
          .fontColor(SUBTLE_COLOR)
      }
      .width('100%')
    }
    .cardStyle()
  }

  @Builder
  beijingCard() {
    Column() {
      Row() {
        Text('北京时间')
          .fontSize(13)
          .fontColor(SUBTLE_COLOR)
          .layoutWeight(1)
        Text(TimeFormat.clockWithSeconds(this.beijingSecond))
          .fontSize(18)
          .fontColor(TEXT_COLOR)
      }
      .width('100%')
      Divider().color('#24304F').margin({ top: 10, bottom: 10 })
      Row() {
        this.metric('日期', TimeFormat.dateWithWeekday(Date.now(), this.language))
        this.metric('经度修正', TimeFormat.signedDuration(this.snapshot.longitudeOffsetSeconds, this.language))
        this.metric('均时差', TimeFormat.signedDuration(this.snapshot.equationOfTimeSeconds, this.language))
      }
      .width('100%')
    }
    .cardStyle()
  }

  @Builder
  metric(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(10)
        .fontColor(SUBTLE_COLOR)
      Text(value)
        .fontSize(12)
        .fontColor(TEXT_COLOR)
        .margin({ top: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  weatherCard() {
    Column() {
      Row() {
        Text('天气')
          .fontSize(13)
          .fontColor(SUBTLE_COLOR)
          .layoutWeight(1)
        Text('Open-Meteo')
          .fontSize(10)
          .fontColor('#5A6885')
      }
      .width('100%')
      Row() {
        Text(this.weatherTemperature)
          .fontSize(30)
          .fontColor(TEXT_COLOR)
        Column() {
          Text(this.weatherText)
            .fontSize(13)
            .fontColor(TEXT_COLOR)
          Text(this.weatherRange.length > 0 ? `今日 ${this.weatherRange}` : '暂无预报')
            .fontSize(11)
            .fontColor(SUBTLE_COLOR)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .cardStyle()
  }

  @Builder
  keyTimeCard() {
    Column() {
      Row() {
        Text('关键时间')
          .fontSize(13)
          .fontColor(SUBTLE_COLOR)
          .layoutWeight(1)
        Text(this.keyTimeState)
          .fontSize(11)
          .fontColor(this.bandColor())
      }
      .width('100%')

      Row() {
        ForEach(this.segments, (item: string) => {
          if (isBandSegment(item)) {
            Row()
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.bandColor())
              .layoutWeight(segmentLength(item))
          } else {
            Row()
              .height(8)
              .layoutWeight(segmentLength(item))
          }
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .height(8)
      .borderRadius(4)
      .backgroundColor('#24304F')
      .margin({ top: 10 })

      Row() {
        Text('0:00')
          .fontSize(9)
          .fontColor('#5A6885')
          .layoutWeight(1)
        Text('12:00')
          .fontSize(9)
          .fontColor('#5A6885')
        Text('24:00')
          .fontSize(9)
          .fontColor('#5A6885')
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .margin({ top: 4 })

      Text(this.keyTimeText.length > 0 ? this.keyTimeText : '还没有关键时间数据（每天 01:00–05:00 自动同步一次）')
        .fontSize(12)
        .fontColor(this.keyTimeText.length > 0 ? TEXT_COLOR : SUBTLE_COLOR)
        .margin({ top: 8 })
        .width('100%')
    }
    .cardStyle()
  }

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
          .fontColor(SUBTLE_COLOR)
      }
      .width('100%')
      Row() {
        this.metric('日出', TimeFormat.clock(this.snapshot.sunriseBeijingSeconds))
        this.metric('上中天', TimeFormat.clock(this.snapshot.solarNoonBeijingSeconds))
        this.metric('日落', TimeFormat.clock(this.snapshot.sunsetBeijingSeconds))
        this.metric('白昼', this.snapshot.daylightSeconds >= 0
          ? TimeFormat.duration(this.snapshot.daylightSeconds, this.language)
          : '--')
      }
      .width('100%')
      .margin({ top: 10 })
      Text(`日出日落按真太阳时：${TimeFormat.clock(this.snapshot.sunriseTrueSolarSeconds)} / ` +
        `${TimeFormat.clock(this.snapshot.sunsetTrueSolarSeconds)}`)
        .fontSize(10)
        .fontColor('#5A6885')
        .margin({ top: 8 })
      if (this.sunSummary().length > 0) {
        Text(this.sunSummary())
          .fontSize(11)
          .fontColor(SUBTLE_COLOR)
          .margin({ top: 4 })
      }
    }
    .cardStyle()
  }

  @Builder
  placeCard() {
    Column() {
      Row() {
        Text('观测点')
          .fontSize(13)
          .fontColor(SUBTLE_COLOR)
          .layoutWeight(1)
        Text(TimeFormat.coordinates(this.place.latitude, this.place.longitude))
          .fontSize(11)
          .fontColor(SUBTLE_COLOR)
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(Place.PRESETS, (preset: Place, index: number) => {
          Text(index < this.presetLabels.length ? this.presetLabels[index] : TimeFormat.coordinates(preset.latitude, preset.longitude))
            .fontSize(12)
            .fontColor(this.place.sameLocation(preset) ? PAGE_COLOR : TEXT_COLOR)
            .backgroundColor(this.place.sameLocation(preset) ? HERO_COLOR : '#24304F')
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.applyPlace(preset);
            })
        }, (preset: Place) => `${preset.latitude}-${preset.longitude}`)
      }
      .width('100%')

      Row() {
        Button(this.locating ? '定位中…' : '使用当前位置')
          .fontSize(13)
          .backgroundColor('#24304F')
          .fontColor(TEXT_COLOR)
          .layoutWeight(1)
          .height(38)
          .onClick(() => {
            this.locate();
          })
        Button('手动输入')
          .fontSize(13)
          .backgroundColor('#24304F')
          .fontColor(TEXT_COLOR)
          .layoutWeight(1)
          .height(38)
          .margin({ left: 8 })
          .onClick(() => {
            this.showManualInput = !this.showManualInput;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      if (this.showManualInput) {
        Row() {
          TextInput({ text: this.manualLatitude, placeholder: '纬度 39.9042' })
            .type(InputType.NUMBER_DECIMAL)
            .backgroundColor('#0F1830')
            .fontColor(TEXT_COLOR)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.manualLatitude = value;
            })
          TextInput({ text: this.manualLongitude, placeholder: '经度 116.4074' })
            .type(InputType.NUMBER_DECIMAL)
            .backgroundColor('#0F1830')
            .fontColor(TEXT_COLOR)
            .layoutWeight(1)
            .margin({ left: 8 })
            .onChange((value: string) => {
              this.manualLongitude = value;
            })
          Button('确定')
            .fontSize(13)
            .backgroundColor(HERO_COLOR)
            .fontColor(PAGE_COLOR)
            .margin({ left: 8 })
            .onClick(() => {
              this.applyManual();
            })
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .cardStyle()
  }

  @Builder
  settingsCard() {
    Column() {
      Text('提醒')
        .fontSize(13)
        .fontColor(SUBTLE_COLOR)
        .width('100%')
      Row() {
        Column() {
          Text('时辰交接提醒')
            .fontSize(14)
            .fontColor(TEXT_COLOR)
          Text('进入下一个时辰时响一声（250 ms）')
            .fontSize(10)
            .fontColor(SUBTLE_COLOR)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.shichenReminders })
          .onChange((isOn: boolean) => {
            this.shichenReminders = isOn;
            AppStore.setShichenReminders(isOn);
            this.previousShichenIndex = -1;
            this.rescheduleReminders();
          })
      }
      .width('100%')
      .margin({ top: 10 })

      Row() {
        Column() {
          Text('关键时间报时')
            .fontSize(14)
            .fontColor(TEXT_COLOR)
          Text('每进入一段关键时间响一次（500 ms）')
            .fontSize(10)
            .fontColor(SUBTLE_COLOR)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.keyTimeChime })
          .onChange((isOn: boolean) => {
            this.keyTimeChime = isOn;
            AppStore.setKeyTimeChime(isOn);
            this.rescheduleReminders();
          })
      }
      .width('100%')
      .margin({ top: 14 })

      Text('提醒由系统代理发出：应用不在前台也会到点通知。打开应用时则只响铃、不留通知。')
        .fontSize(10)
        .fontColor('#5A6885')
        .margin({ top: 12 })
        .width('100%')
    }
    .cardStyle()
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 12 }) {
          this.heroCard()
          this.beijingCard()
          this.weatherCard()
          this.keyTimeCard()
          this.sunCard()
          this.placeCard()
          this.settingsCard()
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAGE_COLOR)
  }
}
