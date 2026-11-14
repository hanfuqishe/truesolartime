/**
 * 当前天气（气温 + WMO 天气码）的解析与分类，数据来自 Open-Meteo：免费、无需 Key、全球可用。
 *
 * 数据来源需要在界面上标注：Open-Meteo（CC BY 4.0）。
 * 这里只有纯逻辑：请求与缓存放在 services/WeatherService.ets。
 */

export enum WeatherCondition {
  CLEAR = 0,
  PARTLY_CLOUDY = 1,
  OVERCAST = 2,
  FOG = 3,
  DRIZZLE = 4,
  RAIN = 5,
  HEAVY_RAIN = 6,
  SHOWERS = 7,
  SNOW = 8,
  HEAVY_SNOW = 9,
  THUNDER = 10
}

export class WeatherSnapshot {
  temperatureC: number;
  code: number;

  constructor(temperatureC: number, code: number) {
    this.temperatureC = temperatureC;
    this.code = code;
  }
}

/** 某个整点的小时预报。 */
export class HourPoint {
  epochSeconds: number;
  temperatureC: number;
  code: number;

  constructor(epochSeconds: number, temperatureC: number, code: number) {
    this.epochSeconds = epochSeconds;
    this.temperatureC = temperatureC;
    this.code = code;
  }
}

function floorMod(value: number, modulus: number): number {
  return ((value % modulus) + modulus) % modulus;
}

export class WeatherLogic {
  /** 取数的刷新间隔 30 分钟；位置移动超过 5 km 也重新取数。 */
  static readonly TTL_MILLIS: number = 30 * 60 * 1000;
  /** 显示用的保留时限（与小时预报一致）：刷新失败时继续显示最近一次取到的数据。 */
  static readonly HOURLY_MAX_AGE_MILLIS: number = 24 * 60 * 60 * 1000;
  /** 取数失败后的重试间隔：成功是 30 分钟一拍，失败时 5 分钟就再试一次。 */
  static readonly RETRY_AFTER_FAILURE_MILLIS: number = 5 * 60 * 1000;
  static readonly MOVE_THRESHOLD_KM: number = 5.0;
  /** 没有有效天气时天气位显示的占位符。 */
  static readonly PLACEHOLDER: string = '--';

  static buildUrl(latitude: number, longitude: number): string {
    return 'https://api.open-meteo.com/v1/forecast' +
      `?latitude=${latitude.toFixed(4)}&longitude=${longitude.toFixed(4)}` +
      '&current=temperature_2m,weather_code' +
      '&hourly=temperature_2m,weather_code&forecast_days=2&past_days=1&timezone=UTC';
  }

  /** 解析当前天气；结构不对时返回 null。 */
  static parse(json: string): WeatherSnapshot | null {
    let root: Record<string, Object>;
    try {
      root = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return null;
    }
    const current: Object | undefined = root['current'];
    if (current === undefined || current === null) {
      return null;
    }
    const fields: Record<string, Object> = current as Record<string, Object>;
    const temperature: Object | undefined = fields['temperature_2m'];
    if (temperature === undefined || temperature === null) {
      return null;
    }
    const code: Object | undefined = fields['weather_code'];
    return new WeatherSnapshot(Math.round(Number(temperature)), code === undefined ? 0 : Number(code));
  }

  /** 解析 hourly 序列（请求时指定 timezone=UTC，时间因此可直接当 UTC 解析）。 */
  static parseHourly(json: string): HourPoint[] {
    const points: HourPoint[] = [];
    let root: Record<string, Object>;
    try {
      root = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return points;
    }
    const hourly: Object | undefined = root['hourly'];
    if (hourly === undefined || hourly === null) {
      return points;
    }
    const fields: Record<string, Object> = hourly as Record<string, Object>;
    const times: Object[] = fields['time'] as Object[];
    const temps: Object[] = fields['temperature_2m'] as Object[];
    const codes: Object[] = fields['weather_code'] as Object[];
    if (!Array.isArray(times) || !Array.isArray(temps)) {
      return points;
    }
    const count: number = Math.min(times.length, temps.length);
    for (let index = 0; index < count; index++) {
      const epoch: number = WeatherLogic.parseUtcHour(times[index] as string);
      if (epoch < 0) {
        continue;
      }
      const temperature: number = Number(temps[index]);
      if (isNaN(temperature)) {
        continue;
      }
      const code: number = Array.isArray(codes) && codes.length > index ? Number(codes[index]) : 0;
      points.push(new HourPoint(epoch, Math.round(temperature), code));
    }
    return points;
  }

