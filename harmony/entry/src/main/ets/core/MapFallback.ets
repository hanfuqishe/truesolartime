/**
 * 地图底图兜底：空白瓦片判定 + 回退/降级状态机（纯逻辑，不碰网络与 UI）。
 *
 * 与 Android 的 `TileBlank` / `MapFallback` 同一套数值：
 *   - 首选仍是「境内高德、境外 OSM」；
 *   - 只有**自动**模式才回退：OSM 连续失败 3 次 → 改用高德；任意一块 OSM 成功即清零；
 *   - 手动选择底图不回退、不探测、不降级；
 *   - 高德对境外常回 200 的空白瓦片（灰底 + 水印），按失败处理；
 *   - 降级链 z12 → z11 → z10 → z3（全球底图），z3 仍空白 → 界面显示「底图不可用」；
 *   - 回退后每 5 分钟探测一次 OSM（z3 小瓦片 + PNG/JPEG 魔数），成功即切回并清零。
 *
 * 采样约定：调用方把 256×256 的瓦片按步长 8 抽成 32×32 个 0xRRGGBB 样本再交给
 * [MapTileAnalysis.analyze]；本文件只吃颜色数组。
 */

import { MapStyle } from './MapTiles';
import { SolarTimeMath } from './SolarTimeMath';

/** 一块瓦片的像素分析结果。 */
export class TileContent {
  sampleCount: number;
  colorKinds: number;
  variance: number;
  blueShare: number;
  isOcean: boolean;
  isBlank: boolean;

  constructor(sampleCount: number = 0, colorKinds: number = 0, variance: number = 0,
      blueShare: number = 0, isOcean: boolean = false, isBlank: boolean = false) {
    this.sampleCount = sampleCount;
    this.colorKinds = colorKinds;
    this.variance = variance;
    this.blueShare = blueShare;
    this.isOcean = isOcean;
    this.isBlank = isBlank;
  }
}

export class MapTileLogic {
  /** 采样步长（像素）：256 / 8 = 32。 */
  static readonly SAMPLE_STEP: number = 8;
  static readonly SAMPLE_SIDE: number = 32;
  /** 颜色量化：每通道只留高 4 位。 */
  static readonly QUANT_SHIFT: number = 4;
  /** 颜色种类少于 8 且方差 < 400 → 空白；7 种算空白，8 种不算。 */
  static readonly MIN_COLOR_KINDS: number = 8;
  static readonly VARIANCE_THRESHOLD: number = 400;
  /** 方差 < 12 → 几乎单色，无论颜色种类都算空白。 */
  static readonly MONO_VARIANCE: number = 12;
  /** 蓝色（海面）占比 ≥ 0.6 → 海洋，算有内容。 */
  static readonly OCEAN_BLUE_SHARE: number = 0.6;
  static readonly OCEAN_MIN_SATURATION: number = 0.22;
  /** 判为海面所需的最低亮度。 */
  static readonly OCEAN_MIN_BRIGHTNESS: number = 60;

  /** 把一块 256×256 的 RGBA 像素按步长 8 抽成 32×32 的 0xRRGGBB 样本（最近邻，不插值）。 */
  static sampleNearest(rgba: number[], width: number, height: number): number[] {
    const colors: number[] = [];
    for (let y: number = 0; y < height; y += MapTileLogic.SAMPLE_STEP) {
      for (let x: number = 0; x < width; x += MapTileLogic.SAMPLE_STEP) {
        const index: number = (y * width + x) * 4;
        if (index + 2 < rgba.length) {
          colors.push((rgba[index] << 16) | (rgba[index + 1] << 8) | rgba[index + 2]);
        }
      }
    }
    return colors;
  }

