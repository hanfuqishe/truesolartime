/**
 * 所有持久化数据都走 preferences：主进程、卡片进程读同一份文件。
 *
 * 用同步 API 是刻意的 —— FormExtensionAbility 的 onAddForm 必须同步返回卡片数据，
 * 没有办法在这里 await。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Place, PlaceSource } from '../core/Place';
import { ThemeMode } from '../core/ThemeMode';

const SETTINGS_STORE: string = 'solar_time_settings';
const WEATHER_STORE: string = 'weather_cache';
const KEY_TIME_STORE: string = 'take_time_cache';
const DISTRICT_STORE: string = 'district_cache';
const CARD_STORE: string = 'card_cache';

export class CachedWeather {
  temperatureC: number = 0;
  code: number = 0;
  /** 取数时刻（毫秒）；0 表示没有缓存。 */
  fetchedMillis: number = 0;
  /** 格式版本，参数变化时递增以强制重取。 */
  schema: number = 0;
  hourly: string = '';
  /** 上次**尝试**取数的时刻（毫秒）：取数失败后按 5 分钟节流重试。 */
  attemptMillis: number = 0;
  /** 这份缓存的来源（open-meteo / 7timer）；空串 = 旧版本缓存，按主源算。 */
  source: string = '';
  /** 逐时步长（小时）：1 = 主源，3 = 备用源；0 = 旧版本缓存，按来源推。 */
  stepHours: number = 0;
  /** 当前是低精度数据时，**连续**尝试主源失败的次数（成功切回主源时清零）。 */
  primaryFailures: number = 0;
}

/**
 * 最近一次取数的诊断记录（设置页「诊断」片区显示）。
 *
 * 与 Android 的 `DiagStore.recordWeather` 同一组键名（`weather_source` / `weather_step` /
 * `weather_age_minutes`），排查时两端的日志与截图能直接对上。
 */
export class WeatherDiag {
  /** 结果一句话，例如「主源成功」「主源失败，已降级到 7Timer!」。 */
  result: string = '';
  /** 本次结果对应的数据源（open-meteo / 7timer）。 */
  source: string = '';
  /** 逐时步长（小时）。 */
  stepHours: number = 0;
  /** 记录时的数据过期分钟数；-1 表示没有缓存。 */
  ageMinutes: number = -1;
  /** 最近一次失败的原因；成功后清空。 */
  failure: string = '';
  /** 记录时刻（毫秒）。 */
  recordedMillis: number = 0;
}

export class CachedKeyTime {
  bands: string = '';
  temperature: string = '';
  fetchedMillis: number = 0;
  attemptMillis: number = 0;
  successDay: string = '';
  targetDay: string = '';
  targetMillis: number = 0;
}

export class CachedDistrict {
  full: string = '';
  short: string = '';
  language: string = '';
  latitude: number = 0;
  longitude: number = 0;
  fetchedMillis: number = 0;
  schema: number = 0;
  countryCode: string = '';
}

