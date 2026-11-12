/**
 * 「关键时间」（西格瑪食療页面上的「服用時間 Take Time」）的解析与缓存策略。
 *
 * 页面给出的时间一律当作真太阳时使用，不做时区或经度换算。
 * 这里只有纯逻辑：抓网页、读写缓存放在 services/KeyTimeService.ets。
 */

export const MINUTES_PER_DAY: number = 24 * 60;

/** 一段关键时间，按真太阳时的当日分钟数表示；endMinute 小于 startMinute 时表示跨过午夜。 */
export class TakeBand {
  startMinute: number;
  endMinute: number;

  constructor(startMinute: number, endMinute: number) {
    this.startMinute = startMinute;
    this.endMinute = endMinute;
  }

  lengthMinutes(): number {
    return floorMod(this.endMinute - this.startMinute, MINUTES_PER_DAY);
  }

  /** minuteOfDay 是否落在这段关键时间里（含起点、不含终点，跨午夜的段也支持）。 */
  contains(minuteOfDay: number): boolean {
    const offset: number = floorMod(minuteOfDay - this.startMinute, MINUTES_PER_DAY);
    return offset < this.lengthMinutes();
  }
}

/** 时间轴上的一段：从 startMinute 起连续 lengthMinutes 分钟，bandIndex 为 -1 表示空档。 */
export class AxisSegment {
  startMinute: number;
  lengthMinutes: number;
  bandIndex: number;

  constructor(startMinute: number, lengthMinutes: number, bandIndex: number) {
    this.startMinute = startMinute;
    this.lengthMinutes = lengthMinutes;
    this.bandIndex = bandIndex;
  }
}

/** 关键时间的要求：冻或温用绿色，热或温用红色。 */
export enum TakeTemperature {
  NONE = 0,
  COLD_OR_MILD = 1,
  HOT_OR_MILD = 2
}

export class TakeTimeSchedule {
  bands: TakeBand[];
  temperature: TakeTemperature;

  constructor(bands: TakeBand[], temperature: TakeTemperature) {
    this.bands = bands;
    this.temperature = temperature;
  }
}

/** 上次成功抓取的结果最多沿用 7 天，超过就当作从未抓取过。 */
export const TAKE_TIME_VALID_MILLIS: number = 7 * 24 * 60 * 60 * 1000;
/** 每天只在 01:00–05:00 之间挑一个随机时刻同步。 */
export const SYNC_WINDOW_START_MINUTE: number = 60;
export const SYNC_WINDOW_END_MINUTE: number = 300;
/** 当天同步失败后每个小时重试一次。 */
export const RETRY_MILLIS: number = 60 * 60 * 1000;

const TIME_ANCHOR: string = 'Take Time';
/** 「Take Time」后面这段文字里就是时间段与温度要求。 */
const WINDOW_CHARS: number = 400;
const RANGE_REGEX: RegExp = /(\d{1,2}):(\d{2})\s*[-~–—至]\s*(\d{1,2}):(\d{2})/g;

function floorMod(value: number, modulus: number): number {
  return ((value % modulus) + modulus) % modulus;
}