  /** 分析 32×32 个样本：颜色种类、方差、海面占比与「是否空白」。 */
  static analyze(colors: number[]): TileContent {
    const count: number = colors.length;
    if (count === 0) {
      // 没采到样本不判空白：宁可不降级，也别因一次读取失败把好底图踢下去。
      return new TileContent();
    }
    const kinds: Set<number> = new Set<number>();
    let sumR: number = 0;
    let sumG: number = 0;
    let sumB: number = 0;
    let blue: number = 0;
    for (const color of colors) {
      const r: number = (color >> 16) & 0xFF;
      const g: number = (color >> 8) & 0xFF;
      const b: number = color & 0xFF;
      sumR += r;
      sumG += g;
      sumB += b;
      kinds.add(MapTileLogic.quantize(r, g, b));
      if (MapTileLogic.isOceanBlue(r, g, b)) {
        blue++;
      }
    }
    const meanR: number = sumR / count;
    const meanG: number = sumG / count;
    const meanB: number = sumB / count;
    let devR: number = 0;
    let devG: number = 0;
    let devB: number = 0;
    for (const color of colors) {
      const r: number = ((color >> 16) & 0xFF) - meanR;
      const g: number = ((color >> 8) & 0xFF) - meanG;
      const b: number = (color & 0xFF) - meanB;
      devR += r * r;
      devG += g * g;
      devB += b * b;
    }
    const variance: number = (devR + devG + devB) / (3 * count);
    const blueShare: number = blue / count;
    const isOcean: boolean = blueShare >= MapTileLogic.OCEAN_BLUE_SHARE;
    const isBlank: boolean = !isOcean && (variance < MapTileLogic.MONO_VARIANCE ||
      (kinds.size < MapTileLogic.MIN_COLOR_KINDS && variance < MapTileLogic.VARIANCE_THRESHOLD));
    return new TileContent(count, kinds.size, variance, blueShare, isOcean, isBlank);
  }

  /** 一屏的结论：看过的每一块都空白才算这一屏空白；空集合不算空白。 */
  static viewportIsBlank(contents: TileContent[]): boolean {
    if (contents.length === 0) {
      return false;
    }
    for (const content of contents) {
      if (!content.isBlank) {
        return false;
      }
    }
    return true;
  }

  /** 每通道高 4 位 → 一个 12 位的颜色种类编号。 */
  static quantize(r: number, g: number, b: number): number {
    return ((r >> MapTileLogic.QUANT_SHIFT) << 8) | ((g >> MapTileLogic.QUANT_SHIFT) << 4) |
      (b >> MapTileLogic.QUANT_SHIFT);
  }

  /** 色相 185–265°、饱和 ≥ 0.22、亮度 ≥ 60 的像素算海面。 */
  static isOceanBlue(r: number, g: number, b: number): boolean {
    const hi: number = Math.max(r, Math.max(g, b));
    const lo: number = Math.min(r, Math.min(g, b));
    if (hi < MapTileLogic.OCEAN_MIN_BRIGHTNESS) {
      return false;
    }
    const delta: number = hi - lo;
    if (delta === 0) {
      return false;
    }
    const saturation: number = delta / hi;
    if (saturation < MapTileLogic.OCEAN_MIN_SATURATION) {
      return false;
    }
    let hue: number;
    if (hi === r) {
      hue = 60 * (((g - b) / delta) % 6);
    } else if (hi === g) {
      hue = 60 * ((b - r) / delta + 2);
    } else {
      hue = 60 * ((r - g) / delta + 4);
    }
    if (hue < 0) {
      hue += 360;
    }
    return hue >= 185 && hue <= 265;
  }

  /** 诊断文案：`色彩 3 种 / 方差 41 / 海面`。 */
  static describe(content: TileContent): string {
    return `色彩 ${content.colorKinds} 种 / 方差 ${Math.floor(content.variance)}` +
      (content.isOcean ? ' / 海面' : '');
  }
}

/** 一次底图选择：实际用哪个源、是不是回退出来的。 */
export class MapTilePlan {
  requested: MapStyle;
  preferred: MapStyle;
  effective: MapStyle;
  fellBack: boolean;
  fallbackFailures: number;
  probeAtMillis: number;

  constructor(requested: MapStyle, preferred: MapStyle, effective: MapStyle, fellBack: boolean,
      fallbackFailures: number, probeAtMillis: number) {
    this.requested = requested;
    this.preferred = preferred;
    this.effective = effective;
    this.fellBack = fellBack;
    this.fallbackFailures = fallbackFailures;
    this.probeAtMillis = probeAtMillis;
  }
}

/** 缩放级别解析结果。 */
export class MapZoomPlan {
  requested: number;
  zoom: number;
  degraded: boolean;
  unavailable: boolean;

