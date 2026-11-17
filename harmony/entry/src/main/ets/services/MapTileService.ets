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
  TileContent,
  uiStateOf
} from '../core/MapFallback';
import { Place } from '../core/Place';
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
  private static readonly USER_AGENT: string = 'TrueSolarTime-HarmonyOS/1.0 (map tiles)';

  static reset(): void {
    MapTileService.state = new MapFallbackState();
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
    if (viewportChanged) {
      // 程序化改中心/缩放会取消在飞的请求：接下来 2 秒的失败是假失败，别计入统计。
      MapTileService.state = MapFallback.markViewportSettling(MapTileService.state, Date.now());
    }
    const style: MapStyle = MapTilesLogic.styleFromKey(styleKey);
    await MapTileService.probeIfDue();
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

  /** 下载一块瓦片并做像素分析；网络失败 / 非图片 / 解码失败都返回 null。 */
  private static async fetchContent(url: string): Promise<TileContent | null> {
    const bytes: Uint8Array | null = await HttpUtil.getBytes(url,
      { 'User-Agent': MapTileService.USER_AGENT }, MapTileService.TIMEOUT_MILLIS);
    if (bytes === null || !MapTileService.looksLikeImage(bytes)) {
      return null;
    }
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
        : `${MapTileService.styleName(plan.effective)}（自动：${plan.effective === MapStyle.OSM ? '境外' : '境内'}）`);
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
      probeLine
    ];
  }

  private static styleName(style: MapStyle): string {
    if (style === MapStyle.OSM) {
      return 'OpenStreetMap';
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
