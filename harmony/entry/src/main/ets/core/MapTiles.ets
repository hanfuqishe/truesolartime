/**
 * 位置地图的底图与瓦片计算，规则与 Android 端 `map/MapTileSources.kt` 一致：
 *
 * - 境内用高德栅格瓦片（中文地名、路网更细、无需 API Key），境外用 OpenStreetMap；
 * - 高德底图是 GCJ-02 坐标，标点前要把 WGS-84 转成 GCJ-02，数据层始终保持 WGS-84；
 * - 瓦片是标准的 Web Mercator 金字塔，每片 256 px。
 *
 * 这里只有纯计算（坐标转换、瓦片编号与摆放），绘制放在 pages/Index.ets。
 */

/** 一块瓦片的边长（像素）与缩放范围，与 Android 端相同。 */
export const TILE_PX: number = 256;
export const MIN_ZOOM: number = 3;
export const MAX_ZOOM: number = 18;
export const DEFAULT_ZOOM: number = 12;

const EARTH_AXIS: number = 6378245.0;
const ECCENTRICITY: number = 0.00669342162296594323;
/** 高德瓦片节点，轮流使用以免单个域名被限流。 */
const AMAP_HOSTS: string[] = ['webrd01', 'webrd02', 'webrd03', 'webrd04'];

/** 底图坐标系：高德是 GCJ-02，OSM 是 WGS-84。 */
export enum MapDatum {
  WGS84 = 0,
  GCJ02 = 1
}

export class MapLayer {
  /** 用于拼接瓦片地址与缓存的稳定标识。 */
  name: string;
  datum: MapDatum;
  attribution: string;

  constructor(name: string, datum: MapDatum, attribution: string) {
    this.name = name;
    this.datum = datum;
    this.attribution = attribution;
  }
}

const AMAP_LAYER: MapLayer = new MapLayer('amap-vector', MapDatum.GCJ02, '底图 © 高德地图');
const OSM_LAYER: MapLayer = new MapLayer('osm', MapDatum.WGS84, '地图数据 © OpenStreetMap 贡献者');

/** 一块待绘制的瓦片：左上角相对视口左上角的偏移（像素）。 */
export class MapTile {
  url: string;
  leftPx: number;
  topPx: number;

  constructor(url: string, leftPx: number, topPx: number) {
    this.url = url;
    this.leftPx = leftPx;
    this.topPx = topPx;
  }
}

export class MapTilesLogic {
  /** GCJ-02 的适用边界（与 Android 端同一套判断），境外不加偏移。 */
  static isInChina(latitude: number, longitude: number): boolean {
    return longitude >= 72.004 && longitude <= 137.8347 && latitude >= 0.8293 && latitude <= 55.8271;
  }

  /** 自动选图：境内高德，境外 OSM。 */
  static layerFor(latitude: number, longitude: number): MapLayer {
    return MapTilesLogic.isInChina(latitude, longitude) ? AMAP_LAYER : OSM_LAYER;
  }

  /** WGS-84 → GCJ-02；境外原样返回。 */
  static toGcj02(latitude: number, longitude: number): number[] {
    if (!MapTilesLogic.isInChina(latitude, longitude)) {
      return [latitude, longitude];
    }
    const x: number = longitude - 105.0;
    const y: number = latitude - 35.0;
    let deltaLat: number = MapTilesLogic.transformLatitude(x, y);
    let deltaLon: number = MapTilesLogic.transformLongitude(x, y);
    const radLat: number = latitude / 180.0 * Math.PI;
    const sinLat: number = Math.sin(radLat);
    const magic: number = 1 - ECCENTRICITY * sinLat * sinLat;
    const sqrtMagic: number = Math.sqrt(magic);
    deltaLat = deltaLat * 180.0 / (EARTH_AXIS * (1 - ECCENTRICITY) / (magic * sqrtMagic) * Math.PI);
    deltaLon = deltaLon * 180.0 / (EARTH_AXIS / sqrtMagic * Math.cos(radLat) * Math.PI);
    return [latitude + deltaLat, longitude + deltaLon];
  }

  /** 该底图上用来摆放标点的坐标。 */
  static displayPoint(layer: MapLayer, latitude: number, longitude: number): number[] {
    return layer.datum === MapDatum.GCJ02 ? MapTilesLogic.toGcj02(latitude, longitude) : [latitude, longitude];
  }

