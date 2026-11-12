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

  // ---- 观测点与开关 ----

  static place(): Place {
    const store: preferences.Preferences = AppStore.settingsStore();
    const latitude: number = store.getSync('latitude', Place.DEFAULT.latitude) as number;
    const longitude: number = store.getSync('longitude', Place.DEFAULT.longitude) as number;
    const source: number = store.getSync('place_source', PlaceSource.DEFAULT as number) as number;
    const label: string = store.getSync('place_label', '') as string;
    return new Place(latitude, longitude, source as PlaceSource, label, '');
  }

  static setPlace(place: Place): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('latitude', place.latitude);
    store.putSync('longitude', place.longitude);
    store.putSync('place_source', place.source as number);
    store.putSync('place_label', place.label);
    store.flush();
  }

  static shichenReminders(): boolean {
    return AppStore.settingsStore().getSync('shichen_reminders', false) as boolean;
  }

  static setShichenReminders(enabled: boolean): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('shichen_reminders', enabled);
    store.flush();
  }

  static keyTimeChime(): boolean {
    return AppStore.settingsStore().getSync('key_time_chime', false) as boolean;
  }

  static setKeyTimeChime(enabled: boolean): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('key_time_chime', enabled);
    store.flush();
  }

  static locationAsked(): boolean {
    return AppStore.settingsStore().getSync('location_asked', false) as boolean;
  }

  static setLocationAsked(asked: boolean): void {
    const store: preferences.Preferences = AppStore.settingsStore();
    store.putSync('location_asked', asked);
    store.flush();
  }

  // ---- 已发布的卡片 ----

  static formIds(): string[] {
    const raw: string = AppStore.cardStore().getSync('form_ids', '') as string;
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
    cached.temperatureC = store.getSync('temp', 0) as number;
    cached.code = store.getSync('code', 0) as number;
    cached.fetchedMillis = store.getSync('time', 0) as number;
    cached.schema = store.getSync('schema', 0) as number;
    cached.hourly = store.getSync('hourly', '') as string;
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
    return AppStore.weatherStore().getSync('lat', Number.NaN) as number;
  }

  static weatherLongitude(): number {
    return AppStore.weatherStore().getSync('lon', Number.NaN) as number;
  }

  // ---- 关键时间缓存 ----

  static keyTime(): CachedKeyTime {
    const store: preferences.Preferences = AppStore.keyTimeStore();
    const cached: CachedKeyTime = new CachedKeyTime();
    cached.bands = store.getSync('bands', '') as string;
    cached.temperature = store.getSync('temp', '') as string;
    cached.fetchedMillis = store.getSync('fetched', 0) as number;
    cached.attemptMillis = store.getSync('attempt', 0) as number;
    cached.successDay = store.getSync('success_day', '') as string;
    cached.targetDay = store.getSync('target_day', '') as string;
    cached.targetMillis = store.getSync('target_millis', 0) as number;
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
    cached.full = store.getSync('name', '') as string;
    cached.short = store.getSync('short', '') as string;
    cached.language = store.getSync('lang', '') as string;
    cached.latitude = store.getSync('lat', Number.NaN) as number;
    cached.longitude = store.getSync('lon', Number.NaN) as number;
    cached.fetchedMillis = store.getSync('time', 0) as number;
    cached.schema = store.getSync('schema', 0) as number;
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
