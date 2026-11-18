/**
 * 「定位不可用（未知态）」：触发判定、占位符、系统时区、逐时六格与未知态地图快路径。
 *
 * 纯逻辑，供 `pages/Index.ets` 与 `core-check.ts` 使用：
 *   - 触发：跟随 GPS 的**意图**为 true 且拿不到有效定位（未授权 / 20 秒无 fix）；
 *   - 预设城市、手动坐标不受影响；
 *   - 未知态地图：z3 全球底图；有缓存（上次成功源，10 分钟）零探测；否则并行探 2 块 z3
 *     （东亚瓦片 x=6,y=2，避免 (0,0) 被高德空白判定误判），2 秒封顶；都失败 → 不可用；
 *   - 未知态不进回退/降级状态机。
 */

import { MapLayer, MapStyle, MapTilesLogic } from './MapTiles';

/** 未知态的所有占位符（只含 '-'、':'、'°'，不用全角/长破折号）。 */
export class LocationPlaceholders {
  static readonly TIME: string = '--:--:--';
  static readonly SHORT: string = '--';
  static readonly DASH: string = '--';
  static readonly TEMPERATURE: string = '-°';
  static readonly UNKNOWN_PLACE: string = '定位不可用';

  /** 文本是否只由占位符允许的字符组成。 */
  static isPlaceholderText(text: string): boolean {
    if (text.length === 0) {
      return false;
    }
    for (let index = 0; index < text.length; index++) {
      const ch: string = text.charAt(index);
      if (ch !== '-' && ch !== ':' && ch !== '°') {
        return false;
      }
    }
    return true;
  }
}

/** 未知态地图的一次决定：源 / 是否可用 / 是否命中缓存。 */
export class UnknownMapDecision {
  source: MapStyle;
  zoom: number;
  unavailable: boolean;
  fromCache: boolean;

  constructor(source: MapStyle, zoom: number, unavailable: boolean, fromCache: boolean) {
    this.source = source;
    this.zoom = zoom;
    this.unavailable = unavailable;
    this.fromCache = fromCache;
  }
}

/** 未知态地图缓存记录（只被未知态读写）。 */
export class UnknownMapCache {
  source: string = '';
  millis: number = -1;
  latitude: number = 0;
  longitude: number = 0;
}

export class UnknownLocationLogic {
  /** 未知态地图固定 z3，不逐级降级。 */
  static readonly MAP_ZOOM: number = 3;
  /** 未知态只用东亚瓦片（x=6, y=2），不要 (0,0) —— 高德会把那里判成空白。 */
  static readonly PROBE_TILE_X: number = 6;
  static readonly PROBE_TILE_Y: number = 2;
  /** 无缓存时两块 z3 并行探测的封顶时间。 */
  static readonly PROBE_TIMEOUT_MILLIS: number = 2000;
  /** 未知态地图缓存 TTL。 */
  static readonly CACHE_TTL_MILLIS: number = 10 * 60 * 1000;
  /** 授权后 20 秒仍无 fix → 未知态。 */
  static readonly FIX_TIMEOUT_MILLIS: number = 20 * 1000;

  /** 只有「跟随 GPS 的意图」+「没有有效定位」同时成立才是未知态。 */
  static isUnknown(gpsIntent: boolean, hasFix: boolean): boolean {
    return gpsIntent && !hasFix;
  }

  /**
   * 系统时区偏移（秒）。
   *
   * 注意不能用负数当「没传」哨兵：西半球偏移本身就是负数（如 UTC−5 = −18000）。
   * 需要「没有值」时请传 null，由 [offsetSecondsOr] 处理。
   */
  static systemOffsetSeconds(nowMillis: number): number {
    return -new Date(nowMillis).getTimezoneOffset() * 60;
  }

  /** 偏移值缺失（null）时退回系统时区；0 是合法偏移（UTC）。 */
  static offsetSecondsOr(value: number | null, nowMillis: number): number {
    return value === null ? UnknownLocationLogic.systemOffsetSeconds(nowMillis) : value;
  }

  /** 未知态逐时六格：首格「现在」，其余按系统时间逐小时（跨午夜回绕）。 */
  static hourlyLabels(nowEpochSeconds: number, zoneOffsetSeconds: number, language: string,
      count: number = 6): string[] {
    const labels: string[] = [];
    const localMillis: number = (nowEpochSeconds + zoneOffsetSeconds) * 1000;
    const localDate: Date = new Date(localMillis);
    for (let index = 0; index < count; index++) {
      if (index === 0) {
        labels.push(language.startsWith('zh') ? '现在' : 'Now');
      } else {
        const hour: number = (localDate.getUTCHours() + index) % 24;
        labels.push(language.startsWith('zh') ? `${hour}时` : `${hour}:00`);
      }
    }
    return labels;
  }

  /** 未知态逐时温度：六格全是 `-°`。 */
  static hourlyTemperatures(count: number = 6): string[] {
    const temps: string[] = [];
    for (let index = 0; index < count; index++) {
      temps.push(LocationPlaceholders.TEMPERATURE);
    }
    return temps;
  }

  /** 未知态圆盘：昼弧 180°（-180°→0°），夜弧 180°，地平线过圆心。 */
  static dayArcStartDegrees(): number {
    return -180;
  }

  static dayArcSweepDegrees(): number {
    return 180;
  }

  /** 缓存是否仍可用：同源、10 分钟内。 */
  static cacheUsable(cache: UnknownMapCache | null, nowMillis: number): boolean {
    if (cache === null || cache.source.length === 0 || cache.millis < 0) {
      return false;
    }
    return nowMillis - cache.millis <= UnknownLocationLogic.CACHE_TTL_MILLIS;
  }

  /** 有缓存 → 直接用上次成功的源 + z3；无缓存 → 等两块 z3 探测结果。 */
  static decideMap(cache: UnknownMapCache | null, nowMillis: number,
      osmContent: boolean, amapContent: boolean): UnknownMapDecision {
    if (UnknownLocationLogic.cacheUsable(cache, nowMillis)) {
      const source: MapStyle = cache === null || cache.source !== 'osm' ? MapStyle.AMAP_VECTOR : MapStyle.OSM;
      return new UnknownMapDecision(source, UnknownLocationLogic.MAP_ZOOM, false, true);
    }
    if (osmContent) {
      return new UnknownMapDecision(MapStyle.OSM, UnknownLocationLogic.MAP_ZOOM, false, false);
    }
    if (amapContent) {
      return new UnknownMapDecision(MapStyle.AMAP_VECTOR, UnknownLocationLogic.MAP_ZOOM, false, false);
    }
    return new UnknownMapDecision(MapStyle.AMAP_VECTOR, UnknownLocationLogic.MAP_ZOOM, true, false);
  }

  /** 未知态探测瓦片 URL（东亚 z3）。 */
  static probeTile(source: MapStyle): string {
    const layer: MapLayer = MapTilesLogic.layerForStyle(source, 25.0, 110.0);
    return MapTilesLogic.tileUrl(layer, UnknownLocationLogic.MAP_ZOOM,
      UnknownLocationLogic.PROBE_TILE_X, UnknownLocationLogic.PROBE_TILE_Y);
  }
}
