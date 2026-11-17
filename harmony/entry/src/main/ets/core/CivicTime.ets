/**
 * 「所在国的标准时间」的唯一判定入口，与 Android 的 `data/CivicTime.kt` 同一套规则：
 * 界面左栏的标准时钟、`UTC+8` 标签、日出/上中天/日落、真太阳时换算的基准偏移都走这里。
 *
 * 为什么不直接用坐标所在的 tzdata 时区：一个国家常有多块时区，但**官方时间**往往全国统一。
 * 中国最典型（`Asia/Shanghai` +8 / `Asia/Urumqi` +6，官方全境 +8）；南极考察站同理 ——
 * 中国四个站（中山 / 长城 / 昆仑 / 泰山）官方都按北京时间（+8）。
 *
 * 判定顺序：
 *  1. 中国境内（国家码 cn/hk/mo/tw，或没有国家码时落在包围盒内）→ +480；
 *  2. 中国南极考察站（站点坐标 ±0.5°）→ +480；
 *  3. 其它国家 → [ZoneTable] 的国家表 + 多时区大国按经度分段（给的是国家标准时间）。
 *     鸿蒙这边拿不到城市级 IANA ID，所以没有 tzdata 分支；Android 侧多一个可选 `tzId`。
 */

import { SolarTimeMath } from './SolarTimeMath';
import { ZoneTable } from './ZoneTable';

/** 中国南极考察站（站名仅用于排查）：判定半径 0.5°（约 55 km）覆盖站区与周边作业点。 */
class ChineseStation {
  latitude: number;
  longitude: number;

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

export class CivicTimeLogic {
  /** 中国官方标准时间：UTC+8，单位分钟。 */
  static readonly CHINA_MINUTES: number = 480;

  private static readonly STATION_HALF_SPAN_DEG: number = 0.5;

  private static readonly STATIONS: ChineseStation[] = [
    new ChineseStation(-69.3733, 76.3800),   // 中山站
    new ChineseStation(-62.2167, -58.9667),  // 长城站
    new ChineseStation(-80.4167, 77.1167),   // 昆仑站
    new ChineseStation(-73.8667, 76.9667)    // 泰山站
  ];

  /** 是不是中国境内（含港澳台）：有国家码以国家码为准，没有才退回包围盒。 */
  static isChina(latitude: number, longitude: number, countryCode: string): boolean {
    return SolarTimeMath.isInChina(latitude, longitude, countryCode);
  }

  /** 是否落在中国南极考察站附近（站务时间按北京时间，与 tzdata 的 `Antarctica/*` 无关）。 */
  static isChineseAntarcticStation(latitude: number, longitude: number): boolean {
    for (const station of CivicTimeLogic.STATIONS) {
      if (Math.abs(latitude - station.latitude) <= CivicTimeLogic.STATION_HALF_SPAN_DEG &&
        Math.abs(longitude - station.longitude) <= CivicTimeLogic.STATION_HALF_SPAN_DEG) {
        return true;
      }
    }
    return false;
  }

  /**
   * 观测点所在国的标准时间偏移（分钟）。
   *
   * @param countryCode ISO 3166-1 alpha-2；未知传空串（此时才用中国包围盒兜底）
   */
  static standardOffsetMinutes(latitude: number, longitude: number, countryCode: string): number {
    if (CivicTimeLogic.isChina(latitude, longitude, countryCode)) {
      return CivicTimeLogic.CHINA_MINUTES;
    }
    if (CivicTimeLogic.isChineseAntarcticStation(latitude, longitude)) {
      return CivicTimeLogic.CHINA_MINUTES;
    }
    const seconds: number = ZoneTable.offsetSeconds(countryCode, longitude,
      SolarTimeMath.standardZoneOffsetSeconds(latitude, longitude, countryCode));
    return Math.round(seconds / 60);
  }

  /** 同上，单位秒 —— 界面与太阳计算都用秒。 */
  static standardOffsetSeconds(latitude: number, longitude: number, countryCode: string): number {
    return CivicTimeLogic.standardOffsetMinutes(latitude, longitude, countryCode) * 60;
  }
}