export class AppStore {
  private static settingsPrefs: preferences.Preferences | null = null;
  private static weatherPrefs: preferences.Preferences | null = null;
  private static keyTimePrefs: preferences.Preferences | null = null;
  private static districtPrefs: preferences.Preferences | null = null;
  private static cardPrefs: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (AppStore.settingsPrefs !== null) {
      return;
    }
    AppStore.settingsPrefs = preferences.getPreferencesSync(context, { name: SETTINGS_STORE });
    AppStore.weatherPrefs = preferences.getPreferencesSync(context, { name: WEATHER_STORE });
    AppStore.keyTimePrefs = preferences.getPreferencesSync(context, { name: KEY_TIME_STORE });
    AppStore.districtPrefs = preferences.getPreferencesSync(context, { name: DISTRICT_STORE });
    AppStore.cardPrefs = preferences.getPreferencesSync(context, { name: CARD_STORE });
  }

  private static settingsStore(): preferences.Preferences {
    if (AppStore.settingsPrefs === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.settingsPrefs;
  }

  private static weatherStore(): preferences.Preferences {
    if (AppStore.weatherPrefs === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.weatherPrefs;
  }

  private static keyTimeStore(): preferences.Preferences {
    if (AppStore.keyTimePrefs === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.keyTimePrefs;
  }

  private static districtStore(): preferences.Preferences {
    if (AppStore.districtPrefs === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.districtPrefs;
  }

  private static cardStore(): preferences.Preferences {
    if (AppStore.cardPrefs === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.cardPrefs;
  }

  // ArkTS 的类型断言（as）只用于有继承关系的类型，读偏好设置一律走 typeof 收窄。

  private static numberValue(store: preferences.Preferences, key: string, fallback: number): number {
    const value: preferences.ValueType = store.getSync(key, fallback);
    return typeof value === 'number' ? value : fallback;
  }

  private static stringValue(store: preferences.Preferences, key: string, fallback: string): string {
    const value: preferences.ValueType = store.getSync(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }

  private static booleanValue(store: preferences.Preferences, key: string, fallback: boolean): boolean {
    const value: preferences.ValueType = store.getSync(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  // ---- 观测点与开关 ----

  static place(): Place {
    const store: preferences.Preferences = AppStore.settingsStore();
    const latitude: number = AppStore.numberValue(store, 'latitude', Place.DEFAULT.latitude);
    const longitude: number = AppStore.numberValue(store, 'longitude', Place.DEFAULT.longitude);
    const sourceValue: number = AppStore.numberValue(store, 'place_source', PlaceSource.DEFAULT);
    const label: string = AppStore.stringValue(store, 'place_label', '');
    // 预设城市自带的国家码：读出来才能「选中即按表算时区」。空串表示未知（GPS / 手动坐标）。
    const countryCode: string = AppStore.stringValue(store, 'place_country', '');
    const source: PlaceSource =
      sourceValue === PlaceSource.GPS ? PlaceSource.GPS
        : (sourceValue === PlaceSource.MANUAL ? PlaceSource.MANUAL : PlaceSource.DEFAULT);
    return new Place(latitude, longitude, source, label, '', countryCode);
  }

  static setPlace(place: Place): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('latitude', place.latitude);
    store.putSync('longitude', place.longitude);
    store.putSync('place_source', place.source);
    store.putSync('place_label', place.label);
    store.putSync('place_country', place.countryCode);
    store.flush();
  }

  static shichenReminders(): boolean {
    return AppStore.booleanValue(AppStore.settingsStore(), 'shichen_reminders', false);
  }

  static setShichenReminders(enabled: boolean): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('shichen_reminders', enabled);
    store.flush();
  }

  static keyTimeChime(): boolean {
    return AppStore.booleanValue(AppStore.settingsStore(), 'key_time_chime', false);
  }

  static setKeyTimeChime(enabled: boolean): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('key_time_chime', enabled);
    store.flush();
  }

  static locationAsked(): boolean {
    return AppStore.booleanValue(AppStore.settingsStore(), 'location_asked', false);
  }

  static setLocationAsked(asked: boolean): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('location_asked', asked);
    store.flush();
  }

  /** 应用在前台时是否禁止自动熄屏（默认开）。 */
  static keepScreenOn(): boolean {
    return AppStore.booleanValue(AppStore.settingsStore(), 'keep_screen_on', true);
  }

  static setKeepScreenOn(enabled: boolean): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('keep_screen_on', enabled);
    store.flush();
  }

  /** 地图底图：「自动」/ OSM / 高德矢量 / 高德卫星，见 core/MapTiles 的 MAP_STYLE_OPTIONS。 */
  static mapStyle(): string {
    return AppStore.stringValue(AppStore.settingsStore(), 'map_style', 'auto');
  }

  static setMapStyle(key: string): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('map_style', key);
    store.flush();
  }

  /**
   * 配色模式：`AUTO`（按日出日落，默认）/ `LIGHT`（强制亮色）/ `DARK`（强制暗色）。
   *
   * 非法值（旧版本没有这个键、值被人为改坏）一律回 `AUTO` —— 见 [ThemeMode.fromName]。
   */
  static themeMode(): string {
    return ThemeMode.fromName(AppStore.stringValue(AppStore.settingsStore(), 'theme_mode', ThemeMode.AUTO));
  }

  static setThemeMode(mode: string): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    // 存之前先规范化：界面上永远只可能写入三个合法值。
    store.putSync('theme_mode', ThemeMode.fromName(mode));
    store.flush();
  }

  /** 上次为「桌面卡片」主动取 GPS 的时刻（毫秒）：卡片侧最多 5 分钟取一次。 */
  static lastCardFixMillis(): number {
    return AppStore.numberValue(AppStore.settingsStore(), 'last_card_fix', 0);
  }

  static setLastCardFixMillis(millis: number): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('last_card_fix', millis);
    store.flush();
  }

  // ---- 已发布的卡片 ----

  static formIds(): string[] {
    const raw: string = AppStore.stringValue(AppStore.cardStore(), 'form_ids', '');
    if (raw.length === 0) {
      return [];
    }
    return raw.split('|');
  }

  static addFormId(formId: string): void {
    const ids: string[] = AppStore.formIds();
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    const store: preferences.Preferences = AppStore.cardStore();
    store.putSync('form_ids', ids.join('|'));
    store.flush();
  }

  static removeFormId(formId: string): void {
    const ids: string[] = AppStore.formIds().filter((id: string): boolean => id !== formId);
    const store: preferences.Preferences = AppStore.cardStore();
    store.putSync('form_ids', ids.join('|'));
    store.flush();
  }

  // ---- 已发布的代理提醒（系统不提供「按标题查自己发的提醒」，只能自己记账）----

  static reminderIds(): number[] {
    const raw: string = AppStore.stringValue(AppStore.settingsStore(), 'reminder_ids', '');
    const result: number[] = [];
    if (raw.length === 0) {
      return result;
    }
    for (const part of raw.split(',')) {
      const id: number = Number.parseInt(part);
      if (!isNaN(id)) {
        result.push(id);
      }
    }
    return result;
  }

  static setReminderIds(ids: number[]): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('reminder_ids', ids.join(','));
    store.flush();
  }

  // ---- 天气缓存 ----

  static weather(): CachedWeather {
    const store: preferences.Preferences = AppStore.weatherStore();
    const cached: CachedWeather = new CachedWeather();
    cached.temperatureC = AppStore.numberValue(store, 'temp', 0);
    cached.code = AppStore.numberValue(store, 'code', 0);
    cached.fetchedMillis = AppStore.numberValue(store, 'time', 0);
    cached.attemptMillis = AppStore.numberValue(store, 'attempt', 0);
    cached.schema = AppStore.numberValue(store, 'schema', 0);
    cached.hourly = AppStore.stringValue(store, 'hourly', '');
    cached.source = AppStore.stringValue(store, 'source', '');
    cached.stepHours = AppStore.numberValue(store, 'step_hours', 0);
    cached.primaryFailures = AppStore.numberValue(store, 'primary_failures', 0);
    return cached;
  }

  /** 当前低精度数据下，连续尝试主源失败的次数（用于退避；切回主源后清零）。 */
  static weatherPrimaryFailures(): number {
    return AppStore.numberValue(AppStore.weatherStore(), 'primary_failures', 0);
  }

  static setWeatherPrimaryFailures(count: number): void {
    const store: preferences.Preferences = AppStore.weatherStore();
    store.putSync('primary_failures', Math.max(0, Math.floor(count)));
    store.flush();
  }

  /** 只记下「尝试过取数」，不改动已有的成功数据（成功时间仍由 saveWeather 维护）。 */
  static markWeatherAttempt(): void {
    const store: preferences.Preferences = AppStore.weatherStore();
    store.putSync('attempt', Date.now());
    store.flush();
  }

  /**
   * 写一份天气缓存。
   *
   * [source] / [stepHours] 必须跟数据一起存：界面只画 6 个槽位，但槽位之间的间隔
   * 跟着数据源走（主源 1 小时、备用源 3 小时），只存读数不存步长，标签就会和读数错位。
   */
  static saveWeather(temperatureC: number, code: number, hourly: string, schema: number, latitude: number,
      longitude: number, source: string, stepHours: number): void {
    const store: preferences.Preferences = AppStore.weatherStore();
    store.putSync('attempt', Date.now());
    store.putSync('temp', temperatureC);
    store.putSync('code', code);
    store.putSync('hourly', hourly);
    store.putSync('schema', schema);
    store.putSync('source', source);
    store.putSync('step_hours', stepHours);
    store.putSync('lat', latitude);
    store.putSync('lon', longitude);
    store.putSync('time', Date.now());
    store.flush();
  }

  static weatherLatitude(): number {
    return AppStore.numberValue(AppStore.weatherStore(), 'lat', Number.NaN);
  }

  static weatherLongitude(): number {
    return AppStore.numberValue(AppStore.weatherStore(), 'lon', Number.NaN);
  }

  // ---- 天气诊断（设置页「诊断」片区）----

  static weatherDiag(): WeatherDiag {
    const store: preferences.Preferences = AppStore.weatherStore();
    const diag: WeatherDiag = new WeatherDiag();
    diag.result = AppStore.stringValue(store, 'diag_result', '');
    diag.source = AppStore.stringValue(store, 'diag_source', '');
    diag.stepHours = AppStore.numberValue(store, 'diag_step', 0);
    diag.ageMinutes = AppStore.numberValue(store, 'diag_age', -1);
    diag.failure = AppStore.stringValue(store, 'diag_failure', '');
    diag.recordedMillis = AppStore.numberValue(store, 'diag_time', 0);
    return diag;
  }

  static saveWeatherDiag(result: string, source: string, stepHours: number, ageMinutes: number,
      failure: string): void {
    const store: preferences.Preferences = AppStore.weatherStore();
    store.putSync('diag_result', result);
    store.putSync('diag_source', source);
    store.putSync('diag_step', stepHours);
    store.putSync('diag_age', ageMinutes);
    store.putSync('diag_failure', failure);
    store.putSync('diag_time', Date.now());
    store.flush();
  }

  // ---- 关键时间缓存 ----

  static keyTime(): CachedKeyTime {
    const store: preferences.Preferences = AppStore.keyTimeStore();
    const cached: CachedKeyTime = new CachedKeyTime();
    cached.bands = AppStore.stringValue(store, 'bands', '');
    cached.temperature = AppStore.stringValue(store, 'temp', '');
    cached.fetchedMillis = AppStore.numberValue(store, 'fetched', 0);
    cached.attemptMillis = AppStore.numberValue(store, 'attempt', 0);
    cached.successDay = AppStore.stringValue(store, 'success_day', '');
    cached.targetDay = AppStore.stringValue(store, 'target_day', '');
    cached.targetMillis = AppStore.numberValue(store, 'target_millis', 0);
    return cached;
  }

  static saveKeyTime(bands: string, temperature: string, successDay: string): void {
    const store: preferences.Preferences = AppStore.keyTimeStore();
    store.putSync('bands', bands);
    store.putSync('temp', temperature);
    store.putSync('fetched', Date.now());
    store.putSync('success_day', successDay);
    store.flush();
  }

  static markKeyTimeAttempt(): void {
    const store: preferences.Preferences = AppStore.keyTimeStore();
    store.putSync('attempt', Date.now());
    store.flush();
  }

  static saveKeyTimeTarget(day: string, millis: number): void {
    const store: preferences.Preferences = AppStore.keyTimeStore();
    store.putSync('target_day', day);
    store.putSync('target_millis', millis);
    store.flush();
  }

  // ---- 区划缓存 ----

  static district(): CachedDistrict {
    const store: preferences.Preferences = AppStore.districtStore();
    const cached: CachedDistrict = new CachedDistrict();
    cached.full = AppStore.stringValue(store, 'name', '');
    cached.short = AppStore.stringValue(store, 'short', '');
    cached.language = AppStore.stringValue(store, 'lang', '');
    cached.latitude = AppStore.numberValue(store, 'lat', Number.NaN);
    cached.longitude = AppStore.numberValue(store, 'lon', Number.NaN);
    cached.fetchedMillis = AppStore.numberValue(store, 'time', 0);
    cached.schema = AppStore.numberValue(store, 'schema', 0);
    cached.countryCode = AppStore.stringValue(store, 'countryCode', '');
    return cached;
  }

  static saveDistrict(full: string, short: string, language: string, latitude: number, longitude: number, schema: number,
      countryCode: string = ''): void {
    const store: preferences.Preferences = AppStore.districtStore();
    store.putSync('name', full);
    store.putSync('short', short);
    store.putSync('lang', language);
    store.putSync('lat', latitude);
    store.putSync('lon', longitude);
    store.putSync('schema', schema);
    store.putSync('countryCode', countryCode);
    store.putSync('time', Date.now());
    store.flush();
  }
}
