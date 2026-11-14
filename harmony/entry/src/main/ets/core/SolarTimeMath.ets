/**
 * 真太阳时计算。
 *
 * 真太阳时 = 平太阳时 + 均时差，其中
 *   平太阳时(小时) = UTC 时刻 + 经度 / 15
 *   均时差 = 由地球轨道偏心率与黄赤交角引起的日差，采用 NOAA Solar Calculator 的近似公式，
 *            精度约 ±0.5 分钟，足够民用太阳时显示。
 *
 * 时间一律用「UTC 毫秒时间戳」表示，避免平台时区差异。
 */

const RAD: number = Math.PI / 180.0;
const DEG: number = 180.0 / Math.PI;
const SECONDS_PER_DAY: number = 86400.0;
const MS_PER_DAY: number = 86400000.0;

/** 太阳上中天时的天顶角修正（含大气折射与太阳视半径）。 */
const SUNRISE_ZENITH_DEGREES: number = 90.833;

export enum PolarState {
  NORMAL = 0,
  MIDNIGHT_SUN = 1,
  POLAR_NIGHT = 2
}

export class SolarPosition {
  /** 均时差：真太阳时减去平太阳时，单位秒。为正值表示日晷快于钟表。 */
  equationOfTimeSeconds: number;
  /** 太阳赤纬，单位度。 */
  declinationDegrees: number;

  constructor(equationOfTimeSeconds: number, declinationDegrees: number) {
    this.equationOfTimeSeconds = equationOfTimeSeconds;
    this.declinationDegrees = declinationDegrees;
  }
}

export class SunTimes {
  /** 日出 / 日落 / 上中天的 UTC 毫秒；极昼极夜时日出日落为 -1。 */
  sunriseMillis: number;
  sunsetMillis: number;
  solarNoonMillis: number;
  polar: PolarState;

  constructor(sunriseMillis: number, sunsetMillis: number, solarNoonMillis: number, polar: PolarState) {
    this.sunriseMillis = sunriseMillis;
    this.sunsetMillis = sunsetMillis;
    this.solarNoonMillis = solarNoonMillis;
    this.polar = polar;
  }

  hasSunrise(): boolean {
    return this.sunriseMillis >= 0;
  }

  hasSunset(): boolean {
    return this.sunsetMillis >= 0;
  }
}

/** 北京时间的年月日。 */
export class BeijingDate {
  year: number;
  month: number;
  day: number;

  constructor(year: number, month: number, day: number) {
    this.year = year;
    this.month = month;
    this.day = day;
  }

  key(): string {
    return `${this.year}-${pad2(this.month)}-${pad2(this.day)}`;
  }
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function normalizeDegrees(value: number): number {
  return ((value % 360.0) + 360.0) % 360.0;
}

function normalizeSeconds(value: number): number {
  return ((value % SECONDS_PER_DAY) + SECONDS_PER_DAY) % SECONDS_PER_DAY;
}

export class SolarTimeMath {
  /** 北京时间所在的东八区经度。 */
  static readonly BEIJING_LONGITUDE: number = 120.0;
  /** 北京时间（东八区固定偏移）的毫秒数。 */
  static readonly BEIJING_OFFSET_MILLIS: number = 8 * 3600 * 1000;
  static readonly BEIJING_OFFSET_SECONDS: number = 8 * 3600;

