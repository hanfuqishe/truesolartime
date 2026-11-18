/**
 * 地图底图取数：OSM / 高德瓦片下载、空白检测、回退与降级（策略在 core/MapFallback.ets）。
 *
 * 这里只做「网络 + 解码 + 状态持有」：
 *   - 每块瓦片下载后校验 PNG/JPEG 魔数，再解成 256×256 像素；
 *   - 按步长 8 抽 32×32 个样本交给 MapTileLogic 判空白（只对高德源检测）；
 *   - 失败 / 空白都交给 MapFallback 的纯函数状态机；
 *   - 回退后每 5 分钟探测一次 z3 OSM 瓦片，成功即切回。
 */

import { image } from '@kit.ImageKit';
import { MapLayer, MapStyle, MapTile, MapTilesLogic } from '../core/MapTiles';
import {
  MapFallback,
  MapFallbackState,
  MapTileLogic,
  MapTilePlan,
  MapUiState,
  MapZoomPlan,
  ProbeCache,
  ProbeDecision,
  ProgressiveProbe,
  TileContent,
  applyDecision,
  cacheKey,
  needsProbe,
  tileOf,
  uiStateOf
} from '../core/MapFallback';
import { Place, PlaceSource } from '../core/Place';
import {
  UnknownLocationLogic,
  UnknownMapCache,
  UnknownMapDecision
} from '../core/LocationUnknown';
import { AppStore } from './Store';
import { HttpUtil } from './HttpUtil';

/** 一次底图加载的结果（界面只读它；uiState 相同就完全不更新）。 */
export class MapLoadResult {
  tiles: MapTile[] = [];
  zoom: number = MapFallback.DEFAULT_ZOOM;
  attribution: string = '';
  unavailable: boolean = false;
  degraded: boolean = false;
  fellBack: boolean = false;
  uiState: MapUiState = new MapUiState();
}

export class MapTileService {
  private static state: MapFallbackState = new MapFallbackState();
  private static lastStyleKey: string = 'auto';
  private static lastLatitude: number = 0;
  private static lastLongitude: number = 0;
  private static lastCountry: string = '';
  private static lastRequestedZoom: number = MapFallback.DEFAULT_ZOOM;
  private static lastAppliedZoom: number = MapFallback.DEFAULT_ZOOM;
  private static lastUnavailable: boolean = false;
  private static lastDegraded: boolean = false;
  private static probing: boolean = false;

  private static readonly TIMEOUT_MILLIS: number = 6000;
  private static readonly PROBE_TIMEOUT_MILLIS: number = 2500;
  private static readonly USER_AGENT: string = 'TrueSolarTime-HarmonyOS/1.0 (map tiles)';
  private static probeCache: ProbeCache = new ProbeCache();
  private static probeSession: ProgressiveProbe | null = null;
  private static probeListener: ((decision: ProbeDecision) => void) | null = null;
  private static lastCenterLat: number = 0;
  private static lastCenterLon: number = 0;
  private static lastWidthPx: number = 0;
  private static lastHeightPx: number = 0;

  static reset(): void {
    MapTileService.state = new MapFallbackState();
    MapTileService.probeCache = new ProbeCache();
    MapTileService.lastUnavailable = false;
    MapTileService.lastDegraded = false;
  }

