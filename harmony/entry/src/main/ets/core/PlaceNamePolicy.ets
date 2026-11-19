/**
 * 地名反查策略：与 Android `DistrictResolver` / iOS 同一口径。
 *
 * - 移动超过 5 km 才重新反查；
 * - 名字最多信任 30 天；
 * - GPS 采样 60 秒一次。
 */
export class PlaceNamePolicy {
  static readonly MOVE_THRESHOLD_KM: number = 5.0;
  static readonly MAX_AGE_MILLIS: number = 30 * 24 * 60 * 60 * 1000;
  static readonly LOCATION_SAMPLE_INTERVAL_SECONDS: number = 60;

  /** 该距离内的名字可信（距离未知 -1 时不信任）。 */
  static trustsNameAt(movedKm: number): boolean {
    return movedKm >= 0 && movedKm <= PlaceNamePolicy.MOVE_THRESHOLD_KM;
  }

  /** 是否应该发反查请求：移动 > 5 km、过期、或距离未知。 */
  static shouldQuery(movedKm: number, ageMillis: number): boolean {
    if (movedKm < 0) {
      return true;
    }
    return !PlaceNamePolicy.trustsNameAt(movedKm) ||
      !(ageMillis >= 0 && ageMillis <= PlaceNamePolicy.MAX_AGE_MILLIS);
  }
}
