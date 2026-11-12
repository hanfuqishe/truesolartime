/**
 * 行政区划名：先用系统逆地理编码（跟随系统语言），失败再走 OSM Nominatim。
 * 结果缓存 30 天，界面语言变化或移动超过 5 km 才重查 —— 与 Android 端策略一致。
 */

import { geoLocationManager } from '@kit.LocationKit';
import { i18n } from '@kit.LocalizationKit';
import { CityIndex } from '../core/CityIndex';
import { DistrictNameLogic, DistrictNames } from '../core/DistrictName';
import { Place } from '../core/Place';
import { AppStore, CachedDistrict } from './Store';
import { HttpUtil } from './HttpUtil';

const CACHE_SCHEMA: number = 1;
const NOMINATIM_URL: string = 'https://nominatim.openstreetmap.org/reverse';
const TIMEOUT_MILLIS: number = 10000;
/** 遵守 OSM 使用条款：可识别的 UA + 结果缓存。 */
const USER_AGENT: string = 'TrueSolarTime-HarmonyOS/1.0';

export class DistrictService {
  private static inFlight: boolean = false;

  /** 系统语言，例如 "zh-Hans-CN" / "en-US"。 */
  static language(): string {
    try {
      return i18n.System.getSystemLanguage();
    } catch (error) {
      return 'zh-Hans';
    }
  }

  /** 最近一次反查到的名字；不判断距离，避免新结果回来前显示闪成别的名字。 */
  static cachedName(): string {
    return AppStore.district().full;
  }

  static cachedShortName(): string {
    const cached: CachedDistrict = AppStore.district();
    return cached.short.length > 0 ? cached.short : cached.full;
  }

  /** 坐标超过 5 km 才重查。 */
  static needsRefresh(place: Place): boolean {
    const cached: CachedDistrict = AppStore.district();
    const hasCache: boolean = cached.full.length > 0 && cached.schema === CACHE_SCHEMA;
    const age: number = Date.now() - cached.fetchedMillis;
    let moved: number = Number.MAX_VALUE;
    if (!isNaN(cached.latitude) && !isNaN(cached.longitude)) {
      moved = CityIndex.distanceKm(cached.latitude, cached.longitude, place.latitude, place.longitude);
    }
    return DistrictNameLogic.needsRefresh(hasCache, cached.language, DistrictService.language(), age, moved);
  }

  /** 需要时反查一次；查到新名字返回 true（调用方据此刷新界面与卡片）。 */
  static async refreshIfNeeded(place: Place): Promise<boolean> {
    if (DistrictService.inFlight || !DistrictService.needsRefresh(place)) {
      return false;
    }
    DistrictService.inFlight = true;
    try {
      const language: string = DistrictService.language();
      const names: DistrictNames | null = await DistrictService.resolve(place, language);
      if (names === null) {
        return false;
      }
      AppStore.saveDistrict(names.full, names.short, language, place.latitude, place.longitude, CACHE_SCHEMA);
      return true;
    } finally {
      DistrictService.inFlight = false;
    }
  }

  /** 强制反查（用户换城市后立刻更新名字）。 */
  static async resolve(place: Place, language: string): Promise<DistrictNames | null> {
    const fromSystem: DistrictNames | null = await DistrictService.fromSystemGeocoder(place, language);
    if (fromSystem !== null) {
      return fromSystem;
    }
    return DistrictService.fromNominatim(place, language);
  }

  /**
   * 系统逆地理编码。中文界面直接用系统的省市区字段；非中文界面交给 OSM，
   * 因为系统逆地理的返回语言由设备决定，不能保证跟随界面语言。
   */
  private static async fromSystemGeocoder(place: Place, language: string): Promise<DistrictNames | null> {
    if (!language.startsWith('zh')) {
      return null;
    }
    try {
      if (!geoLocationManager.isGeocoderAvailable()) {
        return null;
      }
      const request: geoLocationManager.ReverseGeoCodeRequest = {
        latitude: place.latitude,
        longitude: place.longitude,
        maxItems: 1,
        locale: language
      };
      const addresses: geoLocationManager.GeoAddress[] = await geoLocationManager.getAddressesFromLocation(request);
      if (addresses.length === 0) {
        return null;
      }
      const address: geoLocationManager.GeoAddress = addresses[0];
      return DistrictNameLogic.composeNames([
        address.subLocality,
        address.locality,
        address.subAdministrativeArea,
        address.administrativeArea
      ]);
    } catch (error) {
      return null;
    }
  }

  private static async fromNominatim(place: Place, language: string): Promise<DistrictNames | null> {
    const locale: string = language.length > 0 ? language : 'zh';
    const url: string = `${NOMINATIM_URL}?format=jsonv2&addressdetails=1&zoom=14` +
      `&lat=${place.latitude.toFixed(5)}&lon=${place.longitude.toFixed(5)}` +
      `&accept-language=${encodeURIComponent(locale)}`;
    const headers: Record<string, string> = {
      'User-Agent': USER_AGENT,
      'Accept-Language': locale
    };
    const body: string | null = await HttpUtil.getText(url, headers, TIMEOUT_MILLIS);
    if (body === null) {
      return null;
    }
    try {
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const address: Object | undefined = root['address'];
      if (address === undefined || address === null) {
        return null;
      }
      const fields: Record<string, Object> = address as Record<string, Object>;
      return DistrictNameLogic.composeNames([
        DistrictService.firstOf(fields, ['village', 'town', 'suburb', 'city_district', 'district', 'hamlet']),
        DistrictService.firstOf(fields, ['city', 'municipality', 'county', 'state_district']),
        DistrictService.firstOf(fields, ['state', 'province', 'region'])
      ]);
    } catch (error) {
      return null;
    }
  }

  private static firstOf(fields: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const value: Object | undefined = fields[key];
      if (value !== undefined && value !== null) {
        const text: string = String(value);
        if (text.length > 0) {
          return text;
        }
      }
    }
    return '';
  }
}