  /** 下载并分析一屏瓦片；内部可能降级重试，直到 z3 或拿到内容。 */
  static async load(place: Place, styleKey: string, countryCode: string, centerLatitude: number,
      centerLongitude: number, requestedZoom: number, widthPx: number, heightPx: number,
      viewportChanged: boolean = false): Promise<MapLoadResult> {
    MapTileService.lastStyleKey = styleKey;
    MapTileService.lastLatitude = place.latitude;
    MapTileService.lastLongitude = place.longitude;
    MapTileService.lastCountry = countryCode;
    MapTileService.lastRequestedZoom = requestedZoom;
    MapTileService.lastCenterLat = centerLatitude;
    MapTileService.lastCenterLon = centerLongitude;
    MapTileService.lastWidthPx = widthPx;
    MapTileService.lastHeightPx = heightPx;
    if (viewportChanged) {
      // 程序化改中心/缩放会取消在飞的请求：接下来 2 秒的失败是假失败，别计入统计。
      MapTileService.state = MapFallback.markViewportSettling(MapTileService.state, Date.now());
    }
    const style: MapStyle = MapTilesLogic.styleFromKey(styleKey);
    const firstDecision: ProbeDecision | null = await MapTileService.probeIfNeeded(style, place, countryCode);
    await MapTileService.probeIfDue();
    if (firstDecision !== null) {
      return MapTileService.buildDecisionResult(firstDecision, place, countryCode, centerLatitude,
        centerLongitude, widthPx, heightPx);
    }
    // 探测判定不可用（4 秒什么都没有）：恒 z3，不逐级降级。
    if (MapTileService.probeSession !== null && MapTileService.probeSession.unavailable(Date.now())
      && !MapTileService.probeSession.hasContent) {
      const unavailable: MapLoadResult = new MapLoadResult();
      unavailable.zoom = MapFallback.MIN_ZOOM;
      unavailable.unavailable = true;
      unavailable.uiState.requestedZoom = MapFallback.MIN_ZOOM;
      unavailable.uiState.zoom = MapFallback.MIN_ZOOM;
      unavailable.uiState.unavailable = true;
      MapTileService.lastUnavailable = true;
      return unavailable;
    }
    // 探测已定级 → 不再逐块下载整屏做空白分析（那会把首屏拖回几十秒）：
    // 直接把瓦片 URL 交给 Image，依靠刚探测出的源与级别。
    if (!needsProbe(style, cacheKey(place.latitude, place.longitude), MapTileService.probeCache, Date.now())) {
      return MapTileService.buildFastResult(style, place, countryCode, centerLatitude, centerLongitude,
        requestedZoom, widthPx, heightPx);
    }
    let attempts: number = 0;
    while (attempts < 5) {
      attempts++;
      const plan: MapTilePlan = MapFallback.plan(style, place.latitude, place.longitude, countryCode,
        MapTileService.state);
      const zoomPlan: MapZoomPlan = MapFallback.zoomPlan(plan, requestedZoom, MapTileService.state);
      MapTileService.lastAppliedZoom = zoomPlan.zoom;
      MapTileService.lastDegraded = zoomPlan.degraded;
      if (zoomPlan.unavailable) {
        MapTileService.lastUnavailable = true;
        const result: MapLoadResult = new MapLoadResult();
        result.zoom = zoomPlan.zoom;
        result.unavailable = true;
        result.degraded = zoomPlan.degraded;
        result.fellBack = plan.fellBack;
        result.attribution = MapTileService.attributionFor(plan);
        result.uiState = uiStateOf(plan, zoomPlan);
        return result;
      }
      const layer: MapLayer = MapTilesLogic.layerForStyle(plan.effective, place.latitude, place.longitude,
        countryCode);
      const tiles: MapTile[] = MapTilesLogic.visibleTiles(layer, centerLatitude, centerLongitude,
        zoomPlan.zoom, widthPx, heightPx);
      let viewed: number = 0;
      let blankTiles: number = 0;
      let blankKinds: number = 0;
      for (const tile of tiles) {
        const content: TileContent | null = await MapTileService.fetchContent(tile.url);
        viewed++;
        if (content === null) {
          MapTileService.state = MapFallback.onTileFailed(style, place.latitude, place.longitude,
            countryCode, zoomPlan.zoom, MapTileService.state, Date.now());
          continue;
        }
        if (plan.effective !== MapStyle.OSM && content.isBlank) {
          // 先记下来：只有**看过的每一块都空白**才算这一屏空白（单块灰底可能是真·人烟稀少）。
          blankTiles++;
          blankKinds = content.colorKinds;
          continue;
        }
        MapTileService.state = MapFallback.onTileLoaded(style, place.latitude, place.longitude,
          countryCode, zoomPlan.zoom, MapTileService.state, Date.now());
      }
      if (viewed > 0 && blankTiles === viewed) {
        // 整屏都空白：按失败处理（一次一屏），继续走 z12 → z11 → z10 → z3 的降级链。
        MapTileService.state = MapFallback.onTileBlank(style, place.latitude, place.longitude,
          countryCode, zoomPlan.zoom, MapTileService.state, Date.now(), blankKinds);
      }
      if (viewed === 0) {
        break;
      }
      // 这一批失败 / 空白可能让「该级别没瓦片」成立：重新算一次计划，降过级就再取一屏。
      const nextPlan: MapTilePlan = MapFallback.plan(style, place.latitude, place.longitude, countryCode,
        MapTileService.state);
      const nextZoom: MapZoomPlan = MapFallback.zoomPlan(nextPlan, requestedZoom, MapTileService.state);
      if (nextZoom.unavailable) {
        MapTileService.lastUnavailable = true;
        const failed: MapLoadResult = new MapLoadResult();
        failed.zoom = nextZoom.zoom;
        failed.unavailable = true;
        failed.degraded = nextZoom.degraded;
        failed.fellBack = nextPlan.fellBack;
        failed.attribution = MapTileService.attributionFor(nextPlan);
        failed.uiState = uiStateOf(nextPlan, nextZoom);
        return failed;
      }
      if (nextZoom.zoom !== zoomPlan.zoom) {
        continue;
      }
      MapTileService.lastUnavailable = false;
      const result: MapLoadResult = new MapLoadResult();
      result.tiles = tiles;
      result.zoom = zoomPlan.zoom;
      result.degraded = zoomPlan.degraded;
      result.fellBack = plan.fellBack;
      result.attribution = MapTileService.attributionFor(plan);
      result.uiState = uiStateOf(plan, zoomPlan);
      return result;
    }
    const fallbackResult: MapLoadResult = new MapLoadResult();
    fallbackResult.zoom = MapTileService.lastAppliedZoom;
    fallbackResult.degraded = MapTileService.lastDegraded;
    fallbackResult.attribution = MapTileService.lastStyleKey.length > 0 ? MapTileService.currentAttribution() : '';
    const fallbackStyle: MapStyle = MapTilesLogic.styleFromKey(MapTileService.lastStyleKey);
    const fallbackPlan: MapTilePlan = MapFallback.plan(fallbackStyle, MapTileService.lastLatitude,
      MapTileService.lastLongitude, MapTileService.lastCountry, MapTileService.state);
    const fallbackZoom: MapZoomPlan = MapFallback.zoomPlan(fallbackPlan, MapTileService.lastRequestedZoom,
      MapTileService.state);
    fallbackResult.uiState = uiStateOf(fallbackPlan, fallbackZoom);
    return fallbackResult;
  }