  /** "2026-11-02T04:00" → UTC 秒；格式不对返回 -1。 */
  static parseUtcHour(text: string): number {
    const match: RegExpMatchArray | null = text.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
    if (match === null) {
      return -1;
    }
    const millis: number = Date.UTC(
      Number.parseInt(match[1]),
      Number.parseInt(match[2]) - 1,
      Number.parseInt(match[3]),
      Number.parseInt(match[4]),
      Number.parseInt(match[5])
    );
    return Math.floor(millis / 1000);
  }

  /**
   * 卡片要显示的时刻：从当前所在的 stepHours 小时块开始，按步长取 count 个（本地时区对齐）。
   * 返回 UTC 秒，可直接与 HourPoint.epochSeconds 对应。
   */
  static slots(nowEpochSeconds: number, zoneOffsetSeconds: number, count: number, stepHours: number): number[] {
    const step: number = stepHours * 3600;
    const local: number = nowEpochSeconds + zoneOffsetSeconds;
    const blockStart: number = local - floorMod(local, step);
    const result: number[] = [];
    for (let index = 0; index < count; index++) {
      result.push(blockStart + index * step - zoneOffsetSeconds);
    }
    return result;
  }

  static encodeHourly(points: HourPoint[]): string {
    return points.map((point: HourPoint): string => `${point.epochSeconds},${point.temperatureC},${point.code}`).join(';');
  }

  static decodeHourly(encoded: string): HourPoint[] {
    const points: HourPoint[] = [];
    if (encoded.length === 0) {
      return points;
    }
    for (const item of encoded.split(';')) {
      const parts: string[] = item.split(',');
      if (parts.length !== 3) {
        continue;
      }
      const epoch: number = Number.parseInt(parts[0]);
      const temperature: number = Number.parseInt(parts[1]);
      if (isNaN(epoch) || isNaN(temperature)) {
        continue;
      }
      const code: number = Number.parseInt(parts[2]);
      points.push(new HourPoint(epoch, temperature, isNaN(code) ? 0 : code));
    }
    return points;
  }

  /** 本地某一天的最高/最低温度，返回 [最低, 最高]；没覆盖这一天返回 null。 */
  static temperatureRange(
    points: HourPoint[],
    dayStartMillis: number,
    dayEndMillis: number,
    zoneOffsetMillis: number
  ): number[] | null {
    let min: number = Number.MAX_SAFE_INTEGER;
    let max: number = Number.MIN_SAFE_INTEGER;
    let found: boolean = false;
    for (const point of points) {
      const local: number = point.epochSeconds * 1000 + zoneOffsetMillis;
      if (local < dayStartMillis || local >= dayEndMillis) {
        continue;
      }
      found = true;
      min = Math.min(min, point.temperatureC);
      max = Math.max(max, point.temperatureC);
    }
    return found ? [min, max] : null;
  }

  /**
   * 缓存是否该刷新。
   *
   * `sinceAttemptMillis` 是距上一次**尝试**取数的时长：过期后按 5 分钟节流，
   * 免得取数失败时每次回到前台都打一次网络；成功取到后尝试时刻会一起更新。
   */
  static shouldRefresh(ageMillis: number, movedKm: number, sinceAttemptMillis: number): boolean {
    if (movedKm > WeatherLogic.MOVE_THRESHOLD_KM) {
      return true;
    }
    if (ageMillis >= 0 && ageMillis <= WeatherLogic.TTL_MILLIS) {
      return false;
    }
    return !(sinceAttemptMillis >= 0 && sinceAttemptMillis <= WeatherLogic.RETRY_AFTER_FAILURE_MILLIS);
  }