export class TakeTimeLogic {
  /**
   * 从页面里解析关键时间。
   *
   * 页面形如：
   * `服用時間 Take Time : 15:00-17:00　20:00-22:00　10:00-12:00　(凍或溫 Cold or Mild)`
   * 标签可能被 `<br>`／`&nbsp;` 拆开，所以先去标签再在「Take Time」附近取一段窗口匹配。
   */
  static parse(html: string): TakeTimeSchedule | null {
    const text: string = html
      .replace(/<[^>]*>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&#160;/g, ' ')
      .replace(/&amp;/g, '&');
    const anchor: number = text.toLowerCase().indexOf(TIME_ANCHOR.toLowerCase());
    const source: string =
      anchor >= 0 ? text.substring(anchor, Math.min(text.length, anchor + WINDOW_CHARS)) : text;

    const bands: TakeBand[] = [];
    RANGE_REGEX.lastIndex = 0;
    let match: RegExpExecArray | null = RANGE_REGEX.exec(source);
    while (match !== null) {
      const start: number = TakeTimeLogic.minuteOf(Number.parseInt(match[1]), Number.parseInt(match[2]));
      const end: number = TakeTimeLogic.minuteOf(Number.parseInt(match[3]), Number.parseInt(match[4]));
      if (start >= 0 && end >= 0 && start !== end) {
        const band: TakeBand = new TakeBand(start, end);
        const length: number = band.lengthMinutes();
        if (length >= 1 && length <= MINUTES_PER_DAY - 1) {
          bands.push(band);
        }
      }
      match = RANGE_REGEX.exec(source);
    }
    if (bands.length === 0) {
      return null;
    }
    return new TakeTimeSchedule(bands, TakeTimeLogic.parseTemperature(source));
  }

  /** 只认英文标记：Cold 用绿色，Hot 用红色；两者都没有就当作没标注。 */
  static parseTemperature(text: string): TakeTemperature {
    const lower: string = text.toLowerCase();
    if (lower.indexOf('cold or mild') >= 0) {
      return TakeTemperature.COLD_OR_MILD;
    }
    if (lower.indexOf('hot or mild') >= 0) {
      return TakeTemperature.HOT_OR_MILD;
    }
    return TakeTemperature.NONE;
  }

  private static minuteOf(hour: number, minute: number): number {
    if (isNaN(hour) || isNaN(minute)) {
      return -1;
    }
    if (hour < 0 || hour > 24 || minute < 0 || minute > 59) {
      return -1;
    }
    return floorMod(hour * 60 + minute, MINUTES_PER_DAY);
  }

  static temperatureToKey(temperature: TakeTemperature): string {
    if (temperature === TakeTemperature.COLD_OR_MILD) {
      return 'cold';
    }
    if (temperature === TakeTemperature.HOT_OR_MILD) {
      return 'hot';
    }
    return '';
  }

  static temperatureFromKey(raw: string): TakeTemperature {
    if (raw === 'cold') {
      return TakeTemperature.COLD_OR_MILD;
    }
    if (raw === 'hot') {
      return TakeTemperature.HOT_OR_MILD;
    }
    return TakeTemperature.NONE;
  }

  static encodeBands(bands: TakeBand[]): string {
    return bands.map((band: TakeBand): string => `${band.startMinute}-${band.endMinute}`).join(',');
  }

  static decodeBands(encoded: string): TakeBand[] {
    const result: TakeBand[] = [];
    if (encoded.length === 0) {
      return result;
    }
    for (const part of encoded.split(',')) {
      const pair: string[] = part.split('-');
      if (pair.length !== 2) {
        continue;
      }
      const start: number = Number.parseInt(pair[0]);
      const end: number = Number.parseInt(pair[1]);
      if (isNaN(start) || isNaN(end)) {
        continue;
      }
      result.push(new TakeBand(start, end));
    }
    return result;
  }

  /**
   * 今天是否该联网同步：今天已成功就跳过；目标时刻没到也跳过；
   * 失败后每小时重试一次，直到成功。
   */
  static shouldSync(
    nowMillis: number,
    targetMillis: number,
    today: string,
    lastSuccessDay: string,
    lastAttemptMillis: number
  ): boolean {
    if (lastSuccessDay === today) {
      return false;
    }
    if (nowMillis < targetMillis) {
      return false;
    }
    const sinceAttempt: number = nowMillis - lastAttemptMillis;
    return !(sinceAttempt >= 0 && sinceAttempt <= RETRY_MILLIS);
  }

  /** 当天 00:00 之后 offsetMinutes 分钟的时刻。 */
  static targetMillis(dayStartMillis: number, offsetMinutes: number): number {
    return dayStartMillis + offsetMinutes * 60 * 1000;
  }

  /** 随机偏移始终落在 01:00–05:00 之间（含 01:00，不含 05:00）。 */
  static isInsideSyncWindow(offsetMinutes: number): boolean {
    return offsetMinutes >= SYNC_WINDOW_START_MINUTE && offsetMinutes < SYNC_WINDOW_END_MINUTE;
  }

  static isFresh(ageMillis: number): boolean {
    return ageMillis >= 0 && ageMillis <= TAKE_TIME_VALID_MILLIS;
  }

  /**
   * 把关键时间铺成一条 0:00–24:00 的时间轴：连续归属于同一段的分钟合并成一段，
   * 空档单独占一段。跨午夜的段自然被拆成首尾两段。
   * 卡片用 Row + layoutWeight 按比例摆放色条。
   */
  static axisSegments(bands: TakeBand[]): AxisSegment[] {
    const segments: AxisSegment[] = [];
    if (bands.length === 0) {
      return segments;
    }
    let currentIndex: number = -1;
    let currentStart: number = 0;
    for (let minute = 0; minute < MINUTES_PER_DAY; minute++) {
      let owner: number = -1;
      for (let index = 0; index < bands.length; index++) {
        if (bands[index].contains(minute)) {
          owner = index;
          break;
        }
      }
      if (minute === 0) {
        currentIndex = owner;
        currentStart = 0;
        continue;
      }
      if (owner !== currentIndex) {
        segments.push(new AxisSegment(currentStart, minute - currentStart, currentIndex));
        currentIndex = owner;
        currentStart = minute;
      }
    }
    segments.push(new AxisSegment(currentStart, MINUTES_PER_DAY - currentStart, currentIndex));
    return segments;
  }
}