  /**
   * 渐进升级：5 块并行探测（OSM z3/z12、高德 z12/z10/z3），一块回来就判断一次。
   * 同级两源都有内容时按区域偏好选源；偏好源空白则用另一源（先换源、再降级）。
   * 首块出图立即返回该决定；后续升级通过 [setProbeListener] 回调通知界面。
   */
  private static async probeIfNeeded(style: MapStyle, place: Place,
      countryCode: string): Promise<ProbeDecision | null> {
    const key: string = cacheKey(place.latitude, place.longitude);
    if (!needsProbe(style, key, MapTileService.probeCache, Date.now())) {
      return null;
    }
    const preferred: MapStyle = style === MapStyle.AUTO
      ? MapFallback.preferredStyle(style, place.latitude, place.longitude, countryCode)
      : style;
    const session: ProgressiveProbe = new ProgressiveProbe(Date.now(), preferred);
    MapTileService.probeSession = session;
    let firstDecision: ProbeDecision | null = null;
    const consider = (source: MapStyle, zoom: number, hasContent: boolean): void => {
      const now: number = Date.now();
      if (!session.consider(source, zoom, hasContent, now)) {
        return;
      }
      const decision: ProbeDecision = session.unavailable(now)
        ? new ProbeDecision(source, zoom, true)
        : new ProbeDecision(source, zoom, false);
      if (firstDecision === null) {
        firstDecision = decision;
      }
      MapTileService.state = applyDecision(MapTileService.state, decision, now);
      MapTileService.probeCache.key = key;
      MapTileService.probeCache.millis = now;
      MapTileService.probeCache.decision = decision;
      if (MapTileService.probeListener !== null) {
        MapTileService.probeListener(decision);
      }
    };
    MapTileService.probeTicket(tileOf(MapStyle.OSM, place.latitude, place.longitude, 3), false)
      .then((ok: boolean) => consider(MapStyle.OSM, 3, ok));
    // ESRI z3 / z12：境外自动的首选源，必须和 OSM 同级都探。
    MapTileService.probeTicket(tileOf(MapStyle.ESRI, place.latitude, place.longitude, 3), false)
      .then((ok: boolean) => consider(MapStyle.ESRI, 3, ok));
    MapTileService.probeTicket(tileOf(MapStyle.ESRI, place.latitude, place.longitude, 12), false)
      .then((ok: boolean) => consider(MapStyle.ESRI, 12, ok));
    // OSM z12：同级两源都探，才能「偏好源空白时先换源」。
    MapTileService.probeTicket(tileOf(MapStyle.OSM, place.latitude, place.longitude, 12), false)
      .then((ok: boolean) => consider(MapStyle.OSM, 12, ok));
    MapTileService.probeTicket(tileOf(MapStyle.AMAP_VECTOR, place.latitude, place.longitude, 12), true)
      .then((ok: boolean) => consider(MapStyle.AMAP_VECTOR, 12, ok));
    MapTileService.probeTicket(tileOf(MapStyle.AMAP_VECTOR, place.latitude, place.longitude, 10), true)
      .then((ok: boolean) => consider(MapStyle.AMAP_VECTOR, 10, ok));
    MapTileService.probeTicket(tileOf(MapStyle.AMAP_VECTOR, place.latitude, place.longitude, 3), true)
      .then((ok: boolean) => consider(MapStyle.AMAP_VECTOR, 3, ok));
    // 等到「有首图」或「4 秒什么都没有」为止；期间后续结果会继续通过 listener 升级。
    await new Promise<void>((resolve: () => void) => {
      const timer: number = setInterval(() => {
        const now: number = Date.now();
        if (session.hasContent || session.unavailable(now)) {
          clearInterval(timer);
          resolve();
        }
      }, 40);
    });
    if (firstDecision === null) {
      MapTileService.probeCache.key = key;
      MapTileService.probeCache.millis = Date.now();
    }
    return firstDecision;
  }