  /** 由儒略世纪数推求太阳位置（均时差与赤纬）。 */
  static solarPosition(epochMillis: number): SolarPosition {
    const jd: number = epochMillis / MS_PER_DAY + 2440587.5;
    const t: number = (jd - 2451545.0) / 36525.0;

    const meanLongitude: number = normalizeDegrees(280.46646 + t * (36000.76983 + t * 0.0003032));
    const meanAnomaly: number = normalizeDegrees(357.52911 + t * (35999.05029 - 0.0001537 * t));
    const eccentricity: number = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    const omega: number = 125.04 - 1934.136 * t;

    const meanObliquity: number =
      23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0;
    const obliquity: number = meanObliquity + 0.00256 * Math.cos(omega * RAD);

    const y: number = Math.pow(Math.tan(obliquity * RAD / 2), 2);
    const l0: number = meanLongitude * RAD;
    const m: number = meanAnomaly * RAD;
    // 括号内的量以弧度表示；乘以 DEG 得「度」，再乘 4 分/度、60 秒/分即为秒。
    const equationOfTimeRadians: number =
      y * Math.sin(2 * l0) -
      2 * eccentricity * Math.sin(m) +
      4 * eccentricity * y * Math.sin(m) * Math.cos(2 * l0) -
      0.5 * y * y * Math.sin(4 * l0) -
      1.25 * eccentricity * eccentricity * Math.sin(2 * m);

    const equationOfCenter: number =
      Math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      Math.sin(2 * m) * (0.019993 - 0.000101 * t) +
      Math.sin(3 * m) * 0.000289;
    const apparentLongitude: number = meanLongitude + equationOfCenter - 0.00569 - 0.00478 * Math.sin(omega * RAD);
    const declination: number = Math.asin(Math.sin(obliquity * RAD) * Math.sin(apparentLongitude * RAD)) * DEG;

    return new SolarPosition(equationOfTimeRadians * 240.0 * DEG, declination);
  }

  /** 某瞬间在给定经度上的真太阳时，返回当天的秒数 [0, 86400)。 */
  static trueSolarSecondsOfDay(epochMillis: number, longitude: number): number {
    const utcMillisOfDay: number = ((epochMillis % MS_PER_DAY) + MS_PER_DAY) % MS_PER_DAY;
    const utcSeconds: number = utcMillisOfDay / 1000.0;
    const equationOfTime: number = SolarTimeMath.solarPosition(epochMillis).equationOfTimeSeconds;
    return normalizeSeconds(utcSeconds + longitude * 240.0 + equationOfTime);
  }

  /** 北京时间当天的秒数。 */
  static beijingSecondsOfDay(epochMillis: number): number {
    return normalizeSeconds((epochMillis + SolarTimeMath.BEIJING_OFFSET_MILLIS) / 1000.0);
  }

  /** 真太阳时相对北京时间的偏差，单位秒，范围 (-43200, 43200]。正值表示真太阳时走得快。 */
  static offsetFromBeijingSeconds(epochMillis: number, longitude: number): number {
    const delta: number =
      SolarTimeMath.trueSolarSecondsOfDay(epochMillis, longitude) - SolarTimeMath.beijingSecondsOfDay(epochMillis);
    let normalized: number = (delta + SECONDS_PER_DAY * 1.5) % SECONDS_PER_DAY;
    if (normalized <= 0) {
      normalized += SECONDS_PER_DAY;
    }
    return normalized - SECONDS_PER_DAY / 2;
  }

  /** 经度修正：当地经度相对东经 120° 的时差，单位秒。 */
  static longitudeOffsetSeconds(longitude: number): number {
    return (longitude - SolarTimeMath.BEIJING_LONGITUDE) * 240.0;
  }

  /**
   * 观测点所在地的**标准时区偏移**（相对 UTC，秒）。
   * 中国全境统一 +8（含港澳台与新疆、西藏）；境外按经度每 15° 取整，限制在 UTC-12..+14。
   */
  /** 粗略判断是否在中国境内（含港澳台），用于时区兜底与逆地理编码分流。 */
  static isInChinaBbox(latitude: number, longitude: number): boolean {
    return longitude >= 73 && longitude <= 135 && latitude >= 18 && latitude <= 54;
  }

  static standardZoneOffsetSeconds(latitude: number, longitude: number): number {
    const inChina: boolean = SolarTimeMath.isInChinaBbox(latitude, longitude);
    if (inChina) {
      return SolarTimeMath.BEIJING_OFFSET_SECONDS;
    }
    const hours: number = Math.round(longitude / 15.0);
    const clamped: number = Math.min(14, Math.max(-12, hours));
    return clamped * 3600;
  }

