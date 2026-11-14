/**
 * 某一瞬间、某一地点的完整太阳时快照，界面只消费这个对象。
 * 缺失的时刻统一用 -1 秒表示（例如极昼没有日出）。
 */

import { BeijingDate, PolarState, SolarPosition, SolarTimeMath, SunTimes } from './SolarTimeMath';
import { Shichen } from './Shichen';

const DAY_SECONDS: number = 86400.0;

export class SolarSnapshot {
  /** 真太阳时当天的秒数，0..86399。 */
  trueSolarSeconds: number;
  /** 北京时间当天的秒数，0..86399。 */
  beijingSeconds: number;
  beijingDate: BeijingDate;
  /** 真太阳时比北京时间快多少秒，可正可负。 */
  offsetSeconds: number;
  longitudeOffsetSeconds: number;
  equationOfTimeSeconds: number;
  shichenIndex: number;
  shichenName: string;
  shichenRange: string;
  shichenHalf: string;
  /** 时正（后一小时）为 true，时初为 false。 */
  secondHalf: boolean;
  shichenQuarter: number;
  secondsToNextShichen: number;
  sunriseTrueSolarSeconds: number;
  sunsetTrueSolarSeconds: number;
  solarNoonTrueSolarSeconds: number;
  sunriseBeijingSeconds: number;
  sunsetBeijingSeconds: number;
  solarNoonBeijingSeconds: number;
  /** 观测点所在地标准时区相对 UTC 的偏移（秒）。 */
  localOffsetSeconds: number;
  /** 以下三个为「当地时间」口径，供界面展示日出/上中天/日落。 */
  sunriseLocalSeconds: number;
  sunsetLocalSeconds: number;
  solarNoonLocalSeconds: number;
  daylightSeconds: number;
  polar: PolarState;
  altitudeDegrees: number;

  constructor() {
    this.trueSolarSeconds = 0;
    this.beijingSeconds = 0;
    this.beijingDate = new BeijingDate(1970, 1, 1);
    this.offsetSeconds = 0;
    this.longitudeOffsetSeconds = 0;
    this.equationOfTimeSeconds = 0;
    this.shichenIndex = 0;
    this.shichenName = '';
    this.shichenRange = '';
    this.shichenHalf = '';
    this.secondHalf = false;
    this.shichenQuarter = 1;
    this.secondsToNextShichen = 0;
    this.sunriseTrueSolarSeconds = -1;
    this.sunsetTrueSolarSeconds = -1;
    this.solarNoonTrueSolarSeconds = -1;
    this.sunriseBeijingSeconds = -1;
    this.sunsetBeijingSeconds = -1;
    this.solarNoonBeijingSeconds = -1;
    this.localOffsetSeconds = SolarTimeMath.BEIJING_OFFSET_SECONDS;
    this.sunriseLocalSeconds = -1;
    this.sunsetLocalSeconds = -1;
    this.solarNoonLocalSeconds = -1;
    this.daylightSeconds = -1;
    this.polar = PolarState.NORMAL;
    this.altitudeDegrees = 0;
  }

  isDay(): boolean {
    return this.altitudeDegrees > -0.833;
  }

  hasSunrise(): boolean {
    return this.sunriseTrueSolarSeconds >= 0;
  }

  hasSunset(): boolean {
    return this.sunsetTrueSolarSeconds >= 0;
  }
}