  /** 界面注册渐进升级回调：更高精度回来时不必重新拉整屏，只换源/级别。 */
  static setProbeListener(listener: ((decision: ProbeDecision) => void) | null): void {
    MapTileService.probeListener = listener;
  }

  /** 升级用结果：视口中心保持不变，只换源 / 级别。 */
  static upgradeResult(decision: ProbeDecision): MapLoadResult {
    const place: Place = new Place(MapTileService.lastCenterLat, MapTileService.lastCenterLon,
      PlaceSource.MANUAL, '', '');
    return MapTileService.buildDecisionResult(decision, place, '', MapTileService.lastCenterLat,
      MapTileService.lastCenterLon, MapTileService.lastWidthPx, MapTileService.lastHeightPx);
  }

  /** 用户已手动平移/缩放：冻结后续升级。 */
  static markMapInteraction(): void {
    if (MapTileService.probeSession !== null) {
      MapTileService.probeSession.markUserInteracted();
    }
  }

  /** 诊断：`首图 z3 @312ms，升级 z12 @1830ms`。 */
  static probeDiagnostic(): string {
    return MapTileService.probeSession === null ? '无探测' : MapTileService.probeSession.describe(Date.now());
  }

  /** 单块探测：魔数校验；高德的块还要解像素判空白（空白不算有内容）。 */
  private static async probeTicket(url: string, checkBlank: boolean): Promise<boolean> {
    const bytes: Uint8Array | null = await HttpUtil.getBytes(url,
      { 'User-Agent': MapTileService.USER_AGENT }, MapTileService.PROBE_TIMEOUT_MILLIS);
    if (bytes === null || !MapTileService.looksLikeImage(bytes)) {
      return false;
    }
    if (!checkBlank) {
      return true;
    }
    const content: TileContent | null = await MapTileService.decodeContent(bytes);
    return content !== null && !content.isBlank;
  }

