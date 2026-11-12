/**
 * 十二时辰：以真太阳时为准，每个时辰两小时，子时自 23:00 起。
 */

import { SolarTimeMath } from './SolarTimeMath';

const SECONDS_PER_SICHEN: number = 7200.0;
const SECONDS_PER_DAY: number = 86400.0;

export class Shichen {
  static readonly NAMES: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  static readonly NAMES_EN: string[] = [
    'Zi', 'Chou', 'Yin', 'Mao', 'Chen', 'Si', 'Wu', 'Wei', 'Shen', 'You', 'Xu', 'Hai'
  ];

  private static shift(trueSolarSecondsOfDay: number): number {
    return (((trueSolarSecondsOfDay + 3600.0) % SECONDS_PER_DAY) + SECONDS_PER_DAY) % SECONDS_PER_DAY;
  }

  /** 返回 0..11，0 为子时。传入真太阳时当天的秒数。 */
  static indexOf(trueSolarSecondsOfDay: number): number {
    const shifted: number = Shichen.shift(trueSolarSecondsOfDay);
    return Math.floor(shifted / SECONDS_PER_SICHEN) % 12;
  }

  static nameOf(index: number): string {
    return `${Shichen.NAMES[index]}时`;
  }

  /** 英文界面用拼音，例如 "Zi"；中文界面返回「子时」。 */
  static displayName(index: number, language: string): string {
    if (language.startsWith('zh')) {
      return Shichen.nameOf(index);
    }
    return Shichen.NAMES_EN[index];
  }

  /** 例如 "23:00 – 01:00"。 */
  static rangeText(index: number): string {
    const start: number = (index * 2 + 23) % 24;
    const end: number = (start + 2) % 24;
    return `${pad2(start)}:00 – ${pad2(end)}:00`;
  }

  static secondsIntoShichen(trueSolarSecondsOfDay: number): number {
    return Shichen.shift(trueSolarSecondsOfDay) % SECONDS_PER_SICHEN;
  }

  static secondsToNextShichen(trueSolarSecondsOfDay: number): number {
    return SECONDS_PER_SICHEN - Shichen.secondsIntoShichen(trueSolarSecondsOfDay);
  }

  /** 时初 / 时正，各占一个时辰的前后一小时。 */
  static halfLabel(trueSolarSecondsOfDay: number): string {
    return Shichen.secondsIntoShichen(trueSolarSecondsOfDay) < 3600.0 ? '初' : '正';
  }

  static halfLabelEn(trueSolarSecondsOfDay: number): string {
    return Shichen.secondsIntoShichen(trueSolarSecondsOfDay) < 3600.0 ? 'early' : 'late';
  }

  /** 刻：每 15 分钟一刻，每半个时辰四刻，返回 1..4。 */
  static quarterOfHalf(trueSolarSecondsOfDay: number): number {
    const into: number = Shichen.secondsIntoShichen(trueSolarSecondsOfDay);
    return Math.floor((into % 3600.0) / 900.0) + 1;
  }

  /**
   * 下一个时辰交接的绝对时刻（UTC 毫秒）。
   * 均时差变化率极小，线性外推误差在 1 秒内。
   */
  static nextBoundary(epochMillis: number, longitude: number): number {
    const remaining: number = Shichen.secondsToNextShichen(
      SolarTimeMath.trueSolarSecondsOfDay(epochMillis, longitude)
    );
    return epochMillis + Math.round(remaining * 1000);
  }
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