  constructor(requested: number, zoom: number, degraded: boolean, unavailable: boolean) {
    this.requested = requested;
    this.zoom = zoom;
    this.degraded = degraded;
    this.unavailable = unavailable;
  }
}

/** 界面只订阅这份快照：有效源 / 缩放 / 降级 / 不可用 / 是否回退。 */
export class MapUiState {
  requestedZoom: number = MapFallback.DEFAULT_ZOOM;
  source: MapStyle = MapStyle.AUTO;
  zoom: number = MapFallback.DEFAULT_ZOOM;
  degraded: boolean = false;
  unavailable: boolean = false;
  fellBack: boolean = false;
}

/** 由 plan + zoomPlan 生成 UI 快照（纯函数；失败计数变化不会改变它）。 */
export function uiStateOf(plan: MapTilePlan, zoomPlan: MapZoomPlan): MapUiState {
  const state: MapUiState = new MapUiState();
  state.requestedZoom = zoomPlan.requested;
  state.source = plan.effective;
  state.zoom = zoomPlan.zoom;
  state.degraded = zoomPlan.degraded;
  state.unavailable = zoomPlan.unavailable;
  state.fellBack = plan.fellBack;
  return state;
}

/** 两份 UI 快照是否完全相同：Index 只在这里返回 false 时才 setState。 */
export function sameUiState(left: MapUiState, right: MapUiState): boolean {
  return left.requestedZoom === right.requestedZoom && left.source === right.source &&
    left.zoom === right.zoom && left.degraded === right.degraded &&
    left.unavailable === right.unavailable && left.fellBack === right.fellBack;
}

/** 会话内的底图回退状态（不可变式：纯函数返回新状态）。 */
export class MapFallbackState {
  /** OSM 连续失败次数。 */
  osmFailures: number = 0;
  fellBack: boolean = false;
  fallbackFailures: number = 0;
  /** 下次探测 OSM 的时刻；-1 = 未回退。 */
  probeAtMillis: number = -1;
  /** 按 zoom 位标记「该源在该级别没有瓦片」；位 0..31。 */
  osmUnavailableMask: number = 0;
  amapUnavailableMask: number = 0;
  /** 其中因为空白瓦片才判没内容的级别（结构性，别被「z3 出图」清掉）。 */
  osmBlankMask: number = 0;
  amapBlankMask: number = 0;
  lastFailedZoom: number = -1;
  zoomFailures: number = 0;
  blankTileCount: number = 0;
  lastBlankZoom: number = -1;
  lastBlankColorKinds: number = -1;
  switchedAtMillis: number = -1;
  /** 最近一次失败 / 空白的时刻（回弹静默窗口用）。 */
  lastFailureMillis: number = -1;
  /** 最近一次「z3 出图后把上级没瓦片记忆清掉」的时刻（回弹冷却用）。 */
  lastReboundMillis: number = -1;
  /** 程序化改视口后的静默截止时刻：这之前回来的失败是自身取消请求造成的，不计。 */
  viewportSettleUntilMillis: number = -1;

  /** 到点后是否允许「z3 出图 → 清掉上级没瓦片记忆」的回弹：30 秒无新失败且距上次回弹 ≥5 分钟。 */
  canRecoverChain(nowMillis: number): boolean {
    if (this.lastFailureMillis >= 0 && nowMillis - this.lastFailureMillis < MapFallback.RECOVER_QUIET_MILLIS) {
      return false;
    }
    if (this.lastReboundMillis >= 0 && nowMillis - this.lastReboundMillis < MapFallback.REBOUND_COOLDOWN_MILLIS) {
      return false;
    }
    return true;
  }

  /** 程序化改视口后 2 秒内回来的失败不计。 */
  isViewportSettling(nowMillis: number): boolean {
    return this.viewportSettleUntilMillis >= 0 && nowMillis < this.viewportSettleUntilMillis;
  }

  /** 该源在这个级别是否已被判定「没有瓦片」。 */
  zoomUnavailable(style: MapStyle, zoom: number): boolean {
    const mask: number = style === MapStyle.OSM ? this.osmUnavailableMask : this.amapUnavailableMask;
    return (mask & (1 << zoom)) !== 0;
  }

