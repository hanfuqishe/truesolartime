/**
 * 桌面卡片的数据组装与推送。
 *
 * 版面对齐 Android 版小组件：左栏「标准时间」+ 地名 + 日期，右栏「真太阳时」+ 时辰 + 经纬度，
 * 下面是 0–24 时的时间轴与六格逐时预报。
 *
 * 鸿蒙卡片与 Android 小组件的两处硬差异（实测于 HarmonyOS 6.0.0 模拟器，API 20）：
 *   1. 卡片里的 TextClock 只走系统本地时间：`format()` 与 `timeZoneOffset` 都被忽略，
 *      所以真太阳时不能交给 TextClock 自走，只能按快照展示、随卡片刷新更新；
 *   2. 卡片里禁用 setInterval/setTimeout（编译报 11706006 can't support form application），
 *      卡片自身也无法逐秒重算。
 * 于是真太阳时按「HH:mm:ss」快照下发，卡片每次刷新（系统 30 分钟一次 / 应用主动推送）都会更新。
 */

import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AxisSegment, TakeTimeLogic, TakeTimeSchedule } from '../core/TakeTime';
import { SolarSnapshot, SolarTimeSnapshot } from '../core/SolarSnapshot';
import { SolarTimeMath } from '../core/SolarTimeMath';
import { TimeFormat } from '../core/TimeFormat';
import { NearbyCity, CityIndex } from '../core/CityIndex';
import { HourPoint, WeatherLogic, WeatherSnapshot } from '../core/Weather';
import { AppStore } from './Store';
import { DistrictService } from './DistrictService';
import { KeyTimeService } from './KeyTimeService';
import { LocationService, GeoPoint } from './LocationService';
import { Place, PlaceSource } from '../core/Place';
import { WeatherService } from './WeatherService';

/** TextClock 允许的时区偏移范围（分钟）。 */
const MIN_OFFSET_MINUTES: number = -720;
const MAX_OFFSET_MINUTES: number = 840;
/** 逐时预报的格数（与版面一致）。 */
const HOUR_CELLS: number = 6;
const MINUTES_PER_DAY: number = 1440;
const BEIJING_OFFSET_SECONDS: number = SolarTimeMath.BEIJING_OFFSET_MILLIS / 1000;

export class CardData {
  /** 左栏地名（区县名，取不到时退回最近的城市名）。 */
  city: string = '';
  /** 例如「亥时」。 */
  shichen: string = '';
  /** 例如「11 月 12 日 · 星期四」。 */
  dateText: string = '';
  /** 今日温度区间，例如「2° / 12°」。 */
  temperatureRange: string = '';
  /** 当前天气摘要，例如「6° 晴」。 */
  weatherSummary: string = '';
  /** 真太阳时「HH:mm」。 */
  solarTime: string = '';
  /** 真太阳时的秒，两位。 */
  /** 例如「39.9042°N  116.4074°E」。 */
  coords: string = '';
  /** 与北京时间的时差文字，例如「+1 分 31 秒」。 */
  offsetText: string = '';
  /** 时间轴分段，元素形如「900,-1」（长度分钟数,段号，段号 -1 为空档）。 */
  segments: string[] = [];
  /** 当前时刻在时间轴上的位置（分钟），用于画白点。 */
  nowMinute: number = 0;
  /** 一天的分钟数，卡片按比例摆放白点。 */
  dayMinutes: number = MINUTES_PER_DAY;
  /** TextClock 用的时区偏移（分钟）；卡片上会被忽略，保留以便将来系统支持。 */
  offsetMinutes: number = 0;
  /** 六格逐时预报：时刻标签、天气名称、图标名（对应 resources/base/media/wx_*.svg）。 */
  hourLabels: string[] = [];
  hourConds: string[] = [];
  hourIcons: string[] = [];
  /** "cold" / "hot" / ""，决定时间轴色条颜色。 */
  temperatureKey: string = '';
  /** 真太阳时是否落在关键时间段里：落在里面时数字改用色条同色，与 Android 卡片一致。 */
  inKeyTime: boolean = false;
}

export class CardService {
  /** 同步组装卡片数据（onAddForm 必须同步返回）。 */
  static buildData(): CardData {
    const language: string = DistrictService.language();
    const place = AppStore.place();
    const now: number = Date.now();
    const snapshot: SolarSnapshot = SolarTimeSnapshot.compute(now, place.latitude, place.longitude, language);
    const data: CardData = new CardData();

    data.city = CardService.cityName(place.latitude, place.longitude, language);
    data.shichen = snapshot.shichenName;
    data.dateText = TimeFormat.dateCompact(now, language);
    data.solarTime = TimeFormat.clock(snapshot.trueSolarSeconds);
    data.coords = TimeFormat.coordinates(place.latitude, place.longitude);
    data.offsetText = TimeFormat.signedDuration(snapshot.offsetSeconds, language);
    data.nowMinute = snapshot.trueSolarSeconds / 60;
    const minutes: number = Math.round(SolarTimeMath.trueSolarOffsetSeconds(now, place.longitude) / 60);
    data.offsetMinutes = Math.max(MIN_OFFSET_MINUTES, Math.min(MAX_OFFSET_MINUTES, minutes));

    const dayStart: number = CardService.dayStartMillis(now);
    const range: number[] | null = WeatherLogic.temperatureRange(
      WeatherService.hourly(),
      dayStart,
      dayStart + 24 * 3600 * 1000,
      SolarTimeMath.BEIJING_OFFSET_MILLIS
    );
    if (range !== null) {
      data.temperatureRange = `${range[0]}~${range[1]}°`;
    }

    const weather: WeatherSnapshot | null = WeatherService.cached();
    data.weatherSummary = weather === null
      ? ''
      : `${weather.temperatureC}° ${WeatherLogic.conditionLabel(weather.code, language)}`;
    CardService.fillHourly(data, now, weather === null ? -1 : weather.code, language);

    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
    if (schedule !== null && schedule.bands.length > 0) {
      data.segments = CardService.encodeSegments(TakeTimeLogic.axisSegments(schedule.bands));
      data.temperatureKey = TakeTimeLogic.temperatureToKey(schedule.temperature);
      data.inKeyTime = TakeTimeLogic.insideBands(schedule.bands, snapshot.trueSolarSeconds);
    }
    return data;
  }

