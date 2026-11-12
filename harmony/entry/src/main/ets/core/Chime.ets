/**
 * 报时用的纯计算：
 *   - 「进入关键时间」报时：每到一段关键时间的起点响一次（500 ms）；
 *   - 时辰交接提醒：进入下一个时辰的那一刻响一次（250 ms），撞上关键时间起点时让位。
 *
 * 闹钟/提醒的发布放在 services/ReminderService.ets。
 */

import { Shichen } from './Shichen';
import { SolarTimeMath } from './SolarTimeMath';
import { MINUTES_PER_DAY, TakeBand } from './TakeTime';

const SECONDS_PER_DAY: number = 86400.0;

/** 落点与关键时间起点的容差（分钟）。两个提醒同刻触发，差值远小于 1 分钟。 */
const COLLISION_MINUTES: number = 0.5;

/** 对齐容差：正好落在边界上时把「下一个」让给再下一段，避免刚响过又立刻重响。 */
const SETTLE_SECONDS: number = 1;

function floorMod(value: number, modulus: number): number {
  return ((value % modulus) + modulus) % modulus;
}

export class ChimeLogic {
  /** 时辰交接的提示音比关键时间报时更短，便于区分两种提醒。 */
  static readonly SHICHEN_BEEP_MILLIS: number = 250;
  static readonly KEY_TIME_BEEP_MILLIS: number = 500;

  /**
   * 距离下一个关键时间起点还有多少秒（按真太阳时计）。
   * 没有关键时间时返回 -1 —— 此时不报时。
   */
  static secondsToNextKeyStart(solarSecondsOfDay: number, bands: TakeBand[]): number {
    if (bands.length === 0) {
      return -1;
    }
    let best: number = SECONDS_PER_DAY;
    for (const band of bands) {
      const target: number = band.startMinute * 60.0;
      let delta: number = floorMod(target - solarSecondsOfDay, SECONDS_PER_DAY);
      // 正好落在边界上时等明天，避免「刚响过又立刻再响」。
      if (delta < 0.001) {
        delta = SECONDS_PER_DAY;
      }
      best = Math.min(best, delta);
    }
    return best;
  }

  /** solarMinuteOfDay 是否落在某段关键时间的起点附近（同一分钟即算撞车）。 */
  static collidesWithKeyStart(solarMinuteOfDay: number, bands: TakeBand[]): boolean {
    for (const band of bands) {
      const delta: number = floorMod(solarMinuteOfDay - band.startMinute, MINUTES_PER_DAY);
      if (delta < COLLISION_MINUTES || delta > MINUTES_PER_DAY - COLLISION_MINUTES) {
        return true;
      }
    }
    return false;
  }

  /** 下一个时辰交接的系统时刻（UTC 毫秒），留 1 秒容差。 */
  static nextShichenTrigger(epochMillis: number, longitude: number): number {
    return Shichen.nextBoundary(epochMillis + SETTLE_SECONDS * 1000, longitude);
  }

  /**
   * 下一次交接时刻；若正好撞上关键时间起点，就让位给那一声（500 ms 比 250 ms 长），
   * 顺延到再下一个时辰，避免同一刻响两声。
   *
   * 只在「关键时间报时已开启且有数据」时让位 —— 否则交接提醒会被无故吞掉。
   */
  static nextShichenTriggerYielding(
    epochMillis: number,
    longitude: number,
    keyTimeChimeEnabled: boolean,
    bands: TakeBand[]
  ): number {
    const trigger: number = ChimeLogic.nextShichenTrigger(epochMillis, longitude);
    if (!keyTimeChimeEnabled || bands.length === 0) {
      return trigger;
    }
    const solarMinute: number = SolarTimeMath.trueSolarSecondsOfDay(trigger, longitude) / 60.0;
    if (ChimeLogic.collidesWithKeyStart(solarMinute, bands)) {
      return ChimeLogic.nextShichenTrigger(trigger, longitude);
    }
    return trigger;
  }

  /** 未来 [count] 个时辰交接时刻（UTC 毫秒），用于一次性发布多条代理提醒。 */
  static upcomingShichenTriggers(epochMillis: number, longitude: number, count: number): number[] {
    const triggers: number[] = [];
    let cursor: number = epochMillis;
    for (let index = 0; index < count; index++) {
      cursor = ChimeLogic.nextShichenTrigger(cursor, longitude);
      triggers.push(cursor);
    }
    return triggers;
  }

  /** 从现在起未来 [days] 天内所有关键时间起点的系统时刻（UTC 毫秒）。 */
  static upcomingKeyTimeTriggers(epochMillis: number, longitude: number, bands: TakeBand[], days: number): number[] {
    if (bands.length === 0) {
      return [];
    }
    const triggers: number[] = [];
    let cursor: number = epochMillis;
    const horizon: number = epochMillis + days * SECONDS_PER_DAY * 1000;
    while (triggers.length < bands.length * days * 2 && cursor < horizon) {
      const delta: number = ChimeLogic.secondsToNextKeyStart(
        SolarTimeMath.trueSolarSecondsOfDay(cursor, longitude),
        bands
      );
      if (delta < 0) {
        break;
      }
      cursor = cursor + Math.round(delta * 1000);
      if (cursor >= horizon) {
        break;
      }
      triggers.push(cursor);
      // 跨过刚刚那一秒，避免下次仍算出同一个起点。
      cursor = cursor + 1000;
    }
    return triggers;
  }
}