  /** 未知态地图：z3 全球底图；有缓存零探测，否则并行探 2 块 z3（2 秒封顶），都失败 → 不可用。 */
  static async loadUnknown(widthPx: number, heightPx: number): Promise<MapLoadResult> {
    MapTileService.lastStyleKey = 'auto';
    MapTileService.lastRequestedZoom = UnknownLocationLogic.MAP_ZOOM;
    const cache: UnknownMapCache = new UnknownMapCache();
    cache.source = AppStore.unknownMapSource();
    cache.millis = AppStore.unknownMapMillis();
    let decision: UnknownMapDecision;
    if (UnknownLocationLogic.cacheUsable(cache, Date.now())) {
      decision = UnknownLocationLogic.decideMap(cache, Date.now(), false, false, false);
    } else {
      // 未知态无缓存：三块 z3（ESRI / OSM / 高德）并行；OSM 可能被污染、高德境外空白，不能少 ESRI。
      const esriProbe: Promise<boolean> = MapTileService.probeTicket(
        UnknownLocationLogic.probeTile(MapStyle.ESRI), false);
      const osmProbe: Promise<boolean> = MapTileService.probeTicket(
        UnknownLocationLogic.probeTile(MapStyle.OSM), false);
      const amapProbe: Promise<boolean> = MapTileService.probeTicket(
        UnknownLocationLogic.probeTile(MapStyle.AMAP_VECTOR), true);
      const all: Promise<boolean[]> = Promise.all([esriProbe, osmProbe, amapProbe]);
      const timeout: Promise<boolean[]> = new Promise<boolean[]>((resolve: (value: boolean[]) => void) => {
        setTimeout(() => resolve([false, false, false]), UnknownLocationLogic.PROBE_TIMEOUT_MILLIS);
      });
      const results: boolean[] = await Promise.race([all, timeout]);
      decision = UnknownLocationLogic.decideMap(null, Date.now(), results[0], results[1], results[2]);
      if (!decision.unavailable) {
        AppStore.saveUnknownMapSource(decision.source === MapStyle.ESRI ? 'esri'
          : (decision.source === MapStyle.OSM ? 'osm' : 'amap'));
      }
    }
    MapTileService.lastUnavailable = decision.unavailable;
    const result: MapLoadResult = new MapLoadResult();
    result.zoom = decision.zoom;
    result.unavailable = decision.unavailable;
    result.uiState = new MapUiState();
    result.uiState.requestedZoom = decision.zoom;
    result.uiState.source = decision.source;
    result.uiState.zoom = decision.zoom;
    result.uiState.unavailable = decision.unavailable;
    result.attribution = decision.unavailable ? '' : MapTilesLogic.layerForStyle(decision.source, 25.0, 110.0).attribution;
    if (!decision.unavailable) {
      const layer: MapLayer = MapTilesLogic.layerForStyle(decision.source, 25.0, 110.0);
      result.tiles = MapTilesLogic.visibleTiles(layer, 25.0, 110.0, UnknownLocationLogic.MAP_ZOOM,
        widthPx, heightPx);
    }
    return result;
  }

  /** 由一次探测决定直接生成结果（首图 / 升级都走这里，不重新拉整屏）。 */
  private static buildDecisionResult(decision: ProbeDecision, place: Place, countryCode: string,
      centerLatitude: number, centerLongitude: number, widthPx: number, heightPx: number): MapLoadResult {
    const result: MapLoadResult = new MapLoadResult();
    result.zoom = decision.zoom;
    result.unavailable = decision.unavailable;
    result.uiState = new MapUiState();
    result.uiState.requestedZoom = decision.zoom;
    result.uiState.source = decision.source;
    result.uiState.zoom = decision.zoom;
    result.uiState.unavailable = decision.unavailable;
    result.attribution = decision.unavailable ? '' : MapTilesLogic.layerForStyle(decision.source,
      place.latitude, place.longitude, countryCode).attribution;
    if (!decision.unavailable) {
      const layer: MapLayer = MapTilesLogic.layerForStyle(decision.source, place.latitude, place.longitude,
        countryCode);
      result.tiles = MapTilesLogic.visibleTiles(layer, centerLatitude, centerLongitude, decision.zoom,
        widthPx, heightPx);
    }
    MapTileService.lastAppliedZoom = decision.zoom;
    MapTileService.lastUnavailable = decision.unavailable;
    return result;
  }