  /** 是否落在切源后的残响窗口内（旧请求的失败不计）。 */
  isSettling(nowMillis: number): boolean {
    if (this.switchedAtMillis < 0) {
      return false;
    }
    const elapsed: number = nowMillis - this.switchedAtMillis;
    return elapsed >= 0 && elapsed < MapFallback.SWITCH_SETTLE_MILLIS;
  }

  /** 克隆，便于纯函数式修改。 */
  copy(): MapFallbackState {
    const next: MapFallbackState = new MapFallbackState();
    next.osmFailures = this.osmFailures;
    next.fellBack = this.fellBack;
    next.fallbackFailures = this.fallbackFailures;
    next.probeAtMillis = this.probeAtMillis;
    next.osmUnavailableMask = this.osmUnavailableMask;
    next.amapUnavailableMask = this.amapUnavailableMask;
    next.osmBlankMask = this.osmBlankMask;
    next.amapBlankMask = this.amapBlankMask;
    next.lastFailedZoom = this.lastFailedZoom;
    next.zoomFailures = this.zoomFailures;
    next.blankTileCount = this.blankTileCount;
    next.lastBlankZoom = this.lastBlankZoom;
    next.lastBlankColorKinds = this.lastBlankColorKinds;
    next.switchedAtMillis = this.switchedAtMillis;
    next.lastFailureMillis = this.lastFailureMillis;
    next.lastReboundMillis = this.lastReboundMillis;
    next.viewportSettleUntilMillis = this.viewportSettleUntilMillis;
    return next;
  }

  /** 网络恢复：清掉失败计数、回退标记与所有「没瓦片」记忆。 */
  recovered(nowMillis: number): MapFallbackState {
    const next: MapFallbackState = new MapFallbackState();
    next.switchedAtMillis = nowMillis;
    return next;
  }

  /** 标记某源某级别可用 / 不可用；可用时连空白记忆一起清掉。 */
  markZoom(style: MapStyle, zoom: number, available: boolean): MapFallbackState {
    const next: MapFallbackState = this.copy();
    const bit: number = 1 << zoom;
    if (style === MapStyle.OSM) {
      next.osmUnavailableMask = available ? (next.osmUnavailableMask & ~bit) : (next.osmUnavailableMask | bit);
      if (available) {
        next.osmBlankMask = next.osmBlankMask & ~bit;
      }
    } else {
      next.amapUnavailableMask = available ? (next.amapUnavailableMask & ~bit) : (next.amapUnavailableMask | bit);
      if (available) {
        next.amapBlankMask = next.amapBlankMask & ~bit;
      }
    }
    return next;
  }

  /** 记下「这个级别是因为空白瓦片才判没内容的」。 */
  markBlankZoom(style: MapStyle, zoom: number): MapFallbackState {
    const next: MapFallbackState = this.copy();
    const bit: number = 1 << zoom;
    if (style === MapStyle.OSM) {
      next.osmBlankMask = next.osmBlankMask | bit;
    } else {
      next.amapBlankMask = next.amapBlankMask | bit;
    }
    return next;
  }
}

export class MapFallback {
  /** 连续失败多少次判「OSM 不可用」/「该级别没瓦片」。 */
  static readonly FAILURE_THRESHOLD: number = 3;
  /** 回退后每隔多久探测一次 OSM。 */
  static readonly PROBE_INTERVAL_MILLIS: number = 5 * 60 * 1000;
  static readonly MIN_ZOOM: number = 3;
  static readonly MAX_ZOOM: number = 18;
  static readonly DEFAULT_ZOOM: number = 12;
  /** 逐级下探的步数，之后直接落到 z3 全球底图。 */
  static readonly MAX_DEGRADE_STEPS: number = 2;
  /** 切源后的残响窗口。 */
  static readonly SWITCH_SETTLE_MILLIS: number = 5000;
  /** 回弹前要求的「无新失败」静默时长。 */
  static readonly RECOVER_QUIET_MILLIS: number = 30 * 1000;
  /** 两次回弹（z3 出图后清上级记忆）之间的最小间隔。 */
  static readonly REBOUND_COOLDOWN_MILLIS: number = 5 * 60 * 1000;
  /** 程序化改视口后的失败静默窗口（自身取消请求的假失败）。 */
  static readonly VIEWPORT_SETTLE_MILLIS: number = 2000;

