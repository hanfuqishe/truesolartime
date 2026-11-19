/**
 * 行政区划名：先用系统逆地理编码（跟随系统语言），失败再走 OSM Nominatim。
 * 结果缓存 30 天，界面语言变化或移动超过 5 km 才重查 —— 与 Android 端策略一致。
 */

import { geoLocationManager } from '@kit.LocationKit';
import { i18n } from '@kit.LocalizationKit';
import { CityIndex } from '../core/CityIndex';
import { DistrictLookupPolicy } from '../core/DistrictLookup';
import { DistrictNameLogic, DistrictNames } from '../core/DistrictName';
import { PlaceNamePolicy } from '../core/PlaceNamePolicy';
import { Place } from '../core/Place';
import { SolarTimeMath } from '../core/SolarTimeMath';
import { AppStore, CachedDistrict } from './Store';
import { HttpUtil } from './HttpUtil';

const CACHE_SCHEMA: number = 1;
/** 新坐标与上次反查坐标相距超过该距离，缓存里的名字就不再算数。 */
const MOVE_THRESHOLD_KM: number = 5.0;
const NOMINATIM_URL: string = 'https://nominatim.openstreetmap.org/reverse';
const TIMEOUT_MILLIS: number = 10000;
/** 遵守 OSM 使用条款：可识别的 UA + 结果缓存。 */
const USER_AGENT: string = 'TrueSolarTime-HarmonyOS/1.0';

export class DistrictService {
  private static inFlight: boolean = false;
  /** 上次成功反查的坐标与时刻：5 km 判定与诊断都以它为基准。 */
  private static lastSuccessLat: number = NaN;
  private static lastSuccessLon: number = NaN;
  private static lastSuccessMillis: number = 0;
  private static requestCount: number = 0;
  private static lastDurationMillis: number = 0;
  private static lastDistanceKm: number = -1;
  /** 按地点换代：每次新地点 +1，旧一代回调直接丢弃。 */
  private static generation: number = 0;
  private static lastAttemptLat: number = NaN;
  private static lastAttemptLon: number = NaN;
  private static lastAttemptMillis: number = 0;
  private static lastSkipReason: string = '';

  /** 每反查到一次新名字就 +1，供界面判断「区划名换了」。 */
  private static revisionCount: number = 0;

  static revision(): number {
    return DistrictService.revisionCount;
  }

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

  /**
   * 缓存里的区划名，但**只在与 place 还算同一个地方时才认**（[MOVE_THRESHOLD_KM] 以内）。
   *
   * 换城市后、新名字还没查回来（或这次查询失败）时返回 null，界面就不显示旧城市，
   * 避免「切到纽约，卡片还写着上海市黄浦区」—— 与 Android 的 `cachedNamesFor` 一致。
   */
  static cachedNamesFor(place: Place): DistrictNames | null {
    const cached: CachedDistrict = AppStore.district();
    if (cached.full.length === 0) {
      return null;
    }
    if (isNaN(cached.latitude) || isNaN(cached.longitude)) {
      return null;
    }
    const moved: number = CityIndex.distanceKm(cached.latitude, cached.longitude, place.latitude, place.longitude);
    if (moved > MOVE_THRESHOLD_KM) {
      return null;
    }
    const short: string = cached.short.length > 0 ? cached.short : cached.full;
    return new DistrictNames(cached.full, short, cached.countryCode);
  }

  /** 同 cachedNamesFor，只取带上级的全名（如「上海市黄浦区」）。 */
  static cachedNameFor(place: Place): string {
    const names: DistrictNames | null = DistrictService.cachedNamesFor(place);
    return names === null ? '' : names.full;
  }

  /** 同 cachedNamesFor，只取区县短名。 */
  static cachedShortNameFor(place: Place): string {
    const names: DistrictNames | null = DistrictService.cachedNamesFor(place);
    return names === null ? '' : names.short;
  }

  /** 清空区划名缓存并通知界面重读：换到手动坐标 / 新地点时立刻回到半角 `-`。 */
  static clearCached(): void {
    AppStore.clearDistrict();
    DistrictService.revisionCount++;
  }

  /** 5 km / 30 天 / 语言变化才重查；距离未知一律查。 */
  static needsRefresh(place: Place): boolean {
    const cached: CachedDistrict = AppStore.district();
    const hasCache: boolean = cached.full.length > 0 && cached.schema === CACHE_SCHEMA;
    if (!hasCache || cached.language !== DistrictService.language()) {
      return true;
    }
    const age: number = Date.now() - cached.fetchedMillis;
    let moved: number = -1;
    if (!isNaN(cached.latitude) && !isNaN(cached.longitude)) {
      moved = CityIndex.distanceKm(cached.latitude, cached.longitude, place.latitude, place.longitude);
    }
    return PlaceNamePolicy.shouldQuery(moved, age);
  }