export class SolarTimeSnapshot {
  static compute(epochMillis: number, latitude: number, longitude: number, language: string,
      zoneOffsetSeconds: number = -1): SolarSnapshot {
    const snapshot: SolarSnapshot = new SolarSnapshot();
    const trueSolarSeconds: number = SolarTimeMath.trueSolarSecondsOfDay(epochMillis, longitude);
    const position: SolarPosition = SolarTimeMath.solarPosition(epochMillis);
    const date: BeijingDate = SolarTimeMath.beijingDate(epochMillis);
    const sunTimes: SunTimes = SolarTimeMath.sunTimes(date, latitude, longitude);

    snapshot.trueSolarSeconds = Math.floor(trueSolarSeconds) % 86400;
    snapshot.beijingSeconds = Math.floor(SolarTimeMath.beijingSecondsOfDay(epochMillis)) % 86400;
    snapshot.beijingDate = date;
    snapshot.offsetSeconds = SolarTimeMath.offsetFromBeijingSeconds(epochMillis, longitude);
    snapshot.longitudeOffsetSeconds = SolarTimeMath.longitudeOffsetSeconds(longitude);
    snapshot.equationOfTimeSeconds = position.equationOfTimeSeconds;

    const shichenIndex: number = Shichen.indexOf(trueSolarSeconds);
    snapshot.shichenIndex = shichenIndex;
    snapshot.shichenName = Shichen.displayName(shichenIndex, language);
    snapshot.shichenRange = Shichen.rangeText(shichenIndex);
    snapshot.secondHalf = Shichen.halfLabel(trueSolarSeconds) === '正';
    snapshot.shichenHalf = language.startsWith('zh') ? Shichen.halfLabel(trueSolarSeconds) : Shichen.halfLabelEn(trueSolarSeconds);
    snapshot.shichenQuarter = Shichen.quarterOfHalf(trueSolarSeconds);
    snapshot.secondsToNextShichen = Math.round(Shichen.secondsToNextShichen(trueSolarSeconds));

    if (sunTimes.hasSunrise()) {
      snapshot.sunriseTrueSolarSeconds =
        Math.round(SolarTimeMath.trueSolarSecondsOfDay(sunTimes.sunriseMillis, longitude)) % 86400;
      snapshot.sunriseBeijingSeconds = Math.floor(SolarTimeMath.beijingSecondsOfDay(sunTimes.sunriseMillis)) % 86400;
    }
    if (sunTimes.hasSunset()) {
      snapshot.sunsetTrueSolarSeconds =
        Math.round(SolarTimeMath.trueSolarSecondsOfDay(sunTimes.sunsetMillis, longitude)) % 86400;
      snapshot.sunsetBeijingSeconds = Math.floor(SolarTimeMath.beijingSecondsOfDay(sunTimes.sunsetMillis)) % 86400;
    }
    snapshot.solarNoonTrueSolarSeconds =
      Math.round(SolarTimeMath.trueSolarSecondsOfDay(sunTimes.solarNoonMillis, longitude)) % 86400;
    snapshot.solarNoonBeijingSeconds = Math.floor(SolarTimeMath.beijingSecondsOfDay(sunTimes.solarNoonMillis)) % 86400;

    if (sunTimes.hasSunrise() && sunTimes.hasSunset()) {
      snapshot.daylightSeconds = Math.round((sunTimes.sunsetMillis - sunTimes.sunriseMillis) / 1000);
    }
    // 当地时间 = UTC 时刻 + 当地时区偏移；北京时间口径按 +8 换算，故先减去 +8 再加当地偏移。
    const zoneOffset: number = zoneOffsetSeconds >= 0
      ? zoneOffsetSeconds
      : SolarTimeMath.standardZoneOffsetSeconds(latitude, longitude);
    snapshot.localOffsetSeconds = zoneOffset;
    const shiftSeconds: number = zoneOffset - SolarTimeMath.BEIJING_OFFSET_SECONDS;
    if (snapshot.sunriseBeijingSeconds >= 0) {
      snapshot.sunriseLocalSeconds = SolarTimeSnapshot.wrapDay(snapshot.sunriseBeijingSeconds + shiftSeconds);
    }
    if (snapshot.sunsetBeijingSeconds >= 0) {
      snapshot.sunsetLocalSeconds = SolarTimeSnapshot.wrapDay(snapshot.sunsetBeijingSeconds + shiftSeconds);
    }
    snapshot.solarNoonLocalSeconds = SolarTimeSnapshot.wrapDay(snapshot.solarNoonBeijingSeconds + shiftSeconds);
    snapshot.polar = sunTimes.polar;
    snapshot.altitudeDegrees = SolarTimeMath.solarAltitudeDegrees(epochMillis, latitude, longitude);
    return snapshot;
  }

  /** 把秒数归一到 0..86399。 */
  private static wrapDay(seconds: number): number {
    return ((Math.round(seconds) % 86400) + 86400) % 86400;
  }

  /** 当前时刻是否落在一段关键时间里（按真太阳时当天分钟数判断，供界面着色）。 */
  static solarMinuteOfDay(epochMillis: number, longitude: number): number {
    return SolarTimeMath.trueSolarSecondsOfDay(epochMillis, longitude) / 60.0;
  }

  /** 供测试与调试：真太阳时秒数重建（系统时刻 + 偏移）。 */
  static rebuildFromOffset(epochMillis: number, longitude: number): number {
    const utcSecondsOfDay: number = ((epochMillis % (DAY_SECONDS * 1000)) + DAY_SECONDS * 1000) % (DAY_SECONDS * 1000) / 1000.0;
    const offset: number = SolarTimeMath.trueSolarOffsetSeconds(epochMillis, longitude);
    return (((utcSecondsOfDay + offset) % DAY_SECONDS) + DAY_SECONDS) % DAY_SECONDS;
  }
}