  /** 经纬度 → 该缩放级下的瓦片坐标（带小数，方便做小数偏移）。 */
  static tilePoint(latitude: number, longitude: number, zoom: number): number[] {
    const scale: number = Math.pow(2, zoom);
    const x: number = (longitude + 180.0) / 360.0 * scale;
    const clampedLat: number = Math.max(-85.05112878, Math.min(85.05112878, latitude));
    const rad: number = clampedLat / 180.0 * Math.PI;
    const y: number = (1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2.0 * scale;
    return [x, y];
  }

  /** 瓦片坐标（带小数）→ 经纬度。 */
  static pointToLatLon(x: number, y: number, zoom: number): number[] {
    const scale: number = Math.pow(2, zoom);
    const longitude: number = x / scale * 360.0 - 180.0;
    const n: number = Math.PI - 2.0 * Math.PI * y / scale;
    const latitude: number = 180.0 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
    return [latitude, longitude];
  }

  /** 把中心点平移若干像素（手指拖动），返回新的中心经纬度。 */
  static shift(latitude: number, longitude: number, zoom: number, deltaXPx: number, deltaYPx: number): number[] {
    const point: number[] = MapTilesLogic.tilePoint(latitude, longitude, zoom);
    const scale: number = Math.pow(2, zoom);
    let x: number = point[0] - deltaXPx / TILE_PX;
    let y: number = point[1] - deltaYPx / TILE_PX;
    // 经度方向首尾相接，纬度方向夹在有效范围内，避免拖出地图。
    x = (x % scale + scale) % scale;
    y = Math.max(0, Math.min(scale, y));
    return MapTilesLogic.pointToLatLon(x, y, zoom);
  }

  /**
   * 覆盖整个视口所需的瓦片，坐标已换算成相对视口左上角的像素偏移。
   * 中心点落在视口正中，所以偏移量由「瓦片编号 − 中心的小数瓦片坐标」决定。
   */
  static visibleTiles(layer: MapLayer, latitude: number, longitude: number, zoom: number,
    widthPx: number, heightPx: number): MapTile[] {
    const center: number[] = MapTilesLogic.tilePoint(latitude, longitude, zoom);
    const count: number = Math.pow(2, zoom);
    const firstX: number = Math.floor(center[0] - widthPx / 2 / TILE_PX);
    const firstY: number = Math.floor(center[1] - heightPx / 2 / TILE_PX);
    const lastX: number = Math.floor(center[0] + widthPx / 2 / TILE_PX);
    const lastY: number = Math.floor(center[1] + heightPx / 2 / TILE_PX);
    const tiles: MapTile[] = [];
    for (let tileY: number = Math.max(0, firstY); tileY <= Math.min(count - 1, lastY); tileY++) {
      for (let tileX: number = firstX; tileX <= lastX; tileX++) {
        const wrappedX: number = ((tileX % count) + count) % count;
        tiles.push(new MapTile(
          MapTilesLogic.tileUrl(layer, zoom, wrappedX, tileY),
          (tileX - center[0]) * TILE_PX + widthPx / 2,
          (tileY - center[1]) * TILE_PX + heightPx / 2
        ));
      }
    }
    return tiles;
  }

  static tileUrl(layer: MapLayer, zoom: number, tileX: number, tileY: number): string {
    if (layer.datum === MapDatum.GCJ02) {
      const host: string = AMAP_HOSTS[(tileX + tileY) % AMAP_HOSTS.length];
      return `https://${host}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8` +
        `&x=${tileX}&y=${tileY}&z=${zoom}`;
    }
    return `https://tile.openstreetmap.org/${zoom}/${tileX}/${tileY}.png`;
  }

  static clampZoom(zoom: number): number {
    return Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, Math.round(zoom)));
  }

  private static transformLatitude(x: number, y: number): number {
    let result: number = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
    result += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
    result += (20.0 * Math.sin(y * Math.PI) + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0;
    result += (160.0 * Math.sin(y / 12.0 * Math.PI) + 320.0 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0;
    return result;
  }

  private static transformLongitude(x: number, y: number): number {
    let result: number = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
    result += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
    result += (20.0 * Math.sin(x * Math.PI) + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0;
    result += (150.0 * Math.sin(x / 12.0 * Math.PI) + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0;
    return result;
  }
}