  /** 需要时反查一次；force = 换城市 / 手输坐标时绕过 5 km。 */
  static async refreshIfNeeded(place: Place, force: boolean = false): Promise<boolean> {
    if (!force && !DistrictService.needsRefresh(place)) {
      DistrictService.lastSkipReason = '无需刷新（5 km 内且未过期）';
      return false;
    }
    const now: number = Date.now();
    const samePlace: boolean = !isNaN(DistrictService.lastAttemptLat) &&
      CityIndex.distanceKm(DistrictService.lastAttemptLat, DistrictService.lastAttemptLon,
        place.latitude, place.longitude) < 0.01;
    if (DistrictLookupPolicy.shouldSkipDuplicate(samePlace, now - DistrictService.lastAttemptMillis)) {
      DistrictService.lastSkipReason = '同一地点去重（6 秒内）';
      return false;
    }
    // 新地点直接换代并发请求：上一次卡住不影响这一次。
    DistrictService.generation++;
    const myGen: number = DistrictService.generation;
    DistrictService.lastAttemptLat = place.latitude;
    DistrictService.lastAttemptLon = place.longitude;
    DistrictService.lastAttemptMillis = now;
    DistrictService.inFlight = true;
    DistrictService.lastSkipReason = '';
    const started: number = now;
    try {
      const language: string = DistrictService.language();
      const names: DistrictNames | null = await DistrictService.resolve(place, language);
      DistrictService.lastDurationMillis = Date.now() - started;
      // 过期结果（期间已换地点）直接丢弃，不覆盖新地点的名字。
      if (!DistrictLookupPolicy.shouldAcceptResult(myGen, DistrictService.generation)) {
        DistrictService.lastSkipReason = '过期结果已丢弃（地点已换代）';
        return false;
      }
      if (names === null) {
        return false;
      }
      DistrictService.lastDistanceKm = !isNaN(DistrictService.lastSuccessLat)
        ? CityIndex.distanceKm(DistrictService.lastSuccessLat, DistrictService.lastSuccessLon,
          place.latitude, place.longitude) : -1;
      DistrictService.lastSuccessLat = place.latitude;
      DistrictService.lastSuccessLon = place.longitude;
      DistrictService.lastSuccessMillis = Date.now();
      DistrictService.requestCount++;
      AppStore.saveDistrict(names.full, names.short, language, place.latitude, place.longitude, CACHE_SCHEMA, names.countryCode);
      DistrictService.revisionCount++;
      return true;
    } finally {
      if (myGen === DistrictService.generation) {
        DistrictService.inFlight = false;
      }
    }
  }

  /** 诊断：`行政区名 … · 耗时 = 0.4s · 请求次数 = 1 · 距上次反查 1.2 km`。 */
  static diagnosticLine(): string {
    const name: string = DistrictService.cachedName();
    const label: string = name.length > 0 ? name : '-';
    const seconds: string = (DistrictService.lastDurationMillis / 1000).toFixed(1);
    const distance: string = DistrictService.lastDistanceKm < 0
      ? '未知' : `${DistrictService.lastDistanceKm.toFixed(1)} km`;
    return `行政区名 ${label} · 耗时 = ${seconds}s · 请求次数 = ${DistrictService.requestCount} · 距上次反查 ${distance} · 跳过原因 = ${DistrictService.lastSkipReason.length > 0 ? DistrictService.lastSkipReason : '无'}`;
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
      const district: string = address.subLocality ?? address.locality ?? '';
      const city: string = address.locality ?? address.subAdministrativeArea ?? '';
      const province: string = address.administrativeArea ?? '';
      const sysNames: DistrictNames | null = DistrictNameLogic.pickNames(district, city, province);
      if (sysNames !== null) {
        sysNames.countryCode = (address.countryCode ?? '').toLowerCase();
      }
      return sysNames;
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
      // 优先「区/县」一级：OSM 常把上海的区只写进 display_name（address 里只有街道），
      // 因此再从 display_name 里捞一个以「区/县/旗」结尾的名字；街道只在完全没有区县时兜底。
      const city: string = DistrictService.firstOf(fields, ['city', 'municipality', 'state_district']);
      const display: string = DistrictService.firstOf(root, ['display_name']);
      let district: string = DistrictService.firstOf(fields, ['city_district', 'district', 'county']);
      if (district.length === 0) {
        district = DistrictNameLogic.pickDistrictFromDisplay(display, city);
      }
      if (district.length === 0) {
        district = DistrictService.firstOf(fields, ['suburb', 'town', 'village', 'hamlet']);
      }
      const province: string = DistrictService.firstOf(fields, ['state', 'province', 'region']);
      // 分隔符由名字本身决定（core/DistrictName）：中文名「上海市黄浦区」直接相连，
      // 英文名「New York, Manhattan」用逗号 —— 之前中文界面下拿英文名直接拼接，
      // 会出现「New YorkManhattan」这种粘在一起的怪串。
      if (language.startsWith('zh')) {
        const names: DistrictNames | null = DistrictNameLogic.pickNames(district, city, province);
        if (names !== null) {
          names.countryCode = DistrictService.firstOf(fields, ['country_code']).toLowerCase();
        }
        return names;
      }
      const composed: DistrictNames | null = DistrictNameLogic.composeNames([district, city, province]);
      if (composed !== null) {
        composed.countryCode = DistrictService.firstOf(fields, ['country_code']).toLowerCase();
      }
      return composed;
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
