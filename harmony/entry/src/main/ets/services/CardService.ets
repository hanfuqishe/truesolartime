/**
 * 桌面卡片的数据组装与推送。
 *
 * 卡片里没有 Chronometer 这样的自走时钟，但 TextClock 支持任意时区偏移（分钟），
 * 于是「真太阳时相对 UTC 的偏移」正好可以交给它，卡片上的秒是系统在跳，不需要刷新。
 * 其余内容（时辰、天气、关键时间）靠系统每 30 分钟一次的刷新与应用主动推送。
 * 偏移必须是整数分钟，误差因此在 ±30 秒以内。
 */

import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AxisSegment, TakeBand, TakeTimeLogic, TakeTimeSchedule } from '../core/TakeTime';
import { SolarSnapshot, SolarTimeSnapshot } from '../core/SolarSnapshot';
import { SolarTimeMath } from '../core/SolarTimeMath';
import { TimeFormat } from '../core/TimeFormat';
import { WeatherLogic, WeatherSnapshot } from '../core/Weather';
import { AppStore } from './Store';
import { DistrictService } from './DistrictService';
import { KeyTimeService } from './KeyTimeService';
import { WeatherService } from './WeatherService';

/** TextClock 允许的时区偏移范围（分钟）。 */
const MIN_OFFSET_MINUTES: number = -720;
const MAX_OFFSET_MINUTES: number = 840;

export class CardData {
  /** 区县名（最细一级）。 */
  district: string = '';
  /** 完整区划名，卡片放不下时用不上，主界面用。 */
  districtFull: string = '';
  /** 例如「子时 · 初」。 */
  shichen: string = '';
  /** 例如「23:00 – 01:00」。 */
  shichenRange: string = '';
  /** 真太阳时 HH:mm:ss（拍快照时的值；卡片上有 TextClock 时只作回退）。 */
  solarTime: string = '';
  /** 北京时间 HH:mm:ss。 */
  beijing: string = '';
  /** TextClock 用的时区偏移（分钟）。 */
  offsetMinutes: number = 0;
  /** 例如「21°」。 */
  temperature: string = '';
  /** 例如「多云」。 */
  weather: string = '';
  /** 关键时间段的文字，例如「15:00 – 17:00 · 20:00 – 22:00」。 */
  keyTime: string = '';
  /** 时间轴分段，元素形如「900,-1」（长度分钟数,段号，段号 -1 为空档）。 */
  segments: string[] = [];
  /** "cold" / "hot" / ""。 */
  temperatureKey: string = '';
  /** 与北京时间的时差文字，例如「+14 分 22 秒」。 */
  offsetText: string = '';
  /** 数据来源标注。 */
  credit: string = 'Open-Meteo';
}

export class CardService {
  /** 同步组装卡片数据（onAddForm 必须同步返回）。 */
  static buildData(): CardData {
    const language: string = DistrictService.language();
    const place = AppStore.place();
    const now: number = Date.now();
    const snapshot: SolarSnapshot = SolarTimeSnapshot.compute(now, place.latitude, place.longitude, language);
    const data: CardData = new CardData();

    data.districtFull = DistrictService.cachedName();
    data.district = DistrictService.cachedShortName();
    data.shichen = `${snapshot.shichenName} · ${snapshot.shichenHalf}`;
    data.shichenRange = snapshot.shichenRange;
    data.solarTime = TimeFormat.clockWithSeconds(snapshot.trueSolarSeconds);
    data.beijing = TimeFormat.clockWithSeconds(snapshot.beijingSeconds);
    data.offsetText = TimeFormat.signedDuration(snapshot.offsetSeconds, language);
    const minutes: number = Math.round(SolarTimeMath.trueSolarOffsetSeconds(now, place.longitude) / 60);
    data.offsetMinutes = Math.max(MIN_OFFSET_MINUTES, Math.min(MAX_OFFSET_MINUTES, minutes));

    const weather: WeatherSnapshot | null = WeatherService.cached();
    if (weather !== null) {
      data.temperature = `${weather.temperatureC}°`;
      data.weather = WeatherLogic.conditionName(WeatherLogic.conditionOf(weather.code), language);
    } else {
      data.temperature = '--';
      data.weather = '';
    }

    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
    if (schedule !== null && schedule.bands.length > 0) {
      data.keyTime = CardService.bandsText(schedule.bands);
      data.segments = CardService.encodeSegments(TakeTimeLogic.axisSegments(schedule.bands));
      data.temperatureKey = TakeTimeLogic.temperatureToKey(schedule.temperature);
    }
    return data;
  }

  /** 卡片布局按比例摆放色条，元素形如「长度,段号」。 */
  private static encodeSegments(segments: AxisSegment[]): string[] {
    return segments.map((segment: AxisSegment): string => `${segment.lengthMinutes},${segment.bandIndex}`);
  }

  private static bandsText(bands: TakeBand[]): string {
    return bands
      .map((band: TakeBand): string => `${CardService.minutes(band.startMinute)} – ${CardService.minutes(band.endMinute)}`)
      .join('  ');
  }

  private static minutes(minute: number): string {
    return TimeFormat.clock(minute * 60);
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
   * 取一次天气、关键时间、区划名，然后刷新卡片。
   * 取数失败也照样推一次：至少时间与时辰是新的。
   */
  static async refresh(): Promise<void> {
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
