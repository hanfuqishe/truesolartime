/**
 * 天气取数：Open-Meteo，免费、无需 Key、全球可用（CC BY 4.0）。
 * 缓存 30 分钟；位置移动超过 5 km 也重取。失败沿用旧值。
 */

import { CityIndex } from '../core/CityIndex';
import { Place } from '../core/Place';
import { HourPoint, WeatherLogic, WeatherSnapshot } from '../core/Weather';
import { AppStore, CachedWeather } from './Store';
import { HttpUtil } from './HttpUtil';

const SCHEMA: number = 2;
const TIMEOUT_MILLIS: number = 8000;

export class WeatherService {
  private static inFlight: boolean = false;

  /** 每成功写进一次缓存就 +1；界面靠它发现「天气换过了」，不必每秒去读偏好。 */
  private static revisionCount: number = 0;

  static revision(): number {
    return WeatherService.revisionCount;
  }

  /** 最近一次成功取到的实时天气（6 小时内、且属于当前这个地点），用于显示。 */
  static cached(place: Place): WeatherSnapshot | null {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0 || cached.schema !== SCHEMA) {
      return null;
    }
    const age: number = Date.now() - cached.fetchedMillis;
    if (!(age >= 0 && age <= WeatherLogic.HOURLY_MAX_AGE_MILLIS)) {
      return null;
    }
    // 换了城市后新数据回来之前（或取数一直失败），不能把上一个城市的天气安到新位置上。
    const moved: number = CityIndex.distanceKm(
      AppStore.weatherLatitude(), AppStore.weatherLongitude(), place.latitude, place.longitude);
    if (moved > WeatherLogic.MOVE_THRESHOLD_KM) {
      return null;
    }
    return new WeatherSnapshot(cached.temperatureC, cached.code);
  }

  /** 缓存的小时预报；过期太久或属于别的地点则返回空列表。 */
  static hourly(place: Place | null = null): HourPoint[] {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0) {
      return [];
    }
    const age: number = Date.now() - cached.fetchedMillis;
    if (!(age >= 0 && age <= WeatherLogic.HOURLY_MAX_AGE_MILLIS)) {
      return [];
    }
    // 换城市后新数据回来之前，不能拿旧城市的预报去算温度区间或逐时格。
    if (place !== null) {
      const moved: number = CityIndex.distanceKm(
        AppStore.weatherLatitude(), AppStore.weatherLongitude(), place.latitude, place.longitude);
      if (moved > WeatherLogic.MOVE_THRESHOLD_KM) {
        return [];
      }
    }
    return WeatherLogic.decodeHourly(cached.hourly);
  }

  static needsRefresh(place: Place): boolean {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0 || cached.schema !== SCHEMA || cached.hourly.length === 0) {
      return true;
    }
    const latitude: number = AppStore.weatherLatitude();
    const longitude: number = AppStore.weatherLongitude();
    const moved: number = isNaN(latitude) || isNaN(longitude)
      ? Number.MAX_VALUE
      : CityIndex.distanceKm(latitude, longitude, place.latitude, place.longitude);
    return WeatherLogic.shouldRefresh(Date.now() - cached.fetchedMillis, moved);
  }

  /** 需要时取一次数；成功返回 true。force 为 true 时忽略 30 分钟窗口（用户手工换了地点）。 */
  static async refreshIfNeeded(place: Place, force: boolean = false): Promise<boolean> {
    if (WeatherService.inFlight || (!force && !WeatherService.needsRefresh(place))) {
      return false;
    }
    WeatherService.inFlight = true;
    try {
      const body: string | null = await HttpUtil.getText(WeatherLogic.buildUrl(place.latitude, place.longitude), {}, TIMEOUT_MILLIS);
      if (body === null) {
        return false;
      }
      const snapshot: WeatherSnapshot | null = WeatherLogic.parse(body);
      if (snapshot === null) {
        return false;
      }
      const hourly: HourPoint[] = WeatherLogic.parseHourly(body);
      AppStore.saveWeather(
        snapshot.temperatureC,
        snapshot.code,
        WeatherLogic.encodeHourly(hourly),
        SCHEMA,
        place.latitude,
        place.longitude
      );
      WeatherService.revisionCount++;
      return true;
    } finally {
      WeatherService.inFlight = false;
    }
  }
}