  /** 探测结果新鲜时的快速路径：只算 plan/zoom + 瓦片 URL，不做整屏下载与空白分析。 */
  private static buildFastResult(style: MapStyle, place: Place, countryCode: string, centerLatitude: number,
      centerLongitude: number, requestedZoom: number, widthPx: number, heightPx: number): MapLoadResult {
    const plan: MapTilePlan = MapFallback.plan(style, place.latitude, place.longitude, countryCode,
      MapTileService.state);
    const zoomPlan: MapZoomPlan = MapFallback.zoomPlan(plan, requestedZoom, MapTileService.state);
    const result: MapLoadResult = new MapLoadResult();
    result.zoom = zoomPlan.zoom;
    result.degraded = zoomPlan.degraded;
    result.unavailable = zoomPlan.unavailable;
    result.fellBack = plan.fellBack;
    result.attribution = MapTileService.attributionFor(plan);
    result.uiState = uiStateOf(plan, zoomPlan);
    MapTileService.lastAppliedZoom = zoomPlan.zoom;
    MapTileService.lastDegraded = zoomPlan.degraded;
    MapTileService.lastUnavailable = zoomPlan.unavailable;
    if (!zoomPlan.unavailable) {
      const layer: MapLayer = MapTilesLogic.layerForStyle(plan.effective, place.latitude, place.longitude,
        countryCode);
      result.tiles = MapTilesLogic.visibleTiles(layer, centerLatitude, centerLongitude, zoomPlan.zoom,
        widthPx, heightPx);
    }
    return result;
  }

  /** 下载一块瓦片并做像素分析；网络失败 / 非图片 / 解码失败都返回 null。 */
  private static async fetchContent(url: string): Promise<TileContent | null> {
    const bytes: Uint8Array | null = await HttpUtil.getBytes(url,
      { 'User-Agent': MapTileService.USER_AGENT }, MapTileService.TIMEOUT_MILLIS);
    if (bytes === null || !MapTileService.looksLikeImage(bytes)) {
      return null;
    }
    return MapTileService.decodeContent(bytes);
  }

  /** 已下载的字节 → 256×256 像素 → 32×32 采样 → 空白判定。 */
  private static async decodeContent(bytes: Uint8Array): Promise<TileContent | null> {
    try {
      const source: image.ImageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
      const pixelMap: image.PixelMap = await source.createPixelMap({
        desiredSize: { width: 256, height: 256 }
      });
      const buffer: ArrayBuffer = new ArrayBuffer(256 * 256 * 4);
      await pixelMap.readPixelsToBuffer(buffer);
      const rgba: number[] = [];
      const raw: Uint8Array = new Uint8Array(buffer);
      for (let index = 0; index < raw.length; index++) {
        rgba.push(raw[index]);
      }
      const samples: number[] = MapTileLogic.sampleNearest(rgba, 256, 256);
      pixelMap.release();
      source.release();
      return MapTileLogic.analyze(samples);
    } catch (error) {
      return null;
    }
  }

  /** PNG / JPEG 魔数：DNS 污染返回的 200 假页面不算瓦片。 */
  private static looksLikeImage(bytes: Uint8Array): boolean {
    if (bytes.length < 2) {
      return false;
    }
    const png: boolean = bytes[0] === 0x89 && bytes[1] === 0x50;
    const jpeg: boolean = bytes[0] === 0xFF && bytes[1] === 0xD8;
    return png || jpeg;
  }

  /** 回退后每 5 分钟探测一次 z3 OSM 瓦片；成功即切回。 */
  private static async probeIfDue(): Promise<void> {
    if (MapTileService.probing || !MapFallback.probeDue(MapTileService.state, Date.now())) {
      return;
    }
    MapTileService.probing = true;
    try {
      const bytes: Uint8Array | null = await HttpUtil.getBytes(MapFallback.PROBE_URL,
        { 'User-Agent': MapTileService.USER_AGENT }, 4000);
      const reachable: boolean = bytes !== null && MapTileService.looksLikeImage(bytes);
      MapTileService.state = MapFallback.onProbeResult(MapTileService.state, reachable, Date.now());
    } finally {
      MapTileService.probing = false;
    }
  }

