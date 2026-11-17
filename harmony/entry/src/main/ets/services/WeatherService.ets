/**
 * 天气取数：主源 Open-Meteo（1 小时粒度，CC BY 4.0），备用源 7Timer!（3 小时粒度）。
 *
 * 降级链与策略**逐条对齐 Android 的 WeatherRepository**：
 *   ① 主源请求失败（网络错误 / 超时 ≤5 秒 / 非 2xx / JSON 解析失败）→ **立刻**问备用源，不再等 2 秒重试；
 *   ② 缓存不超过 30 分钟且属于当前地点 → **什么都不做**，界面继续用缓存（不清空）；
 *   ③ 缓存已过期（或根本没有）→ 问备用源 7Timer!，成功就整份换掉（source=7timer、stepHours=3）；
 *   ④ 两个源都失败 → 旧数据继续显示（最长 24 小时），诊断里标「数据过期 N 分钟」；
 *   ⑤ 当前是低精度数据时，前台按 60/120/300 秒退避（封顶 5 分钟）、后台 10 分钟试一次主源，
 *      成功立刻切回 1 小时源并清零退避；回到前台则立即试一次（不等计时器）。
 *
 * 天气变化慢，缓存 30 分钟；只有缓存过期、位置移动超过 5 km、或低精度升级轮询才请求一次。
 * 请求与缓存之外的一切（解析、槽位、降级判定）都在 core/Weather.ets，便于数值自检。
 */

import { CityIndex } from '../core/CityIndex';
import { Place } from '../core/Place';
import {
  HourPoint,
  PrimaryWeather,
  WeatherFallback,
  WeatherLogic,
  WeatherSource,
  WeatherSnapshot
} from '../core/Weather';
import { AppStore, CachedWeather } from './Store';
import { HttpUtil } from './HttpUtil';

/** 缓存格式版本：请求参数或缓存字段变化时递增，强制重取一次（不影响旧数据的继续显示）。 */
const SCHEMA: number = 3;

export class WeatherService {
  private static inFlight: boolean = false;

  /** 每成功写进一次缓存就 +1；界面靠它发现「天气换过了」，不必每秒去读偏好。 */
  private static revisionCount: number = 0;

  static revision(): number {
    return WeatherService.revisionCount;
  }

  /** 是否正在取数（界面据此在「当前地点还没有缓存」时显示「更新中…」）。 */
  static isRefreshing(): boolean {
    return WeatherService.inFlight;
  }

  /** 缓存里的坐标是否属于当前观测点（相距不超过 5 km）；缺坐标的旧缓存一律算「不属于」。 */
  private static belongsTo(place: Place): boolean {
    const latitude: number = AppStore.weatherLatitude();
    const longitude: number = AppStore.weatherLongitude();
    if (isNaN(latitude) || isNaN(longitude)) {
      return false;
    }
    return CityIndex.distanceKm(latitude, longitude, place.latitude, place.longitude) <= WeatherLogic.MOVE_THRESHOLD_KM;
  }

  /** 缓存数据的来源（界面底部署名、诊断跟着它切换）；没有缓存时按主源算。 */
  static source(): string {
    return WeatherSource.of(AppStore.weather().source);
  }

  /** 缓存数据的逐时步长（1 或 3 小时）：优先用缓存里存的，旧缓存按来源推。 */
  static stepHours(): number {
    const cached: CachedWeather = AppStore.weather();
    if (cached.stepHours > 0) {
      return cached.stepHours;
    }
    return WeatherSource.stepHoursOf(cached.source);
  }