  /** 程序化改视口：接下来 2 秒内的失败不计。 */
  static markViewportSettling(state: MapFallbackState, nowMillis: number): MapFallbackState {
    const next: MapFallbackState = state.copy();
    next.viewportSettleUntilMillis = nowMillis + MapFallback.VIEWPORT_SETTLE_MILLIS;
    return next;
  }
  /** 全球底图探测用的 z3 瓦片（任何地区都在，体积小）。 */
  static readonly PROBE_URL: string = 'https://tile.openstreetmap.org/3/4/3.png';

  /** 按地区算首选底图：境内高德、境外 OSM。 */
  static preferredStyle(style: MapStyle, latitude: number, longitude: number, countryCode: string): MapStyle {
    if (style !== MapStyle.AUTO) {
      return style;
    }
    return SolarTimeMath.isInChina(latitude, longitude, countryCode) ? MapStyle.AMAP_VECTOR : MapStyle.OSM;
  }

  /** 一次底图选择：自动模式且已回退 → 实际用高德；手动模式不动。 */
  static plan(style: MapStyle, latitude: number, longitude: number, countryCode: string,
      state: MapFallbackState): MapTilePlan {
    const preferred: MapStyle = MapFallback.preferredStyle(style, latitude, longitude, countryCode);
    if (style !== MapStyle.AUTO) {
      return new MapTilePlan(style, preferred, preferred, false, 0, -1);
    }
    const fellBack: boolean = preferred === MapStyle.OSM && state.fellBack;
    return new MapTilePlan(style, preferred, fellBack ? MapStyle.AMAP_VECTOR : preferred, fellBack,
      fellBack ? state.fallbackFailures : 0, fellBack ? state.probeAtMillis : -1);
  }

  /** 缩放级别：自动模式按「该级别有没有瓦片」逐级下探，最后落到 z3；手动模式不降级。 */
  static zoomPlan(plan: MapTilePlan, requestedZoom: number, state: MapFallbackState): MapZoomPlan {
    const requested: number = Math.max(MapFallback.MIN_ZOOM, Math.min(MapFallback.MAX_ZOOM, requestedZoom));
    if (plan.requested !== MapStyle.AUTO) {
      return new MapZoomPlan(requested, requested, false, false);
    }
    for (let step: number = 0; step <= MapFallback.MAX_DEGRADE_STEPS; step++) {
      const zoom: number = Math.max(MapFallback.MIN_ZOOM, requested - step);
      if (!state.zoomUnavailable(plan.effective, zoom)) {
        return new MapZoomPlan(requested, zoom, zoom !== requested, false);
      }
    }
    return new MapZoomPlan(requested, MapFallback.MIN_ZOOM,
      MapFallback.MIN_ZOOM !== requested, state.zoomUnavailable(plan.effective, MapFallback.MIN_ZOOM));
  }

  /** 一块瓦片加载成功：清该级别「没瓦片」标记；OSM 成功即视为恢复；z3 出图清掉非空白记忆。 */
  static onTileLoaded(style: MapStyle, latitude: number, longitude: number, countryCode: string,
      zoom: number, state: MapFallbackState, nowMillis: number): MapFallbackState {
    if (style !== MapStyle.AUTO) {
      return state;
    }
    const plan: MapTilePlan = MapFallback.plan(style, latitude, longitude, countryCode, state);
    let next: MapFallbackState = state.markZoom(plan.effective, zoom, true).copy();
    next.lastFailedZoom = -1;
    next.zoomFailures = 0;
    if (zoom <= MapFallback.MIN_ZOOM) {
      // 回弹要有静默窗口 + 冷却：否则 z3 一出图就清上级记忆 → 立刻弹回 z12 → 再失败 → 无限升降。
      if (state.canRecoverChain(nowMillis)) {
        // 保留「空白瓦片」的结构性记忆，只清网络问题学来的。
        const sticky: number = plan.effective === MapStyle.OSM ? next.osmBlankMask : next.amapBlankMask;
        if (plan.effective === MapStyle.OSM) {
          next.osmUnavailableMask = next.osmUnavailableMask & sticky;
        } else {
          next.amapUnavailableMask = next.amapUnavailableMask & sticky;
        }
        next.lastReboundMillis = nowMillis;
      }
    }
    if (plan.effective === MapStyle.OSM) {
      next = next.recovered(nowMillis);
    }
    return next;
  }

