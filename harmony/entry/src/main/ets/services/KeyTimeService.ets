/**
 * 关键时间取数：抓「西格瑪食療」页面上的「服用時間 Take Time」。
 *
 * 页面只有一个固定地址、内容变化很慢，因此：
 * 成功一次就把结果连时间戳存下来；后续刷新只用缓存，距上次尝试超过一小时才重新联网。
 * 缓存超过 7 天即视为无效 —— 于是「从未打开过」和「7 天内没打开过」都只画轴线、不着色。
 * 每天只在 01:00–05:00 之间挑一个随机时刻同步，免得所有人都卡在同一点上访问。
 */

import { TakeBand, TakeTemperature, TakeTimeLogic, TAKE_TIME_VALID_MILLIS } from '../core/TakeTime';
import { TakeTimeSchedule } from '../core/TakeTime';
import { AppStore, CachedKeyTime } from './Store';
import { HttpUtil } from './HttpUtil';

const PAGE_URL: string = 'https://www.duosuccess.com/tcm/001a01080301b01a.htm';
const TIMEOUT_MILLIS: number = 10000;

/**
 * 「关键时间」（服用时间）功能开关。
 *
 * 打开后会抓取第三方网页（duosuccess.com）的「Take Time」时段并解析成时间轴：
 * 首页轴线上的彩色时段、真太阳时落在关键时段时的配色、以及到点报时都依赖它。
 * 每天只在 01:00–05:00 之间挑一个随机时刻联网同步一次，成功后缓存 7 天。
 */
export const KEY_TIME_FEATURE_ENABLED: boolean = true;

/** 本地日期键，例如 "2026-11-02"。 */
export function localDayKey(epochMillis: number): string {
  const date: Date = new Date(epochMillis);
  const month: string = date.getMonth() + 1 < 10 ? `0${date.getMonth() + 1}` : `${date.getMonth() + 1}`;
  const day: string = date.getDate() < 10 ? `0${date.getDate()}` : `${date.getDate()}`;
  return `${date.getFullYear()}-${month}-${day}`;
}

/** 本地当天 00:00 的时间戳。 */
function localDayStart(epochMillis: number): number {
  const date: Date = new Date(epochMillis);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

export class KeyTimeService {
  private static inFlight: boolean = false;

  /** 当前可用的关键时间；缓存缺失或超过 7 天返回 null（此时不着色、不报时）。 */
  static schedule(): TakeTimeSchedule | null {
      if (!KEY_TIME_FEATURE_ENABLED) {
        return null;
      }
    const cached: CachedKeyTime = AppStore.keyTime();
    const bands: TakeBand[] = TakeTimeLogic.decodeBands(cached.bands);
    if (bands.length === 0) {
      return null;
    }
    if (!TakeTimeLogic.isFresh(Date.now() - cached.fetchedMillis)) {
      return null;
    }
    return new TakeTimeSchedule(bands, TakeTimeLogic.temperatureFromKey(cached.temperature));
  }

  /** 关键时间要求（冻/热）对应的颜色键，卡片与界面共用。 */
  static temperatureKey(schedule: TakeTimeSchedule | null): string {
    if (schedule === null) {
      return '';
    }
    return TakeTimeLogic.temperatureToKey(schedule.temperature);
  }

  /** 今天该不该联网；是则先记下尝试时刻（失败后一小时重试）。 */
  static async refreshIfDue(): Promise<boolean> {
      if (!KEY_TIME_FEATURE_ENABLED) {
        return false;
      }
    if (KeyTimeService.inFlight) {
      return false;
    }
    const now: number = Date.now();
    const today: string = localDayKey(now);
    const cached: CachedKeyTime = AppStore.keyTime();
    let target: number = cached.targetMillis;
    if (cached.targetDay !== today || target <= 0) {
      const offsetMinutes: number = 60 + Math.floor(Math.random() * 240);
      target = TakeTimeLogic.targetMillis(localDayStart(now), offsetMinutes);
      AppStore.saveKeyTimeTarget(today, target);
    }
    if (!TakeTimeLogic.shouldSync(now, target, today, cached.successDay, cached.attemptMillis)) {
      return false;
    }

    KeyTimeService.inFlight = true;
    AppStore.markKeyTimeAttempt();
    try {
      const body: string | null = await HttpUtil.getText(PAGE_URL, {}, TIMEOUT_MILLIS);
      if (body === null) {
        return false;
      }
      const parsed: TakeTimeSchedule | null = TakeTimeLogic.parse(body);
      if (parsed === null) {
        return false;
      }
      AppStore.saveKeyTime(
        TakeTimeLogic.encodeBands(parsed.bands),
        TakeTimeLogic.temperatureToKey(parsed.temperature),
        today
      );
      return true;
    } finally {
      KeyTimeService.inFlight = false;
    }
  }

  /** 距上次成功抓取还有多久过期（毫秒）；没有数据返回 -1。 */
  static remainingValidity(): number {
    const cached: CachedKeyTime = AppStore.keyTime();
    if (cached.fetchedMillis <= 0 || cached.bands.length === 0) {
      return -1;
    }
    return TAKE_TIME_VALID_MILLIS - (Date.now() - cached.fetchedMillis);
  }

  static temperatureIsHot(schedule: TakeTimeSchedule | null): boolean {
    return schedule !== null && schedule.temperature === TakeTemperature.HOT_OR_MILD;
  }
}