  /**
   * 地名：优先用逆地理得到的**完整名**（如「上海市黄浦区」），与 Android 卡片的做法一致；
   * 没有逆地理结果时退回最近的城市名，绝不显示占位符。
   */
  private static cityName(latitude: number, longitude: number, language: string): string {
    const full: string = DistrictService.cachedName();
    if (full.length > 0) {
      return full;
    }
    const nearest: NearbyCity | null = CityIndex.nearest(latitude, longitude, language);
    return nearest === null ? '' : nearest.name;
  }

  private static dayStartMillis(epochMillis: number): number {
    const local: number = epochMillis + SolarTimeMath.BEIJING_OFFSET_MILLIS;
    return local - (local % (24 * 3600 * 1000)) - SolarTimeMath.BEIJING_OFFSET_MILLIS;
  }

  /** 逐时预报：从当前小时起六格，第一格标「现在」并用实时天气码。 */
  private static fillHourly(data: CardData, now: number, currentCode: number, language: string): void {
    const hourly: HourPoint[] = WeatherService.hourly();
    const slots: number[] = WeatherLogic.slots(now / 1000, BEIJING_OFFSET_SECONDS, HOUR_CELLS, 1);
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
      const localHour: number = Math.floor(((slot + BEIJING_OFFSET_SECONDS) % 86400) / 3600);
      data.hourLabels.push(index === 0 ? CardService.nowLabel(language) : CardService.hourLabel(localHour, language));
      data.hourConds.push(code < 0 ? '' : WeatherLogic.conditionLabel(code, language));
      data.hourIcons.push(code < 0 ? 'unknown' : WeatherLogic.iconKey(code, localHour >= 6 && localHour <= 17));
    }
  }

  private static nowLabel(language: string): string {
    return language.startsWith('zh') ? '现在' : 'Now';
  }

  private static hourLabel(hour: number, language: string): string {
    return language.startsWith('zh') ? `${hour}时` : `${hour}:00`;
  }

  /** 天气图标名，对应 resources/base/media/wx_*.svg。 */

  /** 卡片布局按比例摆放色条，元素形如「长度,段号」。 */
  private static encodeSegments(segments: AxisSegment[]): string[] {
    return segments.map((segment: AxisSegment): string => `${segment.lengthMinutes},${segment.bandIndex}`);
  }

  /** 把数据推给所有已知的卡片实例。 */
  static async pushToCards(): Promise<void> {
    const formIds: string[] = AppStore.formIds();
    if (formIds.length === 0) {
      return;
    }
    const data: CardData = CardService.buildData();
    const binding: formBindingData.FormBindingData = formBindingData.createFormBindingData(data);
    for (const formId of formIds) {
      try {
        await formProvider.updateForm(formId, binding);
      } catch (error) {
        const failure: BusinessError = error as BusinessError;
        console.warn(`updateForm ${formId} failed: ${failure.code} ${failure.message}`);
      }
    }
  }

  /**
   * 跟随 GPS：位置来源是定位时，每次刷新前重新取一次坐标（与 Android 卡片每次 buildViews
   * 都调用 LocationTracker 的行为一致）。没有权限或取不到定位时保留上一次的坐标。
   */
  private static async syncGpsPlace(): Promise<void> {
    const place: Place = AppStore.place();
    if (place.source !== PlaceSource.GPS) {
      return;
    }
    if (!(await LocationService.hasPermission())) {
      return;
    }
    const point: GeoPoint | null = await LocationService.current();
    if (point === null) {
      return;
    }
    if (Math.abs(point.latitude - place.latitude) < 0.000001 &&
      Math.abs(point.longitude - place.longitude) < 0.000001) {
      return;
    }
    AppStore.setPlace(new Place(point.latitude, point.longitude, PlaceSource.GPS, place.label, place.labelKey));
  }

  /**
   * 取一次天气、关键时间、区划名，然后刷新卡片。
   * 取数失败也照样推一次：至少时间与时辰是新的。
   */
  static async refresh(): Promise<void> {
    try {
      await CardService.syncGpsPlace();
    } catch (error) {
      console.warn('gps sync failed');
    }
    const place = AppStore.place();
    try {
      await DistrictService.refreshIfNeeded(place);
    } catch (error) {
      console.warn('district refresh failed');
    }
    try {
      await WeatherService.refreshIfNeeded(place);
    } catch (error) {
      console.warn('weather refresh failed');
    }
    try {
      await KeyTimeService.refreshIfDue();
    } catch (error) {
      console.warn('key time refresh failed');
    }
    await CardService.pushToCards();
  }
}