  /** 一块瓦片真实失败：OSM 累计到 3 次回退；高德同一级别累计到 3 次判该级别没瓦片。 */
  static onTileFailed(style: MapStyle, latitude: number, longitude: number, countryCode: string,
      zoom: number, state: MapFallbackState, nowMillis: number): MapFallbackState {
    if (style !== MapStyle.AUTO) {
      return state;
    }
    // 程序化改视口后 2 秒内的失败是自身取消请求造成的假失败；切源残响同样不计。
    if (state.isViewportSettling(nowMillis) || state.isSettling(nowMillis)) {
      return state;
    }
    return MapFallback.registerFailure(style, latitude, longitude, countryCode, zoom, state, nowMillis, false);
  }

  /** 一块空白瓦片：只累计诊断并走与失败相同的迁移；手动模式只记数。 */
  static onTileBlank(style: MapStyle, latitude: number, longitude: number, countryCode: string,
      zoom: number, state: MapFallbackState, nowMillis: number, colorKinds: number): MapFallbackState {
    const counted: MapFallbackState = state.copy();
    counted.blankTileCount = counted.blankTileCount + 1;
    counted.lastBlankZoom = zoom;
    counted.lastBlankColorKinds = colorKinds;
    if (style !== MapStyle.AUTO) {
      return counted;
    }
    return MapFallback.registerFailure(style, latitude, longitude, countryCode, zoom, counted, nowMillis, true);
  }

  /** 探测是否到期（只回退后 / 自动模式）。 */
  static probeDue(state: MapFallbackState, nowMillis: number): boolean {
    if (!state.fellBack || state.probeAtMillis < 0) {
      return false;
    }
    return nowMillis >= state.probeAtMillis;
  }

  /** 探测结果：成功 → 恢复；失败 → 下次探测再推 5 分钟。 */
  static onProbeResult(state: MapFallbackState, reachable: boolean, nowMillis: number): MapFallbackState {
    if (reachable) {
      return state.recovered(nowMillis);
    }
    const next: MapFallbackState = state.copy();
    next.probeAtMillis = nowMillis + MapFallback.PROBE_INTERVAL_MILLIS;
    return next;
  }

  private static registerFailure(style: MapStyle, latitude: number, longitude: number, countryCode: string,
      zoom: number, state: MapFallbackState, nowMillis: number, blank: boolean): MapFallbackState {
    const plan: MapTilePlan = MapFallback.plan(style, latitude, longitude, countryCode, state);
    if (plan.effective !== MapStyle.OSM) {
      const streak: number = state.lastFailedZoom === zoom ? state.zoomFailures + 1 : 1;
      let next: MapFallbackState = state.copy();
      next.lastFailureMillis = nowMillis;
      next.lastFailedZoom = zoom;
      next.zoomFailures = streak;
      if (streak >= MapFallback.FAILURE_THRESHOLD) {
        next = next.markZoom(plan.effective, zoom, false);
        next.lastFailedZoom = -1;
        next.zoomFailures = 0;
        if (blank) {
          next = next.markBlankZoom(plan.effective, zoom);
        }
      }
      return next;
    }
    const failures: number = state.osmFailures + 1;
    if (failures < MapFallback.FAILURE_THRESHOLD) {
      const next: MapFallbackState = state.copy();
      next.osmFailures = failures;
      next.lastFailureMillis = nowMillis;
      return next;
    }
    const next: MapFallbackState = state.copy();
    next.osmFailures = failures;
    next.fellBack = true;
    next.fallbackFailures = failures;
    next.probeAtMillis = nowMillis + MapFallback.PROBE_INTERVAL_MILLIS;
    next.lastFailedZoom = -1;
    next.zoomFailures = 0;
    next.switchedAtMillis = nowMillis;
    next.lastFailureMillis = nowMillis;
    return next;
  }
}