  /** 署名：跟随实际瓦片源；回退时追加原因。 */
  private static attributionFor(plan: MapTilePlan): string {
    const layer: MapLayer = MapTilesLogic.layerForStyle(plan.effective, MapTileService.lastLatitude,
      MapTileService.lastLongitude, MapTileService.lastCountry);
    if (plan.requested !== MapStyle.AUTO) {
      return layer.attribution;
    }
    if (plan.fellBack) {
      return `${layer.attribution} · OSM 不可达，已回退高德`;
    }
    return layer.attribution;
  }

  private static currentAttribution(): string {
    const style: MapStyle = MapTilesLogic.styleFromKey(MapTileService.lastStyleKey);
    const plan: MapTilePlan = MapFallback.plan(style, MapTileService.lastLatitude,
      MapTileService.lastLongitude, MapTileService.lastCountry, MapTileService.state);
    return MapTileService.attributionFor(plan);
  }

  /** 设置页诊断：实际源（含原因）/ 样式 / 首选 / 缩放与降级 / 瓦片状态 / 失败次数 / 空白判定 / 下次探测。 */
  static diagnostics(): string[] {
    const style: MapStyle = MapTilesLogic.styleFromKey(MapTileService.lastStyleKey);
    const plan: MapTilePlan = MapFallback.plan(style, MapTileService.lastLatitude,
      MapTileService.lastLongitude, MapTileService.lastCountry, MapTileService.state);
    const zoomPlan: MapZoomPlan = MapFallback.zoomPlan(plan, MapTileService.lastRequestedZoom,
      MapTileService.state);
    const source: string = plan.requested !== MapStyle.AUTO
      ? `${MapTileService.styleName(plan.effective)}（手动选择，不回退）`
      : (plan.fellBack
        ? `高德（OSM 失败 ${plan.fallbackFailures} 次后回退）`
        : `${MapTileService.styleName(plan.effective)}（自动：${
          plan.effective === MapStyle.OSM || plan.effective === MapStyle.ESRI ? '境外' : '境内'}）`);
    const zoomLine: string = `地图缩放 = ${zoomPlan.zoom}` +
      (zoomPlan.degraded ? `（已降级：请求 ${zoomPlan.requested}）` : '');
    const statusLine: string = '瓦片状态 = ' + (MapTileService.lastUnavailable
      ? '最低级别也没有瓦片（界面显示「底图不可用」）' : '正常');
    const blankLine: string = MapTileService.state.blankTileCount > 0
      ? `空白瓦片判定 = 已触发 ${MapTileService.state.blankTileCount} 次（最近：z${
        MapTileService.state.lastBlankZoom} 颜色种类 ${MapTileService.state.lastBlankColorKinds}）`
      : '空白瓦片判定 = 未触发（只检测高德瓦片）';
    const failures: string = `OSM 失败次数 = ${
      style === MapStyle.AUTO ? MapTileService.state.osmFailures : 0}`;
    const probeAt: number = MapTileService.state.probeAtMillis;
    let probeLine: string;
    if (style !== MapStyle.AUTO) {
      probeLine = '下次探测 OSM = 不探测（手动选择底图）';
    } else if (!MapTileService.state.fellBack || probeAt < 0) {
      probeLine = '下次探测 OSM = 无（未回退）';
    } else {
      const wait: number = Math.max(0, probeAt - Date.now());
      probeLine = `下次探测 OSM = ${Math.ceil(wait / 1000)} 秒后`;
    }
    return [
      `地图底图 = ${source}`,
      `地图底图样式 = ${MapTileService.styleName(style)}`,
      `首选底图 = ${MapTileService.styleName(plan.preferred)}`,
      zoomLine,
      statusLine,
      blankLine,
      failures,
      `渐进升级 = ${MapTileService.probeDiagnostic()}`,
      probeLine
    ];
  }

  private static styleName(style: MapStyle): string {
    if (style === MapStyle.OSM) {
      return 'OpenStreetMap';
    }
    if (style === MapStyle.ESRI) {
      return 'ESRI';
    }
    if (style === MapStyle.AMAP_VECTOR) {
      return '高德矢量';
    }
    if (style === MapStyle.AMAP_SATELLITE) {
      return '高德卫星';
    }
    return '自动';
  }
}
