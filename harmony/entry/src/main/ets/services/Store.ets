/**
 * 所有持久化数据都走 preferences：主进程、卡片进程读同一份文件。
 *
 * 用同步 API 是刻意的 —— FormExtensionAbility 的 onAddForm 必须同步返回卡片数据，
 * 没有办法在这里 await。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Place, PlaceSource } from '../core/Place';

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
}

export class AppStore {
  private static settings: preferences.Preferences | null = null;
  private static weather: preferences.Preferences | null = null;
  private static keyTime: preferences.Preferences | null = null;
  private static district: preferences.Preferences | null = null;
  private static card: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (AppStore.settings !== null) {
      return;
    }
    AppStore.settings = preferences.getPreferencesSync(context, { name: SETTINGS_STORE });
    AppStore.weather = preferences.getPreferencesSync(context, { name: WEATHER_STORE });
    AppStore.keyTime = preferences.getPreferencesSync(context, { name: KEY_TIME_STORE });
    AppStore.district = preferences.getPreferencesSync(context, { name: DISTRICT_STORE });
    AppStore.card = preferences.getPreferencesSync(context, { name: CARD_STORE });
  }

  private static settingsStore(): preferences.Preferences {
    if (AppStore.settings === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.settings;
  }

  private static weatherStore(): preferences.Preferences {
    if (AppStore.weather === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.weather;
  }

  private static keyTimeStore(): preferences.Preferences {
    if (AppStore.keyTime === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.keyTime;
  }

  private static districtStore(): preferences.Preferences {
    if (AppStore.district === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.district;
  }

  private static cardStore(): preferences.Preferences {
    if (AppStore.card === null) {
      throw new Error('AppStore.init() must be called before use');
    }
    return AppStore.card;
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
    const source: PlaceSource =
      sourceValue === PlaceSource.GPS ? PlaceSource.GPS
        : (sourceValue === PlaceSource.MANUAL ? PlaceSource.MANUAL : PlaceSource.DEFAULT);
    return new Place(latitude, longitude, source, label, '');
  }

  static setPlace(place: Place): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('latitude', place.latitude);
    store.putSync('longitude', place.longitude);
    store.putSync('place_source', place.source);
    store.putSync('place_label', place.label);
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

  // ---- 天气缓存 ----

  static weather(): CachedWeather {
    const store: preferences.Preferences = AppStore.weatherStore();
    const cached: CachedWeather = new CachedWeather();
    cached.temperatureC = AppStore.numberValue(store, 'temp', 0);
    cached.code = AppStore.numberValue(store, 'code', 0);
    cached.fetchedMillis = AppStore.numberValue(store, 'time', 0);
    cached.schema = AppStore.numberValue(store, 'schema', 0);
    cached.hourly = AppStore.stringValue(store, 'hourly', '');
    return cached;
  }

  static saveWeather(temperatureC: number, code: number, hourly: string, schema: number, latitude: number, longitude: number): void {
    const store: preferences.Preferences = AppStore.weatherStore();
    store.putSync('temp', temperatureC);
    store.putSync('code', code);
    store.putSync('hourly', hourly);
    store.putSync('schema', schema);
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
    return cached;
  }

  static saveDistrict(full: string, short: string, language: string, latitude: number, longitude: number, schema: number): void {
    const store: preferences.Preferences = AppStore.districtStore();
    store.putSync('name', full);
    store.putSync('short', short);
    store.putSync('lang', language);
    store.putSync('lat', latitude);
    store.putSync('lon', longitude);
    store.putSync('schema', schema);
    store.putSync('time', Date.now());
    store.flush();
  }
}