  /**
   * 当地真太阳时相对 **UTC** 的偏移，单位秒 = 经度 × 4 分/度 + 均时差。
   * 「系统时刻 + 该偏移」即以真太阳时读出的时刻（桌面卡片用它逐秒显示）。
   */
  static trueSolarOffsetSeconds(epochMillis: number, longitude: number): number {
    return longitude * 240.0 + SolarTimeMath.solarPosition(epochMillis).equationOfTimeSeconds;
  }

  /** 太阳高度角，单位度（不含大气折射修正）。 */
  static solarAltitudeDegrees(epochMillis: number, latitude: number, longitude: number): number {
    const position: SolarPosition = SolarTimeMath.solarPosition(epochMillis);
    const hourAngle: number = (SolarTimeMath.trueSolarSecondsOfDay(epochMillis, longitude) / 3600.0 - 12.0) * 15.0 * RAD;
    const lat: number = latitude * RAD;
    const dec: number = position.declinationDegrees * RAD;
    const sinAltitude: number = Math.sin(lat) * Math.sin(dec) + Math.cos(lat) * Math.cos(dec) * Math.cos(hourAngle);
    return Math.asin(Math.max(-1.0, Math.min(1.0, sinAltitude))) * DEG;
  }

  /** 计算某日（以北京日期为准）的日出、日落与上中天时刻。 */
  static sunTimes(date: BeijingDate, latitude: number, longitude: number): SunTimes {
    const midnightUtc: number = Date.UTC(date.year, date.month - 1, date.day);
    const reference: number = midnightUtc + 12 * 3600 * 1000;
    const position: SolarPosition = SolarTimeMath.solarPosition(reference);
    const lat: number = latitude * RAD;
    const dec: number = position.declinationDegrees * RAD;
    const equationOfTimeMinutes: number = position.equationOfTimeSeconds / 60.0;

    const solarNoonMinutes: number = 720.0 - 4.0 * longitude - equationOfTimeMinutes;
    const solarNoon: number = midnightUtc + Math.round(solarNoonMinutes * 60) * 1000;

    const cosHourAngle: number =
      Math.cos(SUNRISE_ZENITH_DEGREES * RAD) / (Math.cos(lat) * Math.cos(dec)) - Math.tan(lat) * Math.tan(dec);
    if (cosHourAngle > 1.0 || cosHourAngle < -1.0) {
      const polar: PolarState = cosHourAngle > 1.0 ? PolarState.POLAR_NIGHT : PolarState.MIDNIGHT_SUN;
      return new SunTimes(-1, -1, solarNoon, polar);
    }

    const hourAngleDegrees: number = Math.acos(cosHourAngle) * DEG;
    const sunriseMinutes: number = 720.0 - 4.0 * (longitude + hourAngleDegrees) - equationOfTimeMinutes;
    const sunsetMinutes: number = 720.0 + 4.0 * (hourAngleDegrees - longitude) - equationOfTimeMinutes;
    return new SunTimes(
      midnightUtc + Math.round(sunriseMinutes * 60) * 1000,
      midnightUtc + Math.round(sunsetMinutes * 60) * 1000,
      solarNoon,
      PolarState.NORMAL
    );
  }

  /** 时间戳对应的北京日期。 */
  static beijingDate(epochMillis: number): BeijingDate {
    const date: Date = new Date(epochMillis + SolarTimeMath.BEIJING_OFFSET_MILLIS);
    return new BeijingDate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
  }

  /** 时间戳对应的北京时间当天的秒数，取整到秒。 */
  static beijingSecondsOfDayFloor(epochMillis: number): number {
    return Math.floor(SolarTimeMath.beijingSecondsOfDay(epochMillis));
  }

  /** 真太阳时当天的秒数，取整到秒。 */
  static trueSolarSecondsOfDayFloor(epochMillis: number, longitude: number): number {
    return Math.floor(SolarTimeMath.trueSolarSecondsOfDay(epochMillis, longitude));
  }
}