  /** 缓存有多旧（分钟）；没有任何缓存时返回 -1。诊断用它标注「数据过期 N 分钟」。 */
  static ageMinutes(): number {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0) {
      return -1;
    }
    return Math.floor(Math.max(0, Date.now() - cached.fetchedMillis) / 60000);
  }

  /** 诊断里的「数据过期 N 分钟」；没有缓存返回空串。 */
  static staleLabel(): string {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0) {
      return '';
    }
    return WeatherLogic.staleLabel(Math.max(0, Date.now() - cached.fetchedMillis));
  }

  /**
   * 最近一次取到的实时天气（24 小时内、且属于当前这个地点），用于显示。
   *
   * 这里**不**看缓存格式版本：版本只在 [needsRefresh] 里触发一次重取。
   * 取数失败时（夜间 Doze、网络刚醒还没通……）旧数据继续显示，总比整块变成 `--` 强。
   */
  static cached(place: Place): WeatherSnapshot | null {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0) {
      return null;
    }
    const age: number = Date.now() - cached.fetchedMillis;
    if (!WeatherLogic.isDisplayable(age)) {
      return null;
    }
    // 换了城市后新数据回来之前（或取数一直失败），不能把上一个城市的天气安到新位置上。
    if (!WeatherService.belongsTo(place)) {
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
    if (!WeatherLogic.isDisplayable(age)) {
      return [];
    }
    // 换城市后新数据回来之前，不能拿旧城市的预报去算温度区间或逐时格。
    if (place !== null && !WeatherService.belongsTo(place)) {
      return [];
    }
    return WeatherLogic.decodeHourly(cached.hourly);
  }

  /**
   * 该不该刷新。
   *
   * @param foreground true = 应用在前台（页面可见）：低精度数据按 60/120/300 秒退避轮询主源；
   *   false = 后台 / 卡片刷新：低精度升级最小间隔 10 分钟，不参与 60 秒轮询。
   */
  static needsRefresh(place: Place, foreground: boolean = true): boolean {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0 || cached.hourly.length === 0) {
      return true;
    }
    // 旧版本缓存里没有来源/步长：重取一次，否则逐时行会按错的步长排。
    if (cached.source.length === 0 || cached.stepHours <= 0) {
      return true;
    }
    if (cached.schema !== SCHEMA) {
      return true;
    }
    const latitude: number = AppStore.weatherLatitude();
    const longitude: number = AppStore.weatherLongitude();
    const moved: number = isNaN(latitude) || isNaN(longitude)
      ? Number.MAX_VALUE
      : CityIndex.distanceKm(latitude, longitude, place.latitude, place.longitude);
    const now: number = Date.now();
    // 任意一条满足即刷新：过期（含 5 分钟失败节流）或「低精度数据想升级回 1 小时源」（按前后台退避）。
    return WeatherLogic.needsFetch(
      now - cached.fetchedMillis,
      moved,
      now - cached.attemptMillis,
      cached.source,
      cached.stepHours,
      cached.primaryFailures,
      foreground
    );
  }

  /**
   * 应用回到前台 / 切换地点时该不该**立刻**取一次（不受剩余退避秒数限制）。
   *
   * 只在「当前是低精度数据」时为真：目标就是尽快升级回 Open-Meteo 的 1 小时网格。
   * 当前地点还没有任何缓存时 [needsRefresh] 本来就返回 true，不必再 force。
   */
  static shouldForceUpgrade(): boolean {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0) {
      return false;
    }
    return WeatherLogic.shouldForceUpgradeOnForeground(cached.source, cached.stepHours);
  }

  /**
   * 需要时取一次数；拿到新数据返回 true。
   *
   * @param force true = 忽略所有节流立刻取一次。用于「应用回到前台 / 用户换了地点」，
   *   以及「手里是低精度 3 小时数据、要尽快升级回 1 小时源」这几种情形（见 [shouldForceUpgrade]）。
   * @param foreground true = 应用在前台（页面可见）；卡片刷新路径传 false。
   */
  static async refreshIfNeeded(place: Place, force: boolean = false,
      foreground: boolean = true): Promise<boolean> {
    if (WeatherService.inFlight || (!force && !WeatherService.needsRefresh(place, foreground))) {
      return false;
    }
    WeatherService.inFlight = true;
    // 先记下尝试时刻：失败后按 5 分钟节流重试；成功时 save 会把它一起刷新。
    AppStore.markWeatherAttempt();
    const cachedBefore: CachedWeather = AppStore.weather();
    // 这次是不是「降级后重试主源」：只有这种失败才累计退避次数（首次降级本身不算一次重试失败）。
    const retryingFromLowPrecision: boolean =
      WeatherLogic.isLowPrecision(cachedBefore.source, cachedBefore.stepHours);
    let failure: string = '';
    try {
      // ① 主源。**失败一次就立刻降级**：5 秒超时拿不到直接问 7Timer!，不再隔 2 秒重试 ——
      //    界面可能正等着数据，宁可先用 3 小时粒度的备用源，也不要长时间空白。
      const body: string | null = await HttpUtil.getText(
        WeatherLogic.buildUrl(place.latitude, place.longitude), {}, WeatherLogic.HTTP_TIMEOUT_MILLIS);
      if (body === null) {
        failure = '主源 Open-Meteo 请求失败（网络错误 / 超时 / 非 2xx）';
      }
      const primary: PrimaryWeather | null = body === null ? null : WeatherLogic.parsePrimary(body);
      if (primary !== null) {
        // 成功切回主源：退避清零，回到普通的 30 分钟过期 / 5 分钟失败节流。
        AppStore.setWeatherPrimaryFailures(0);
        WeatherService.save(place, primary.snapshot, primary.hourly, WeatherSource.OPEN_METEO);
        WeatherService.record('主源成功', WeatherSource.OPEN_METEO, '');
        return true;
      }
      if (body !== null) {
        failure = '主源 Open-Meteo 响应解析失败（缺 current / hourly）';
      }
      // 降级后重试主源又失败 → 连续失败次数 +1（60→120→300 秒退避）。
      if (retryingFromLowPrecision) {
        AppStore.setWeatherPrimaryFailures(AppStore.weatherPrimaryFailures() + 1);
      }

      // ② 主源失败：缓存还没过期、**且确实属于当前这个地点**，就什么都不动，界面继续用缓存。
      //    （缓存属于别的城市时不能靠它「顶住」：界面本来就会显示占位符，这时该去问备用源。）
      const cached: CachedWeather = AppStore.weather();
      const hasCache: boolean = cached.fetchedMillis > 0;
      const cacheAge: number = hasCache ? Date.now() - cached.fetchedMillis : -1;
      const belongs: boolean = hasCache && WeatherService.belongsTo(place);
      if (WeatherLogic.fallbackFor(belongs, cacheAge) === WeatherFallback.KEEP_CACHE) {
        WeatherService.record('主源失败，沿用未过期的缓存', WeatherService.source(), failure);
        return false;
      }

      // ③ 缓存已过期（或根本没有）：问备用源 7Timer!，成功就整份换掉。
      const sevenTimerBody: string | null = await HttpUtil.getText(
        WeatherLogic.buildSevenTimerUrl(place.latitude, place.longitude), {}, WeatherLogic.HTTP_TIMEOUT_MILLIS);
      if (sevenTimerBody === null) {
        failure = `${failure}；备用源 7Timer! 请求失败`;
      } else {
        const points: HourPoint[] = WeatherLogic.parseSevenTimer(sevenTimerBody);
        const snapshot: WeatherSnapshot | null = WeatherLogic.snapshotAt(points, Math.floor(Date.now() / 1000));
        if (snapshot !== null) {
          WeatherService.save(place, snapshot, points, WeatherSource.SEVEN_TIMER);
          WeatherService.record('主源失败，已降级到 7Timer!', WeatherSource.SEVEN_TIMER, failure);
          return true;
        }
        failure = `${failure}；备用源 7Timer! 响应解析失败`;
      }

      // ④ 两个源都失败：旧数据继续显示（读取侧按 24 小时上限过滤），诊断里标注过期时长。
      const stale: string = WeatherService.staleLabel();
      WeatherService.record(
        `主源与备用源都失败，保留旧数据（${stale.length > 0 ? stale : '无缓存'}）`,
        WeatherService.source(),
        failure
      );
      return false;
    } finally {
      WeatherService.inFlight = false;
    }
  }

  /** 上次**尝试**取数的时刻（毫秒）；0 = 还没试过。诊断里显示。 */
  static lastAttemptMillis(): number {
    return AppStore.weather().attemptMillis;
  }

  /**
   * 距离下一次自动取数还有多少秒（诊断用）。
   *
   * - 低精度数据：60 秒轮询一次主源（[WeatherLogic.LOW_PRECISION_RETRY_MILLIS]）；
   * - 主源数据已过期：失败节流 5 分钟后再试（[WeatherLogic.RETRY_AFTER_FAILURE_MILLIS]）；
   * - 主源数据新鲜：30 分钟过期后才会再取（[WeatherLogic.TTL_MILLIS]）。
   */
  static nextRetrySeconds(): number {
    const cached: CachedWeather = AppStore.weather();
    if (cached.fetchedMillis <= 0) {
      return 0;
    }
    const now: number = Date.now();
    const age: number = now - cached.fetchedMillis;
    const sinceAttempt: number = now - cached.attemptMillis;
    if (WeatherLogic.isLowPrecision(cached.source, cached.stepHours)) {
      const delay: number = WeatherLogic.lowPrecisionRetryDelayMillis(
        cached.primaryFailures, true);
      return Math.max(0, Math.ceil((delay - sinceAttempt) / 1000));
    }
    if (age > WeatherLogic.TTL_MILLIS) {
      return Math.max(0, Math.ceil((WeatherLogic.RETRY_AFTER_FAILURE_MILLIS - sinceAttempt) / 1000));
    }
    return Math.max(0, Math.ceil((WeatherLogic.TTL_MILLIS - age) / 1000));
  }

  /** 写缓存（连同来源与步长一起，界面靠它排逐时行）。 */
  private static save(place: Place, snapshot: WeatherSnapshot, hourly: HourPoint[], source: string): void {
    AppStore.saveWeather(
      snapshot.temperatureC,
      snapshot.code,
      WeatherLogic.encodeHourly(hourly),
      SCHEMA,
      place.latitude,
      place.longitude,
      source,
      WeatherSource.stepHoursOf(source)
    );
    WeatherService.revisionCount++;
  }

  /** 把这一次取数的结果写进诊断（天气源 / 步长 / 过期分钟数 / 失败原因）。 */
  private static record(result: string, source: string, failure: string): void {
    const ageMinutes: number = WeatherService.ageMinutes();
    AppStore.saveWeatherDiag(result, WeatherSource.of(source), WeatherSource.stepHoursOf(source), ageMinutes, failure);
    console.info(`[weather] ${result} source=${WeatherSource.of(source)} step=${
      WeatherSource.stepHoursOf(source)}h age=${ageMinutes}min failure=${failure}`);
  }
}