  /**
   * 未来 count 个小时的预报文案，例如「14时 多云 21°」/ "2:00 PM? "。
   * 槽位按本地整点对齐，找不到对应数据的小时直接跳过。
   */
  static forecastLabels(
    points: HourPoint[],
    nowEpochSeconds: number,
    zoneOffsetSeconds: number,
    count: number,
    language: string
  ): string[] {
    const slots: number[] = WeatherLogic.slots(nowEpochSeconds, zoneOffsetSeconds, count, 1);
    const labels: string[] = [];
    for (const slot of slots) {
      let match: HourPoint | null = null;
      for (const point of points) {
        if (point.epochSeconds === slot) {
          match = point;
          break;
        }
      }
      if (match === null) {
        continue;
      }
      const hour: number = new Date((slot + zoneOffsetSeconds) * 1000).getUTCHours();
      const name: string = WeatherLogic.conditionName(WeatherLogic.conditionOf(match.code), language);
      labels.push(language.startsWith('zh')
        ? `${hour}时 ${name} ${match.temperatureC}°`
        : `${hour}:00 ${name} ${match.temperatureC}°`);
    }
    return labels;
  }

  /** WMO 天气码 → 分类。 */
  static conditionOf(code: number): WeatherCondition {
    switch (code) {
      case 0:
        return WeatherCondition.CLEAR;
      case 1:
      case 2:
        return WeatherCondition.PARTLY_CLOUDY;
      case 3:
        return WeatherCondition.OVERCAST;
      case 45:
      case 48:
        return WeatherCondition.FOG;
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return WeatherCondition.DRIZZLE;
      case 61:
      case 63:
      case 66:
      case 67:
        return WeatherCondition.RAIN;
      case 65:
      case 82:
        return WeatherCondition.HEAVY_RAIN;
      case 80:
      case 81:
        return WeatherCondition.SHOWERS;
      case 71:
      case 73:
      case 77:
      case 85:
      case 86:
        return WeatherCondition.SNOW;
      case 75:
        return WeatherCondition.HEAVY_SNOW;
      case 95:
      case 96:
      case 99:
        return WeatherCondition.THUNDER;
      default:
        return WeatherCondition.OVERCAST;
    }
  }

  /** 天气码 → 可读文案。 */
  static conditionLabel(code: number, language: string): string {
    return WeatherLogic.conditionName(WeatherLogic.conditionOf(code), language);
  }

  /**
   * 天气码 → 图标名（对应 resources/base/media/wx_*.svg，由 Tools/gen-wx-icons.py 从
   * Android 的 VectorDrawable 转出）。卡片与主界面共用，避免两处各写一套映射。
   */
  static iconKey(code: number, isDay: boolean): string {
    switch (WeatherLogic.conditionOf(code)) {
      case WeatherCondition.CLEAR:
        return isDay ? 'clear_day' : 'clear_night';
      case WeatherCondition.PARTLY_CLOUDY:
        return isDay ? 'partly_day' : 'partly_night';
      case WeatherCondition.OVERCAST:
        return 'overcast';
      case WeatherCondition.FOG:
        return 'fog';
      case WeatherCondition.DRIZZLE:
        return 'drizzle';
      case WeatherCondition.RAIN:
        return 'rain';
      case WeatherCondition.HEAVY_RAIN:
        return 'heavy_rain';
      case WeatherCondition.SHOWERS:
        return 'showers';
      case WeatherCondition.SNOW:
        return 'snow';
      case WeatherCondition.HEAVY_SNOW:
        return 'heavy_snow';
      case WeatherCondition.THUNDER:
        return 'thunder';
      default:
        return 'unknown';
    }
  }

  static conditionName(condition: WeatherCondition, language: string): string {
    const zh: string[] = ['晴', '多云', '阴', '雾', '毛毛雨', '小雨', '大雨', '阵雨', '雪', '大雪', '雷雨'];
    const en: string[] = [
      'Clear', 'Partly cloudy', 'Overcast', 'Fog', 'Drizzle', 'Rain', 'Heavy rain', 'Showers', 'Snow', 'Heavy snow',
      'Thunder'
    ];
    const table: string[] = language.startsWith('zh') ? zh : en;
    return table[condition];
  }
}
