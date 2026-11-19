/**
 * 核心数值自检：期望值与 Android 端 SolarTimeMathTest / ShichenTest /
 * TakeTimeRepositoryTest / WeatherRepositoryTest / CityIndexTest 保持一致，
 * 也覆盖 iOS Scripts/main.swift 的同类断言。
 *
 * 运行：node Tools/verify-core.js
 */

import { BeijingDate, SolarTimeMath, PolarState } from './core/SolarTimeMath';
import { Shichen } from './core/Shichen';
import { TimeFormat } from './core/TimeFormat';
import { SolarSnapshot, SolarTimeSnapshot } from './core/SolarSnapshot';
import { CityIndex } from './core/CityIndex';
import { TakeBand, TakeTemperature, TakeTimeLogic, MINUTES_PER_DAY } from './core/TakeTime';import { WeatherLogic, WeatherCondition, HourPoint, WeatherSlot, WeatherSource, WeatherFallback } from './core/Weather';
import { ThemeMode } from './core/ThemeMode';
import { DistrictNameLogic, DistrictNames } from './core/DistrictName';
import { DistrictLayoutPlan, DistrictLayoutSolver, DistrictLayoutTier } from './core/DistrictLayout';
import { DialLabels } from './core/DialLabels';
import { PlaceNamePolicy } from './core/PlaceNamePolicy';
import { ChimeLogic } from './core/Chime';
import { Place, PlaceSource } from './core/Place';
import { PlaceBadgeLogic } from './core/PlaceBadge';
import { CivicTimeLogic } from './core/CivicTime';
import { HorizonSpan, MotionArrow, SunArcSpan, SunLabelAnchors, SunPath, SunPathGeometry } from './core/SunPath';
import { SunDialColors } from './core/SunDialColors';
import {
  LocationPlaceholders,
  UnknownLocationLogic,
  UnknownMapCache,
  UnknownMapDecision
} from './core/LocationUnknown';
import { ZoneTable } from './core/ZoneTable';
import { MapTilesLogic, MapDatum, MAP_STYLE_OPTIONS, MapStyle, TILE_PX, MIN_ZOOM, MAX_ZOOM,
  MANUAL_TILE_CONCURRENCY } from './core/MapTiles';
import {
  AmapProbe,
  MapFallback,
  MapFallbackState,
  MapTileLogic,
  MapTilePlan,
  MapUiState,
  ManualTileTracker,
  ProbeCache,
  ProbeDecision,
  ProgressiveProbe,
  applyDecision,
  bestContentZoom,
  cacheKey,
  decide,
  isBetterTile,
  needsProbe,
  sourceRank,
  sameUiState,
  shouldEarlyExit,
  shouldProbe,
  tileOf,
  uiStateOf,
  zoomsAbove
} from './core/MapFallback';

let passed = 0;
const failures: string[] = [];

function check(name: string, condition: boolean, detail: string = ''): void {
  if (condition) {
    passed++;
  } else {
    failures.push(detail.length > 0 ? `${name} (${detail})` : name);
  }
}

function near(name: string, expected: number, actual: number, tolerance: number): void {
  check(name, Math.abs(expected - actual) <= tolerance, `expected ${expected}, got ${actual}`);
}

function equal(name: string, expected: string | number | boolean, actual: string | number | boolean): void {
  check(name, expected === actual, `expected ${expected}, got ${actual}`);
}

const beijing = (y: number, m: number, d: number): number => Date.UTC(y, m - 1, d, 12, 0, 0);
const secondOfDay = (hour: number, minute: number, second: number = 0): number => hour * 3600 + minute * 60 + second;

// ---- 均时差（NOAA 公布值）----
const equationCases: number[][] = [
  [beijing(2024, 2, 11), -14.2],
  [beijing(2024, 5, 14), 3.7],
  [beijing(2024, 6, 21), -1.8],
  [beijing(2024, 7, 26), -6.5],
  [beijing(2024, 11, 3), 16.5]
];
for (const item of equationCases) {
  const minutes = SolarTimeMath.solarPosition(item[0]).equationOfTimeSeconds / 60.0;
  near(`equation of time @${new Date(item[0]).toISOString()}`, item[1], minutes, 0.5);
}

// ---- 北京时间经度修正 + 均时差 ----
{
  const instant = Date.UTC(2026, 10, 2, 4, 3, 0);
  const offset = SolarTimeMath.offsetFromBeijingSeconds(instant, 116.4074);
  near('Beijing offset early November', 127.0, offset, 20.0);
  const expected =
    SolarTimeMath.longitudeOffsetSeconds(116.4074) + SolarTimeMath.solarPosition(instant).equationOfTimeSeconds;
  near('offset = longitude + EoT', expected, offset, 1e-6);

  const rebuilt = SolarTimeSnapshot.rebuildFromOffset(instant, 116.4074);
  near('offset rebuilds true solar time', SolarTimeMath.trueSolarSecondsOfDay(instant, 116.4074), rebuilt, 1e-6);
}

// ---- 真太阳时每秒推进 ----
{
  const longitudes = [121.4737, 87.6168, -74.01];
  for (const longitude of longitudes) {
    const start = Date.UTC(2026, 10, 2, 0, 0, 0);
    const first = SolarTimeMath.trueSolarSecondsOfDay(start, longitude);
    const later = SolarTimeMath.trueSolarSecondsOfDay(start + 3600 * 1000, longitude);
    let delta = later - first;
    if (delta < 0) {
      delta += 86400;
    }
    near(`true solar advances one hour @${longitude}`, 3600, delta, 5);
  }
}

// ---- 日出日落（北京，年鉴值）----
{
  const june = SolarTimeMath.sunTimes(new BeijingDate(2024, 6, 21), 39.9042, 116.4074);
  equal('June polar state', PolarState.NORMAL, june.polar);
  const sunriseJune = SolarTimeMath.beijingSecondsOfDay(june.sunriseMillis);
  const sunsetJune = SolarTimeMath.beijingSecondsOfDay(june.sunsetMillis);
  near('Beijing sunrise Jun 21', secondOfDay(4, 46), sunriseJune, 180);
  near('Beijing sunset Jun 21', secondOfDay(19, 46), sunsetJune, 180);
  near(
    'June daylight hours',
    15.0,
    (june.sunsetMillis - june.sunriseMillis) / 3600000.0,
    0.1
  );

  const december = SolarTimeMath.sunTimes(new BeijingDate(2024, 12, 21), 39.9042, 116.4074);
  near('Beijing sunrise Dec 21', secondOfDay(7, 32), SolarTimeMath.beijingSecondsOfDay(december.sunriseMillis), 180);

  const november = SolarTimeMath.sunTimes(new BeijingDate(2026, 11, 2), 39.9042, 116.4074);
  near('solar noon is 12:00 true solar', secondOfDay(12, 0), SolarTimeMath.trueSolarSecondsOfDay(november.solarNoonMillis, 116.4074), 6);
  near('winter solar noon is 12:00 true solar', secondOfDay(12, 0), SolarTimeMath.trueSolarSecondsOfDay(december.solarNoonMillis, 116.4074), 30);

  const polarSummer = SolarTimeMath.sunTimes(new BeijingDate(2024, 6, 21), 78.0, 15.0);
  equal('midnight sun state', PolarState.MIDNIGHT_SUN, polarSummer.polar);
  check('midnight sun has no sunrise', !polarSummer.hasSunrise());
  const polarWinter = SolarTimeMath.sunTimes(new BeijingDate(2024, 12, 21), 78.0, 15.0);
  equal('polar night state', PolarState.POLAR_NIGHT, polarWinter.polar);
  check('polar night has no sunset', !polarWinter.hasSunset());
}

// ---- 太阳高度角 ----
{
  const noon = Date.UTC(2026, 10, 2, 4, 0, 0);
  const noonAltitude = SolarTimeMath.solarAltitudeDegrees(noon, 39.9042, 116.4074);
  const midnightAltitude = SolarTimeMath.solarAltitudeDegrees(noon + 43200 * 1000, 39.9042, 116.4074);
  check('altitude peaks near solar noon', noonAltitude > midnightAltitude, `${noonAltitude} vs ${midnightAltitude}`);
  check('noon altitude in 20..40 deg', noonAltitude > 20 && noonAltitude < 40, `${noonAltitude}`);
}

// ---- 偏移量始终在半日之内 ----
{
  const instant = Date.UTC(2026, 2, 20, 6, 0, 0);
  for (const longitude of [-179.9, -120.0, 0.0, 60.0, 116.4, 179.9]) {
    const offset = SolarTimeMath.offsetFromBeijingSeconds(instant, longitude);
    check(`offset within half day @${longitude}`, Math.abs(offset) <= 43200, `${offset}`);
  }
}

// ---- 十二时辰 ----
{
  equal('Zi at 23:00', 0, Shichen.indexOf(secondOfDay(23, 0, 0)));
  equal('Zi at 00:30', 0, Shichen.indexOf(secondOfDay(0, 30, 0)));
  equal('Zi at 00:59:59', 0, Shichen.indexOf(secondOfDay(0, 59, 59)));
  equal('Chou at 01:00', 1, Shichen.indexOf(secondOfDay(1, 0, 0)));
  equal('Wu at 11:00', 6, Shichen.indexOf(secondOfDay(11, 0, 0)));
  equal('Wu at 12:59:59', 6, Shichen.indexOf(secondOfDay(12, 59, 59)));
  equal('Wei at 13:00', 7, Shichen.indexOf(secondOfDay(13, 0, 0)));
  equal('Hai at 22:59:59', 11, Shichen.indexOf(secondOfDay(22, 59, 59)));

  equal('name 0', '子时', Shichen.nameOf(0));
  equal('name 6', '午时', Shichen.nameOf(6));
  equal('name 11', '亥时', Shichen.nameOf(11));
  equal('range 0', '23:00 – 01:00', Shichen.rangeText(0));
  equal('range 6', '11:00 – 13:00', Shichen.rangeText(6));
  equal('range 11', '21:00 – 23:00', Shichen.rangeText(11));
  equal('en name 6', 'Wu', Shichen.displayName(6, 'en-US'));

  equal('half early at 11:00', '初', Shichen.halfLabel(secondOfDay(11, 0, 0)));
  equal('quarter 1 at 11:00', 1, Shichen.quarterOfHalf(secondOfDay(11, 0, 0)));
  equal('quarter 4 at 11:50', 4, Shichen.quarterOfHalf(secondOfDay(11, 50, 0)));
  equal('half late at 12:00', '正', Shichen.halfLabel(secondOfDay(12, 0, 0)));
  equal('quarter 1 at 12:00', 1, Shichen.quarterOfHalf(secondOfDay(12, 0, 0)));
  equal('quarter 2 at 12:20', 2, Shichen.quarterOfHalf(secondOfDay(12, 20, 0)));

  near('countdown from 23:30', 5400.0, Shichen.secondsToNextShichen(secondOfDay(23, 30, 0)), 1e-6);
  near('countdown from 23:00', 7200.0, Shichen.secondsToNextShichen(secondOfDay(23, 0, 0)), 1e-6);
  near('countdown from 02:59', 60.0, Shichen.secondsToNextShichen(secondOfDay(2, 59, 0)), 1e-6);

  const now = Date.UTC(2026, 10, 2, 4, 3, 0);
  const boundary = Shichen.nextBoundary(now, 116.4074);
  const delta = (boundary - now) / 1000.0;
  check('next boundary within a shichen', delta >= 1 && delta <= 7200, `${delta}`);
  const solarAtBoundary = SolarTimeMath.trueSolarSecondsOfDay(boundary, 116.4074);
  near('boundary aligns to odd true-solar hour', 0.0, (solarAtBoundary + 3600) % 7200, 2.0);
}

// ---- 快照 ----
{
  const snapshot = SolarTimeSnapshot.compute(Date.UTC(2026, 10, 2, 4, 3, 0), 39.9042, 116.4074, 'zh-CN');
  check('snapshot true solar seconds in range', snapshot.trueSolarSeconds >= 0 && snapshot.trueSolarSeconds < 86400);
  equal('snapshot shichen name matches index', Shichen.nameOf(snapshot.shichenIndex), snapshot.shichenName);
  check('snapshot reports sunrise', snapshot.hasSunrise() && snapshot.sunriseTrueSolarSeconds > 0);
  check('snapshot daylight positive', snapshot.daylightSeconds > 30000);
  check('snapshot is day before sunset', snapshot.isDay());
}

// ---- 格式化 ----
{
  equal('clock', '13:05', TimeFormat.clock(secondOfDay(13, 5, 0)));
  equal('clock with seconds', '13:05:09', TimeFormat.clockWithSeconds(secondOfDay(13, 5, 9)));
  equal('clock placeholder', '--:--', TimeFormat.clock(-1));
  equal('signed positive', '+14 分 22 秒', TimeFormat.signedDuration(862, 'zh'));
  equal('signed negative', '-2 分 05 秒', TimeFormat.signedDuration(-125, 'zh'));
  equal('duration hours', '13 小时 42 分', TimeFormat.duration(49320, 'zh'));
  equal('countdown', '01:23:45', TimeFormat.countdown(5025));
  equal('coordinates', '39.9042°N  116.4074°E', TimeFormat.coordinates(39.9042, 116.4074));
  equal('coordinates south west', '33.4500°S  70.6700°W', TimeFormat.coordinates(-33.45, -70.67));
  equal('unknown location coordinates become a dash', '--',
    TimeFormat.coordinates(39.9042, 116.4074, true));
}

// ---- 城市索引 ----
{
  const beijing = CityIndex.nearest(39.9042, 116.4074, 'zh-CN');
  check('nearest to Beijing is Beijing', beijing !== null && beijing.name === '北京', `${beijing ? beijing.name : 'null'}`);
  const urumqiEn = CityIndex.nearest(43.8256, 87.6168, 'en-US');
  check('Urumqi English name', urumqiEn !== null && urumqiEn.name === 'Urumqi', `${urumqiEn ? urumqiEn.name : 'null'}`);
  const remote = CityIndex.nearest(0.0, 0.0, 'zh-CN');
  check('mid-ocean has no city', remote === null);
  near('distance Beijing-Shanghai', 1067, CityIndex.distanceKm(39.9042, 116.4074, 31.2304, 121.4737), 15);
  check('city table is populated', CityIndex.size() > 200, `${CityIndex.size()}`);
}

// ---- 关键时间 ----
{
  const html =
    '<b>服用時間 Take Time</b> : 15:00-17:00&nbsp; 20:00-22:00 <br> 10:00-12:00 ' +
    '<font>(凍或溫 Cold or Mild)</font>';
  const schedule = TakeTimeLogic.parse(html);
  check('parsed key times', schedule !== null);
  if (schedule !== null) {
    equal('three bands', 3, schedule.bands.length);
    equal('first band start', 900, schedule.bands[0].startMinute);
    equal('temperature cold', TakeTemperature.COLD_OR_MILD, schedule.temperature);
    check('15:30 inside first band', schedule.bands[0].contains(930));
    check('16:59 inside first band', schedule.bands[0].contains(1019));
    check('17:00 outside first band', !schedule.bands[0].contains(1020));
    const encoded = TakeTimeLogic.encodeBands(schedule.bands);
    const decoded = TakeTimeLogic.decodeBands(encoded);
    equal('bands round trip', encoded, TakeTimeLogic.encodeBands(decoded));
  }

  const midnightBand = new TakeBand(23 * 60, 60);
  equal('midnight band length', 120, midnightBand.lengthMinutes());
  check('23:30 inside midnight band', midnightBand.contains(23 * 60 + 30));
  check('00:30 inside midnight band', midnightBand.contains(30));
  check('01:00 outside midnight band', !midnightBand.contains(60));

  const hot = TakeTimeLogic.parse('<p>Take Time : 09:00-11:00 (Hot or Mild)</p>');
  check('hot marker parsed', hot !== null && hot.temperature === TakeTemperature.HOT_OR_MILD);
  check('empty page gives null', TakeTimeLogic.parse('<p>nothing here</p>') === null);
  const wrapped = TakeTimeLogic.parse('<p>Take Time</p><p>06:00 - 08:00</p>');
  check('ranges split by tags', wrapped !== null && wrapped.bands.length === 1);

  // 每天 01:00–05:00 之间随机同步，失败后一小时重试
  const today = '2026-11-02';
  const target = TakeTimeLogic.targetMillis(Date.UTC(2026, 10, 2, 0, 0, 0), 120);
  check('sync before target is skipped', !TakeTimeLogic.shouldSync(target - 1, target, today, '', 0));
  check('sync after target runs', TakeTimeLogic.shouldSync(target + 1000, target, today, '', 0));
  check('sync skipped after today success', !TakeTimeLogic.shouldSync(target + 1000, target, today, today, 0));
  check(
    'sync retries after one hour',
    TakeTimeLogic.shouldSync(target + 3700 * 1000, target, today, '', target)
  );
  check('sync within retry window skipped', !TakeTimeLogic.shouldSync(target + 3599 * 1000, target, today, '', target));
  check('sync window lower bound', TakeTimeLogic.isInsideSyncWindow(60));
  check('sync window upper bound exclusive', !TakeTimeLogic.isInsideSyncWindow(300));
  check('cache fresh within 7 days', TakeTimeLogic.isFresh(6 * 24 * 3600 * 1000));
  check('cache stale after 7 days', !TakeTimeLogic.isFresh(8 * 24 * 3600 * 1000));

  // 时间轴铺段：15:00-17:00 与 20:00-22:00 应得到「空档、段、空档、段、空档」五段
  const segments = TakeTimeLogic.axisSegments([new TakeBand(900, 1020), new TakeBand(1200, 1320)]);
  equal('axis has five segments', 5, segments.length);
  equal('axis first segment is a gap of 15h', 900, segments[0].lengthMinutes);
  equal('axis first band starts at 15:00', 900, segments[1].startMinute);
  equal('axis first band is 2h', 120, segments[1].lengthMinutes);
  equal('axis bands are ordered', 1, segments[3].bandIndex);
  equal('axis ends with a gap of 2h', 120, segments[4].lengthMinutes);
  let axisTotal = 0;
  for (const segment of segments) {
    axisTotal += segment.lengthMinutes;
  }
  equal('axis covers the whole day', MINUTES_PER_DAY, axisTotal);
  const midnightSegments = TakeTimeLogic.axisSegments([new TakeBand(1380, 60)]);
  equal('midnight band splits into three segments', 3, midnightSegments.length);
  equal('midnight band tail ends at 01:00', 60, midnightSegments[0].lengthMinutes);
  equal('midnight band head starts at 23:00', 1380, midnightSegments[2].startMinute);

  // 真太阳时是否落在关键时间里（决定数字字色）
  const colorBands = [new TakeBand(900, 1020), new TakeBand(1380, 60)];
  check('inside band changes color', TakeTimeLogic.insideBands(colorBands, 16 * 3600));
  check('outside band keeps gold', !TakeTimeLogic.insideBands(colorBands, 9 * 3600));
  check('band start counts as inside', TakeTimeLogic.insideBands(colorBands, 900 * 60));
  check('band end is outside', !TakeTimeLogic.insideBands(colorBands, 1020 * 60));
  check('midnight band counts', TakeTimeLogic.insideBands(colorBands, 23 * 3600 + 1800));
  check('no bands never inside', !TakeTimeLogic.insideBands([], 16 * 3600));
}

// ---- 天气 ----
{
  const json = '{"current":{"temperature_2m":21.6,"weather_code":3},' +
    '"hourly":{"time":["2026-11-02T00:00","2026-11-02T01:00"],' +
    '"temperature_2m":[20.4,19.5],"weather_code":[1,3]}}';
  const current = WeatherLogic.parse(json);
  check('current weather parsed', current !== null && current.temperatureC === 22, `${current ? current.temperatureC : 'null'}`);
  check('weather code', current !== null && current.code === 3);
  const hourly = WeatherLogic.parseHourly(json);
  equal('hourly length', 2, hourly.length);
  equal('hourly first epoch', Date.UTC(2026, 10, 2, 0, 0, 0) / 1000, hourly[0].epochSeconds);
  equal('hourly rounds temperature', 20, hourly[0].temperatureC);

  equal('clear code', WeatherCondition.CLEAR, WeatherLogic.conditionOf(0));
  equal('thunder code', WeatherCondition.THUNDER, WeatherLogic.conditionOf(95));
  equal('snow code', WeatherCondition.SNOW, WeatherLogic.conditionOf(85));
  equal('unknown code falls back to overcast', WeatherCondition.OVERCAST, WeatherLogic.conditionOf(12345));

  const slots = WeatherLogic.slots(Date.UTC(2026, 10, 2, 4, 37, 0) / 1000, 8 * 3600, 4, 3);
  equal('four slots', 4, slots.length);
  equal('slots start at local block', Date.UTC(2026, 10, 2, 4, 0, 0) / 1000, slots[0]);
  equal('slot step is 3h', 3 * 3600, slots[1] - slots[0]);

  const encoded = WeatherLogic.encodeHourly(hourly);
  equal('hourly round trip', encoded, WeatherLogic.encodeHourly(WeatherLogic.decodeHourly(encoded)));

  const range = WeatherLogic.temperatureRange(
    hourly,
    Date.UTC(2026, 10, 2, 0, 0, 0),
    Date.UTC(2026, 10, 3, 0, 0, 0),
    8 * 3600 * 1000
  );
  check('temperature range', range !== null && range[0] === 20 && range[1] === 20, `${range}`);
  check('refresh when stale', WeatherLogic.shouldRefresh(31 * 60 * 1000, 0, 6 * 60 * 1000));
  check('refresh when moved', WeatherLogic.shouldRefresh(60 * 1000, 6, 0));
  check('no refresh when fresh and still', !WeatherLogic.shouldRefresh(60 * 1000, 1, 0));

  // 1.4.39：失败后 5 分钟内不重复请求，超过 5 分钟再试；旧数据最长保留 24 小时
  check('no retry within 5 minutes', !WeatherLogic.shouldRefresh(31 * 60 * 1000, 0, 60 * 1000));
  check('retry after 5 minutes', WeatherLogic.shouldRefresh(31 * 60 * 1000, 0, 6 * 60 * 1000));
  // TTL 只管「多久去取一次」；旧数据仍然可以继续显示，最长 24 小时（显示窗口）
  check('refresh after ttl when retry allowed', WeatherLogic.shouldRefresh(6 * 60 * 60 * 1000, 0, 60 * 60 * 1000));
  check('display window is 24h', WeatherLogic.HOURLY_MAX_AGE_MILLIS === 24 * 60 * 60 * 1000);
  check('just-attempted is throttled even when ancient', !WeatherLogic.shouldRefresh(25 * 60 * 60 * 1000, 0, 0));
  check('ancient data refreshes once the 5-min throttle is over', WeatherLogic.shouldRefresh(25 * 60 * 60 * 1000, 0, 6 * 60 * 1000));
  equal(
    'open-meteo url',
    'https://api.open-meteo.com/v1/forecast?latitude=39.9042&longitude=116.4074' +
      '&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code&forecast_days=2&past_days=1&timezone=UTC',
    WeatherLogic.buildUrl(39.9042, 116.4074)
  );

  // 逐时预报文案：槽位按本地（+8）整点对齐
  const forecastPoints: HourPoint[] = [
    new HourPoint(Date.UTC(2026, 10, 2, 0, 0, 0) / 1000, 20, 0),
    new HourPoint(Date.UTC(2026, 10, 2, 1, 0, 0) / 1000, 19, 3)
  ];
  const forecast = WeatherLogic.forecastLabels(
    forecastPoints,
    Date.UTC(2026, 10, 2, 0, 30, 0) / 1000,
    8 * 3600,
    2,
    'zh-CN'
  );
  equal('two forecast labels', 2, forecast.length);
  equal('first forecast label', '8时 晴 20°', forecast[0]);
  equal('second forecast label', '9时 阴 19°', forecast[1]);
  equal(
    'english forecast label',
    '8:00 Clear 20°',
    WeatherLogic.forecastLabels(forecastPoints, Date.UTC(2026, 10, 2, 0, 30, 0) / 1000, 8 * 3600, 1, 'en-US')[0]
  );
}

// ---- 逐时行：步长跟随数据源（槽位数恒为 6 个）----
{
  /** 2026-11-16 的某个 UTC 时刻（避免手写魔数出错，与 Android 的 WeatherRepositoryTest 同一口径）。 */
  const utcAt = (hour: number, minute: number = 0): number => Date.UTC(2026, 10, 16, hour, minute, 0) / 1000;
  const hourlyPoints = (fromEpoch: number, count: number, stepHours: number): HourPoint[] => {
    const points: HourPoint[] = [];
    for (let index = 0; index < count; index++) {
      points.push(new HourPoint(fromEpoch + index * stepHours * 3600, 10 + index, 1));
    }
    return points;
  };
  const localHours = (slots: WeatherSlot[], offsetSeconds: number): string =>
    slots.map((slot: WeatherSlot): number => WeatherLogic.localHourOf(slot.epochSeconds, offsetSeconds)).join(',');
  const labelsOf = (slots: WeatherSlot[], offsetSeconds: number, language: string): string =>
    WeatherLogic.slotLabels(slots, offsetSeconds, language).join(',');

  // 槽位数是版面常量：永远 6 格，变的只有步长。
  equal('six hourly slots', 6, WeatherLogic.SLOT_COUNT);

  // 主源（1 小时粒度）：本地 21:55 → 现在/22时/23时/0时/1时/2时，6 格覆盖 6 小时。
  const now = utcAt(13, 55); // 本地 21:55（+08:00）
  const oneHourPoints = hourlyPoints(utcAt(12), 12, 1); // 本地 20:00 起
  const oneHourSlots = WeatherLogic.visibleSlots(oneHourPoints, now, 8 * 3600, WeatherLogic.SLOT_COUNT, 1);
  equal('1h source keeps six slots', 6, oneHourSlots.length);
  equal('1h slot local hours', '21,22,23,0,1,2', localHours(oneHourSlots, 8 * 3600));
  equal('1h slot labels', '现在,22时,23时,0时,1时,2时', labelsOf(oneHourSlots, 8 * 3600, 'zh-CN'));
  equal('1h slot labels in english', 'Now,22:00,23:00,0:00,1:00,2:00', labelsOf(oneHourSlots, 8 * 3600, 'en-US'));
  equal('1h slots span five hours between first and last', 5 * 3600,
    oneHourSlots[5].epochSeconds - oneHourSlots[0].epochSeconds);
  equal('1h first slot is now', 1, oneHourSlots.filter((slot: WeatherSlot): boolean => slot.isNow).length);
  check('1h now slot uses the latest point not in the future', oneHourSlots[0].epochSeconds === utcAt(13));

  // 备用源（3 小时粒度）：本地 21:55 → 现在/23时/2时/5时/8时/11时，6 格覆盖 18 小时。
  const threeHourPoints = hourlyPoints(utcAt(12), 8, 3); // 本地 20:00 起
  const threeHourSlots = WeatherLogic.visibleSlots(threeHourPoints, now, 8 * 3600, WeatherLogic.SLOT_COUNT, 3);
  equal('3h source keeps six slots', 6, threeHourSlots.length);
  equal('3h slot local hours', '20,23,2,5,8,11', localHours(threeHourSlots, 8 * 3600));
  equal('3h slot labels', '现在,23时,2时,5时,8时,11时', labelsOf(threeHourSlots, 8 * 3600, 'zh-CN'));
  equal('3h slot labels in english', 'Now,23:00,2:00,5:00,8:00,11:00', labelsOf(threeHourSlots, 8 * 3600, 'en-US'));
  // 6 格 × 3 小时 = 覆盖 18 小时；首格到末格起点是 5 个步长 = 15 小时。
  equal('3h slots span fifteen hours between first and last', 15 * 3600,
    threeHourSlots[5].epochSeconds - threeHourSlots[0].epochSeconds);
  equal('3h first slot is the 20:00 reading', utcAt(12), threeHourSlots[0].epochSeconds);

  // 逐时行图标下方显示温度（与 Android `hourTemperatures` 同一规则）：
  // 首格「现在」用实时读数，其余用采样点温度；缺数据显示 `-`。
  const temps1h: (number | null)[] = WeatherLogic.hourTemperatures(oneHourPoints, now, 8 * 3600, 1, 18);
  equal('1h hourly now uses the current reading', 18, temps1h[0] === null ? -999 : temps1h[0]);
  equal('1h hourly temps follow the sample points', '12,13,14,15,16',
    temps1h.slice(1).map((value: number | null): number => value === null ? -999 : value).join(','));
  const labels1h: string[] = temps1h.map((value: number | null): string => WeatherLogic.temperatureLabel(value));
  equal('1h hourly temperature labels', '18°,12°,13°,14°,15°,16°', labels1h.join(','));
  check('all hourly temperatures end with the degree sign',
    labels1h.every((label: string): boolean => label.endsWith('°')));
  const temps3h: (number | null)[] = WeatherLogic.hourTemperatures(threeHourPoints, now, 8 * 3600, 3, 18);
  equal('3h hourly now uses the current reading, not the sample point', 18,
    temps3h[0] === null ? -999 : temps3h[0]);
  equal('3h hourly sample temps follow', '11,12,13,14,15',
    temps3h.slice(1).map((value: number | null): number => value === null ? -999 : value).join(','));
  // 没有实时读数时「现在」退回该采样点温度。
  const tempsNoCurrent: (number | null)[] = WeatherLogic.hourTemperatures(
    threeHourPoints, now, 8 * 3600, 3, null);
  equal('missing current reading falls back to the sample point', 10,
    tempsNoCurrent[0] === null ? -999 : tempsNoCurrent[0]);
  // 完全没有采样点：全 null → 全 `-`。
  const missingTemps: (number | null)[] = WeatherLogic.hourTemperatures([], now, 8 * 3600, 3, null);
  equal('missing hourly temps are all null', 'null,null,null,null,null,null',
    missingTemps.map((value: number | null): string => value === null ? 'null' : `${value}`).join(','));
  equal('missing hourly temperature labels are all dashes', '-,-,-,-,-,-',
    missingTemps.map((value: number | null): string => WeatherLogic.temperatureLabel(value)).join(','));

  // 第二排逐时行按「格数」跳过（不是按小时数硬挪：3 小时源的 6 格就是 18 小时）。
  const secondRow = WeatherLogic.visibleSlots(threeHourPoints, now, 8 * 3600, WeatherLogic.SLOT_COUNT, 3, 6);
  equal('second row skips six slots', '14,17,20,23,2,5', localHours(secondRow, 8 * 3600));
  check('second row has no now slot', secondRow.filter((slot: WeatherSlot): boolean => slot.isNow).length === 0);

  // 一个采样点都没有时也要排满 6 格（内容由界面填占位符），且按数据源的网格对齐。
  const emptyThree = WeatherLogic.visibleSlots([], now, 8 * 3600, WeatherLogic.SLOT_COUNT, 3);
  equal('empty 3h grid still has six slots', 6, emptyThree.length);
  equal('empty 3h grid hours', '20,23,2,5,8,11', localHours(emptyThree, 8 * 3600));
  check('empty 3h grid starts with now', emptyThree[0].isNow);
  const emptyOne = WeatherLogic.visibleSlots([], now, 8 * 3600, WeatherLogic.SLOT_COUNT, 1);
  equal('empty 1h grid aligns to the local hour', '21,22,23,0,1,2', localHours(emptyOne, 8 * 3600));

  // 采样点全在未来 → 「现在」退回第一个点（宁可显示最近的预报，也不要空格）。
  const futureOnly: HourPoint[] = [new HourPoint(utcAt(3), 5, 1), new HourPoint(utcAt(6), 6, 1)];
  const futureSlots = WeatherLogic.visibleSlots(futureOnly, utcAt(0), 0, 3, 3);
  equal('future-only anchor falls back to the first point', utcAt(3), futureSlots[0].epochSeconds);
  equal('future-only slots step by the source', utcAt(9), futureSlots[2].epochSeconds);

  // 3 小时网格对齐（UTC 的 0/3/6/…/21 点 —— 7Timer! 自己的采样网格）。
  equal('align 3h drops to the grid', utcAt(3), WeatherLogic.alignToStep(utcAt(4), 3));
  equal('align keeps grid points', utcAt(3), WeatherLogic.alignToStep(utcAt(3), 3));
  equal('align 3h at 23:59', utcAt(21), WeatherLogic.alignToStep(utcAt(23, 59), 3));
  equal('align 1h at 04:59', utcAt(4), WeatherLogic.alignToStep(utcAt(4, 59), 1));
  equal('align 1h keeps whole hours', utcAt(4), WeatherLogic.alignToStep(utcAt(4), 1));
  // 对齐后一定落在 UTC 0/3/6/…/21 上（换成 +08:00 就是本地 2/5/8/…/23 点，与 7Timer 的采样网格一致）。
  equal('aligned 3h point sits on the utc grid', 0, WeatherLogic.alignToStep(utcAt(13, 55), 3) % (12 * 3600));
  equal('aligned 3h point is local 20:00 at utc+8', 20, WeatherLogic.localHourOf(WeatherLogic.alignToStep(utcAt(13, 55), 3), 8 * 3600));
  equal('local hour handles negative offsets', 23, WeatherLogic.localHourOf(utcAt(7), -8 * 3600));

  // 7Timer! 真实返回（2026-11 抓取，上海坐标）走一遍完整链路：init + timepoint → 6 槽。
  const realSevenTimer = '{"product":"civil","init":"2026111606","dataseries":[' +
    '{"timepoint":3,"temp2m":16,"weather":"cloudynight"},' +
    '{"timepoint":6,"temp2m":15,"weather":"cloudynight"},' +
    '{"timepoint":9,"temp2m":14,"weather":"cloudynight"},' +
    '{"timepoint":12,"temp2m":14,"weather":"cloudynight"},' +
    '{"timepoint":15,"temp2m":13,"weather":"cloudynight"},' +
    '{"timepoint":18,"temp2m":13,"weather":"cloudyday"},' +
    '{"timepoint":21,"temp2m":15,"weather":"cloudyday"}]}';
  const realPoints = WeatherLogic.parseSevenTimer(realSevenTimer);
  equal('real 7timer payload yields seven points', 7, realPoints.length);
  equal('first 7timer point is init + 3h', utcAt(9), realPoints[0].epochSeconds);
  const realSlots = WeatherLogic.visibleSlots(realPoints, utcAt(13, 26), 8 * 3600, WeatherLogic.SLOT_COUNT, 3);
  equal('real 7timer slots', '现在,23时,2时,5时,8时,11时', labelsOf(realSlots, 8 * 3600, 'zh-CN'));
  // 「现在」取的是 20:00 那条（15°），不是第一个点（09:00Z 的 16°）—— 这就是 3 小时源的代价。
  const realSnapshot = WeatherLogic.snapshotAt(realPoints, utcAt(13, 26));
  equal('7timer current temperature comes from the latest point', 15, realSnapshot === null ? -1 : realSnapshot.temperatureC);
  equal('7timer current code maps cloudy to overcast', 3, realSnapshot === null ? -1 : realSnapshot.code);
}

// ---- 7Timer! 解析与天气码映射 ----
{
  const utcAt = (hour: number, minute: number = 0): number => Date.UTC(2026, 10, 16, hour, minute, 0) / 1000;

  // init 06:00Z + timepoint 3h / 6h → 09:00Z / 12:00Z；天气词带 day/night 后缀也能认。
  const timepointJson = '{"product":"civil","init":"2026111606","dataseries":[' +
    '{"timepoint":3,"temp2m":16,"weather":"cloudynight"},' +
    '{"timepoint":6,"temp2m":15,"weather":"clearday"}]}';
  const timepointPoints = WeatherLogic.parseSevenTimer(timepointJson);
  equal('two 7timer points', 2, timepointPoints.length);
  equal('7timer point 1 is init + 3h', utcAt(9), timepointPoints[0].epochSeconds);
  equal('7timer point 2 is init + 6h', utcAt(12), timepointPoints[1].epochSeconds);
  equal('7timer point 1 temperature', 16, timepointPoints[0].temperatureC);
  equal('cloudynight maps to overcast', 3, timepointPoints[0].code);
  equal('clearday maps to clear', 0, timepointPoints[1].code);

  // 旧文档里的 `time` 字段（yyyyMMddHH）也认，并向下对齐到 3 小时网格。
  const absolutePoints = WeatherLogic.parseSevenTimer('{"dataseries":[{"time":"2025111604","temp2m":9,"weather":"rain"}]}');
  equal('absolute time field yields one point', 1, absolutePoints.length);
  equal('absolute time is realigned to the grid', Date.UTC(2025, 10, 16, 3, 0, 0) / 1000, absolutePoints[0].epochSeconds);
  equal('rain maps to moderate rain', 63, absolutePoints[0].code);

  // 乱序 → 排序；缺 temp2m 的条目跳过。
  const mixedPoints = WeatherLogic.parseSevenTimer('{"init":"2026111606","dataseries":[' +
    '{"timepoint":6,"temp2m":15,"weather":"clearday"},{"weather":"rain"},' +
    '{"timepoint":3,"temp2m":16,"weather":"cloudyday"}]}');
  equal('broken items are skipped', 2, mixedPoints.length);
  equal('7timer points are sorted', utcAt(9), mixedPoints[0].epochSeconds);
  equal('7timer sort keeps the later point second', utcAt(12), mixedPoints[1].epochSeconds);

  // 各种坏负载都返回空列表（不能崩）。
  equal('not json yields nothing', 0, WeatherLogic.parseSevenTimer('not json').length);
  equal('payload without dataseries yields nothing', 0, WeatherLogic.parseSevenTimer('{"product":"civil"}').length);
  equal('empty dataseries yields nothing', 0, WeatherLogic.parseSevenTimer('{"dataseries":[]}').length);
  equal('timepoint without init is dropped', 0,
    WeatherLogic.parseSevenTimer('{"dataseries":[{"timepoint":3,"temp2m":1}]}').length);

  // 时刻串解析：yyyyMMddHH（UTC）→ epoch；格式不对返回 -1。
  equal('stamp 2026111606', Date.UTC(2026, 10, 16, 6, 0, 0) / 1000, WeatherLogic.sevenTimerStampEpoch('2026111606'));
  equal('stamp with spaces', Date.UTC(2026, 10, 16, 6, 0, 0) / 1000, WeatherLogic.sevenTimerStampEpoch(' 2026111606 '));
  equal('broken stamp', -1, WeatherLogic.sevenTimerStampEpoch('2026-11-16'));
  equal('empty stamp', -1, WeatherLogic.sevenTimerStampEpoch(''));

  // 天气词 → WMO 码：昼夜后缀不影响分类，表外的值按「多云」。
  equal('clearday', 0, WeatherLogic.wmoCodeOfSevenTimer('clearday'));
  equal('clearnight', 0, WeatherLogic.wmoCodeOfSevenTimer('clearnight'));
  equal('pcloudyday', 2, WeatherLogic.wmoCodeOfSevenTimer('pcloudyday'));
  equal('mcloudynight', 3, WeatherLogic.wmoCodeOfSevenTimer('mcloudynight'));
  equal('cloudyday', 3, WeatherLogic.wmoCodeOfSevenTimer('cloudyday'));
  equal('humidday', 45, WeatherLogic.wmoCodeOfSevenTimer('humidday'));
  equal('fog', 45, WeatherLogic.wmoCodeOfSevenTimer('fog'));
  equal('lightrainday', 80, WeatherLogic.wmoCodeOfSevenTimer('lightrainday'));
  equal('ishowernight', 80, WeatherLogic.wmoCodeOfSevenTimer('ishowernight'));
  equal('rain', 63, WeatherLogic.wmoCodeOfSevenTimer('rain'));
  equal('heavyrain', 65, WeatherLogic.wmoCodeOfSevenTimer('heavyrain'));
  equal('lightsnowday', 71, WeatherLogic.wmoCodeOfSevenTimer('lightsnowday'));
  equal('snownight', 73, WeatherLogic.wmoCodeOfSevenTimer('snownight'));
  equal('tsday', 95, WeatherLogic.wmoCodeOfSevenTimer('tsday'));
  equal('unknown word falls back to pcloudy', 2, WeatherLogic.wmoCodeOfSevenTimer('sandstorm'));
  equal('empty word falls back to pcloudy', 2, WeatherLogic.wmoCodeOfSevenTimer(''));
  equal('uppercase word is normalised', 2, WeatherLogic.wmoCodeOfSevenTimer('PCLOUDYDAY'));
  equal('mapped code is understood by the wmo classifier', WeatherCondition.OVERCAST,
    WeatherLogic.conditionOf(WeatherLogic.wmoCodeOfSevenTimer('cloudynight')));
  equal('mapped clear code is understood', WeatherCondition.CLEAR,
    WeatherLogic.conditionOf(WeatherLogic.wmoCodeOfSevenTimer('clearday')));

  // 7Timer 没有 current 块：实时读数取「不晚于当前时刻的最后一个点」。
  const series: HourPoint[] = [
    new HourPoint(utcAt(3), 7, 3), new HourPoint(utcAt(6), 12, 1), new HourPoint(utcAt(9), 15, 0)
  ];
  equal('snapshot takes the latest past point', 12, WeatherLogic.snapshotAt(series, utcAt(7))?.temperatureC as number);
  equal('snapshot falls back to the first point when all are in the future', 7,
    WeatherLogic.snapshotAt(series, utcAt(0))?.temperatureC as number);
  check('snapshot without points is null', WeatherLogic.snapshotAt([], utcAt(0)) === null);

  // 主源必须同时有 current 与 hourly：只有气温没有逐时也算失败（否则会拿到半残数据）。
  check('primary without hourly is rejected',
    WeatherLogic.parsePrimary('{"current":{"temperature_2m":9,"weather_code":2}}') === null);
  check('broken primary is rejected', WeatherLogic.parsePrimary('not json') === null);
  const fullPrimary = WeatherLogic.parsePrimary('{"current":{"temperature_2m":9,"weather_code":2},' +
    '"hourly":{"time":["2026-11-10T00:00"],"temperature_2m":[8.2],"weather_code":[1]}}');
  check('primary with current and hourly is accepted', fullPrimary !== null && fullPrimary.hourly.length === 1);
  equal('primary snapshot temperature', 9, fullPrimary === null ? -1 : fullPrimary.snapshot.temperatureC);
}

// ---- 降级判定 / 旧数据保留 ----
{
  // 主源失败后：缓存未过期就什么都不动（不清空界面），过期或没有缓存才去问 7Timer!。
  equal('fresh cache is kept', WeatherFallback.KEEP_CACHE, WeatherLogic.fallbackFor(true, 5 * 60 * 1000));
  equal('cache at the 30 minute edge is kept', WeatherFallback.KEEP_CACHE,
    WeatherLogic.fallbackFor(true, WeatherLogic.TTL_MILLIS));
  equal('expired cache tries 7timer', WeatherFallback.TRY_SEVEN_TIMER, WeatherLogic.fallbackFor(true, 31 * 60 * 1000));
  equal('no cache tries 7timer', WeatherFallback.TRY_SEVEN_TIMER, WeatherLogic.fallbackFor(false, 0));
  equal('negative age tries 7timer', WeatherFallback.TRY_SEVEN_TIMER, WeatherLogic.fallbackFor(true, -1));

  // 旧数据 24 小时内都能显示（超过才当作没有数据）。
  check('zero age is displayable', WeatherLogic.isDisplayable(0));
  check('23 hours old is displayable', WeatherLogic.isDisplayable(23 * 60 * 60 * 1000));
  check('more than a day is not displayable', !WeatherLogic.isDisplayable(24 * 60 * 60 * 1000 + 1));
  equal('display window is 24 hours', 24 * 60 * 60 * 1000, WeatherLogic.DISPLAY_MAX_AGE_MILLIS);

  // 诊断里的「数据过期 N 分钟」。
  equal('stale label under a minute', '数据过期 0 分钟', WeatherLogic.staleLabel(30 * 1000));
  equal('stale label 45 minutes', '数据过期 45 分钟', WeatherLogic.staleLabel(45 * 60 * 1000));
  equal('stale label 25 hours', '数据过期 1500 分钟', WeatherLogic.staleLabel(25 * 60 * 60 * 1000));
  equal('stale label without cache', '', WeatherLogic.staleLabel(-1));

  // 主源超时：5 秒拿不到就立刻降级（不再「等 2 秒重试一次」）。
  equal('http timeout is five seconds', 5000, WeatherLogic.HTTP_TIMEOUT_MILLIS);

  // ---- 刷新触发：过期 或 低精度升级（任意一条满足即刷新）----
  const MINUTE = 60 * 1000;
  const NEVER_ATTEMPTED = Number.MAX_SAFE_INTEGER;
  // 主源失败后**直接 fallback**（没有「2 秒重试一次」的中转）：无缓存 / 缓存过期 → 立刻问 7Timer!；
  // 缓存新鲜且属于当前地点 → 保留缓存、什么都不做。
  equal('no cache falls back to 7timer immediately', WeatherFallback.TRY_SEVEN_TIMER,
    WeatherLogic.fallbackFor(false, -1));
  equal('expired cache falls back to 7timer immediately', WeatherFallback.TRY_SEVEN_TIMER,
    WeatherLogic.fallbackFor(true, 31 * MINUTE));
  equal('fresh cache is kept after a primary failure', WeatherFallback.KEEP_CACHE,
    WeatherLogic.fallbackFor(true, 5 * MINUTE));

  // 低精度判定的两个来源都要认：7Timer! 与步长 3。
  check('7timer data is low precision', WeatherLogic.isLowPrecision('7timer', 3));
  check('step 3 alone is low precision', WeatherLogic.isLowPrecision('open-meteo', 3));
  check('open-meteo 1h is high precision', !WeatherLogic.isLowPrecision('open-meteo', 1));

  // ① 低精度 + 未过期 → 仍然要刷新（为了升级回 1 小时源）
  check('low precision refreshes even when fresh',
    WeatherLogic.needsFetch(5 * MINUTE, 0, NEVER_ATTEMPTED, '7timer', 3));
  // ② 60 秒内刚试过（无论成败）→ 不重复刷新；满 60 秒立刻再试。
  check('low precision is throttled at fifty nine seconds',
    !WeatherLogic.needsFetch(5 * MINUTE, 0, 59 * 1000, '7timer', 3));
  check('low precision retries right at sixty seconds',
    WeatherLogic.needsFetch(5 * MINUTE, 0, 60 * 1000, '7timer', 3));
  check('low precision retries after a minute',
    WeatherLogic.needsFetch(5 * MINUTE, 0, 2 * MINUTE, '7timer', 3));
  // ③ 切回主源（1 小时源、新鲜）后 → 不再按 60 秒轮询
  check('upgraded data does not poll every minute',
    !WeatherLogic.needsFetch(5 * MINUTE, 0, 2 * MINUTE, 'open-meteo', 1));
  // ④ 两条互不干扰：过期与低精度各自成立、各自生效
  check('expired high precision data refreshes',
    WeatherLogic.needsFetch(45 * MINUTE, 0, 11 * MINUTE, 'open-meteo', 1));
  check('expired low precision data refreshes',
    WeatherLogic.needsFetch(45 * MINUTE, 0, 11 * MINUTE, '7timer', 3));
  check('fresh high precision data is left alone',
    !WeatherLogic.needsFetch(5 * MINUTE, 0, NEVER_ATTEMPTED, 'open-meteo', 1));
  // 失败后的 5 分钟节流仍然管住「过期」这一条；但低精度数据满 60 秒就会再试。
  check('failure throttle still gates the expiry path',
    !WeatherLogic.needsFetch(45 * MINUTE, 0, 30 * 1000, '7timer', 3));
  check('low precision resumes polling after sixty seconds',
    WeatherLogic.needsFetch(45 * MINUTE, 0, 2 * MINUTE, '7timer', 3));
  // 移动超过 5 km 一律刷新（换地点）
  check('moving triggers a refresh', WeatherLogic.needsFetch(1 * MINUTE, 6, 0, 'open-meteo', 1));
  // 升级节流的独立判定（界面「回到前台立刻升级」用的也是它）
  check('precision upgrade waits sixty seconds', !WeatherLogic.shouldUpgradePrecision('7timer', 3, 59 * 1000));
  check('precision upgrade fires at sixty seconds', WeatherLogic.shouldUpgradePrecision('7timer', 3, 60 * 1000));
  check('precision upgrade ignores high precision data',
    !WeatherLogic.shouldUpgradePrecision('open-meteo', 1, NEVER_ATTEMPTED));
  equal('low precision retry window is sixty seconds', 60 * 1000, WeatherLogic.LOW_PRECISION_RETRY_MILLIS);

  // ---- 降级后重试主源：前台 60→120→300 秒退避（封顶），后台一律 10 分钟 ----
  equal('foreground retry after first failure is 60s', 60 * 1000,
    WeatherLogic.lowPrecisionRetryDelayMillis(1, true));
  equal('foreground retry after two failures is 120s', 2 * 60 * 1000,
    WeatherLogic.lowPrecisionRetryDelayMillis(2, true));
  equal('foreground retry after three failures is 300s', 5 * 60 * 1000,
    WeatherLogic.lowPrecisionRetryDelayMillis(3, true));
  equal('foreground retry is capped at 300s after four failures', 5 * 60 * 1000,
    WeatherLogic.lowPrecisionRetryDelayMillis(4, true));
  equal('background retry is ten minutes regardless of failures', 10 * 60 * 1000,
    WeatherLogic.lowPrecisionRetryDelayMillis(1, false));
  equal('background retry stays ten minutes after four failures', 10 * 60 * 1000,
    WeatherLogic.lowPrecisionRetryDelayMillis(4, false));
  equal('next retry timestamp adds the backoff delay', 1_000_000 + 2 * 60 * 1000,
    WeatherLogic.nextLowPrecisionRetryAt(1_000_000, 2, true));
  equal('next retry timestamp in background adds ten minutes', 1_000_000 + 10 * 60 * 1000,
    WeatherLogic.nextLowPrecisionRetryAt(1_000_000, 3, false));
  check('two failures throttle at 119 seconds',
    !WeatherLogic.needsFetch(5 * MINUTE, 0, 119 * 1000, '7timer', 3, 2, true));
  check('two failures retry at 120 seconds',
    WeatherLogic.needsFetch(5 * MINUTE, 0, 120 * 1000, '7timer', 3, 2, true));
  check('background does not poll every minute',
    !WeatherLogic.needsFetch(5 * MINUTE, 0, 2 * MINUTE, '7timer', 3, 1, false));
  check('background retries after ten minutes',
    WeatherLogic.needsFetch(5 * MINUTE, 0, 10 * MINUTE, '7timer', 3, 1, false));
  check('after switching back to the primary no backoff polling',
    !WeatherLogic.needsFetch(5 * MINUTE, 0, 2 * MINUTE, 'open-meteo', 1, 4, true)
      && !WeatherLogic.shouldForceUpgradeOnForeground('open-meteo', 1));
  check('returning to foreground forces an immediate primary attempt',
    WeatherLogic.shouldForceUpgradeOnForeground('7timer', 3));

  // 数据源标识（缓存里存的就是这两个字符串）：认不出来一律当主源、步长 1。
  equal('open-meteo id', 'open-meteo', WeatherSource.OPEN_METEO);
  equal('7timer id', '7timer', WeatherSource.SEVEN_TIMER);
  equal('7timer id round trip', WeatherSource.SEVEN_TIMER, WeatherSource.of('7timer'));
  equal('unknown source falls back to open-meteo', WeatherSource.OPEN_METEO, WeatherSource.of('noaa'));
  equal('empty source falls back to open-meteo', WeatherSource.OPEN_METEO, WeatherSource.of(''));
  equal('open-meteo step is one hour', 1, WeatherSource.stepHoursOf('open-meteo'));
  equal('7timer step is three hours', 3, WeatherSource.stepHoursOf('7timer'));
  equal('unknown source step is one hour', 1, WeatherSource.stepHoursOf('noaa'));
  equal('open-meteo display name', 'Open-Meteo', WeatherSource.displayName('open-meteo'));
  equal('7timer display name', '7Timer!', WeatherSource.displayName('7timer'));
  equal('open-meteo attribution keeps the licence', 'Open-Meteo（CC BY 4.0）', WeatherSource.attribution('open-meteo'));
  equal('7timer attribution', '7Timer!', WeatherSource.attribution('7timer'));
  equal('seven timer url', 'https://www.7timer.info/bin/api.pl?lon=121.4737&lat=31.2304&product=civil&output=json',
    WeatherLogic.buildSevenTimerUrl(31.2304, 121.4737));
}

// ---- 主题三态（自动 / 亮色 / 暗色）----
{
  // 存储值 → 模式：非法值（旧版本没这个键、值被改坏）一律回「自动」。
  equal('empty theme falls back to auto', 'AUTO', ThemeMode.fromName(''));
  equal('unknown theme falls back to auto', 'AUTO', ThemeMode.fromName('SEPIA'));
  equal('lowercase theme falls back to auto', 'AUTO', ThemeMode.fromName('light'));
  equal('light round trip', 'LIGHT', ThemeMode.fromName('LIGHT'));
  equal('dark round trip', 'DARK', ThemeMode.fromName('DARK'));
  equal('auto round trip', 'AUTO', ThemeMode.fromName('AUTO'));
  equal('three theme options', 3, ThemeMode.OPTIONS.length);
  equal('theme option order', 'AUTO,LIGHT,DARK', ThemeMode.OPTIONS.join(','));
  equal('default theme is auto', ThemeMode.AUTO, ThemeMode.fromName(ThemeMode.OPTIONS[0]));

  // AUTO 跟太阳（白天亮、夜里暗）；LIGHT/DARK 忽略太阳。
  check('auto is dark at night', ThemeMode.isDark('AUTO', false));
  check('auto is light by day', !ThemeMode.isDark('AUTO', true));
  check('light stays light at night', !ThemeMode.isDark('LIGHT', false));
  check('light stays light by day', !ThemeMode.isDark('LIGHT', true));
  check('dark stays dark at night', ThemeMode.isDark('DARK', false));
  check('dark stays dark by day', ThemeMode.isDark('DARK', true));
  check('invalid mode behaves like auto', ThemeMode.isDark('sepia', false) && !ThemeMode.isDark('sepia', true));
  check('isLight is the inverse of isDark',
    ThemeMode.isLight('DARK', true) === false && ThemeMode.isLight('LIGHT', false) === true);

  // 设置页文案。
  equal('auto label', '自动', ThemeMode.label('AUTO'));
  equal('light label', '亮色', ThemeMode.label('LIGHT'));
  equal('dark label', '暗色', ThemeMode.label('DARK'));
  equal('invalid label falls back to auto', '自动', ThemeMode.label('SEPIA'));
  check('every mode has a description', ThemeMode.OPTIONS.every((mode: string): boolean =>
    ThemeMode.description(mode).length > 0));
}

// ---- 区划名 ----
{
  const names = DistrictNameLogic.composeNames(['南山区', '深圳市', '广东省']);
  check('composed names', names !== null && names.full === '广东省深圳市南山区', `${names ? names.full : 'null'}`);
  check('short name is finest level', names !== null && names.short === '南山区');
  check('placeholder dropped', DistrictNameLogic.composeNames(['市辖区', '北京市'])?.full === '北京市');
  check('duplicate dropped', DistrictNameLogic.composeNames(['深圳', '深圳', '广东'])?.full === '广东深圳');
  check('empty gives null', DistrictNameLogic.composeNames(['', '[]', '  ']) === null);

  // 分隔符按名字判断：英文名必须用「, 」连接，不能拼成「New YorkManhattan」。
  const manhattan = DistrictNameLogic.pickNames('Manhattan', 'New York', 'New York');
  equal('latin names joined with comma', 'New York, Manhattan', manhattan === null ? 'null' : manhattan.full);
  equal('latin short name is district', 'Manhattan', manhattan === null ? 'null' : manhattan.short);
  const dongcheng = DistrictNameLogic.pickNames('东城区', '北京市', '北京市');
  equal('chinese names joined directly', '北京市东城区', dongcheng === null ? 'null' : dongcheng.full);
  // 三段式：英文去重后保留最细三级、逗号连接；中文从粗到细直接相连。
  const tokyo = DistrictNameLogic.composeNames(['Chiyoda', 'Tokyo', 'Tokyo']);
  equal('latin levels deduped', 'Chiyoda, Tokyo', tokyo === null ? 'null' : tokyo.full);
  const mixed = DistrictNameLogic.composeNames(['Manhattan', '纽约', '纽约州']);
  equal('mixed grouping uses comma', 'Manhattan, 纽约, 纽约州', mixed === null ? 'null' : mixed.full);
  check('chinese grouping detected',
    DistrictNameLogic.isChineseGrouping(['黄浦区', '上海市']) &&
    !DistrictNameLogic.isChineseGrouping(['Manhattan', '纽约']));
  const fallback = DistrictNameLogic.pickNames('', '深圳市', '广东省');
  check('fallback to city', fallback !== null && fallback.full === '深圳市', `${fallback ? fallback.full : 'null'}`);
  const shanghai = DistrictNameLogic.pickNames('黄浦区', '上海市', '上海市');
  check('municipality name joined', shanghai !== null && shanghai.full === '上海市黄浦区', `${shanghai ? shanghai.full : 'null'}`);
  check('municipality short is district', shanghai !== null && shanghai.short === '黄浦区');
  const shenzhen = DistrictNameLogic.pickNames('南山区', '深圳市', '广东省');
  check('city prefixed to district', shenzhen !== null && shenzhen.full === '深圳市南山区', `${shenzhen ? shenzhen.full : 'null'}`);
  const prefixed = DistrictNameLogic.pickNames('上海市黄浦区', '上海市', '上海市');
  check('already prefixed not doubled', prefixed !== null && prefixed.full === '上海市黄浦区', `${prefixed ? prefixed.full : 'null'}`);
  check('language change triggers refresh', DistrictNameLogic.needsRefresh(true, 'zh-CN', 'en-US', 1000, 0));
  check('fresh cache reused', !DistrictNameLogic.needsRefresh(true, 'zh-CN', 'zh-CN', 60 * 1000, 1));
  check('moving triggers refresh', DistrictNameLogic.needsRefresh(true, 'zh-CN', 'zh-CN', 60 * 1000, 7));
  const display = '均乐社区, 南京东路街道, 上海市, 黄浦区, 上海市, 中国';
  check('district picked from display_name', DistrictNameLogic.pickDistrictFromDisplay(display, '上海市') === '黄浦区');
  check('city token skipped', DistrictNameLogic.pickDistrictFromDisplay('上海市, 上海市, 中国', '上海市') === '');
  check('no district in display', DistrictNameLogic.pickDistrictFromDisplay('Huangpu, Shanghai, China', 'Shanghai') === '');
  check('county suffix recognised', DistrictNameLogic.pickDistrictFromDisplay('某镇, 某县, 某市', '某市') === '某县');

  // 地名显示：手动坐标 + 反查失败 → 半角减号；成功 → 区划名；从预设城市切来不残留旧名
  // （旧缓存按坐标过滤为 null，见 DistrictService.cachedNamesFor）。
  equal('manual coordinate with failed lookup shows a dash', '-',
    DistrictNameLogic.labelFor(null, ''));
  const cairo = new DistrictNames('开罗省', '开罗', 'eg');
  equal('successful lookup shows the district', '开罗省', DistrictNameLogic.labelFor(cairo, ''));
  equal('district wins over a preset fallback', '开罗省', DistrictNameLogic.labelFor(cairo, '北京'));
  equal('preset city falls back to its own name', '北京', DistrictNameLogic.labelFor(null, '北京'));
  check('old beijing cache is too far from cairo coordinates',
    CityIndex.distanceKm(39.9042, 116.4074, 25.2048, 30.2708) > 5);
}

// ---- 报时窗口 ----
{
  const bands = [new TakeBand(15 * 60, 17 * 60), new TakeBand(20 * 60, 22 * 60)];
  near('next key start at 14:00', 3600, ChimeLogic.secondsToNextKeyStart(secondOfDay(14, 0, 0), bands), 1e-6);
  near('next key start after 21:00 wraps to next day 15:00', 18 * 3600, ChimeLogic.secondsToNextKeyStart(secondOfDay(21, 0, 0), bands), 1e-6);
  check('no bands means no chime', ChimeLogic.secondsToNextKeyStart(0, []) < 0);
  check('collides with 15:00 start', ChimeLogic.collidesWithKeyStart(15 * 60 + 0.2, bands));
  check('no collision at 15:10', !ChimeLogic.collidesWithKeyStart(15 * 60 + 10, bands));
  check('collides across midnight', ChimeLogic.collidesWithKeyStart(MINUTES_PER_DAY - 0.1, [new TakeBand(0, 120)]));

  const now = Date.UTC(2026, 10, 2, 4, 3, 0);
  const triggers = ChimeLogic.upcomingShichenTriggers(now, 116.4074, 3);
  equal('three shichen triggers', 3, triggers.length);
  for (let index = 1; index < triggers.length; index++) {
    near('shichen triggers are two hours apart', 7200, (triggers[index] - triggers[index - 1]) / 1000, 2);
  }
  const yielding = ChimeLogic.nextShichenTriggerYielding(now, 116.4074, false, bands);
  equal('yielding is a no-op when chimes off', ChimeLogic.nextShichenTrigger(now, 116.4074), yielding);

  const keyTriggers = ChimeLogic.upcomingKeyTimeTriggers(now, 116.4074, bands, 2);
  check('key time triggers cover two days', keyTriggers.length === 4, `${keyTriggers.length}`);
  for (const trigger of keyTriggers) {
    const minutes = SolarTimeMath.trueSolarSecondsOfDay(trigger, 116.4074) / 60.0;
    check('key trigger lands on a band start', ChimeLogic.collidesWithKeyStart(minutes, bands), `${minutes}`);
  }
}

// ---- 观测点 ----
{
  check('default place is Beijing', Place.DEFAULT.labelKey === 'city_beijing' && Place.DEFAULT.latitude === 39.9042);
  equal('twenty two presets', 22, Place.PRESETS.length);
  check('valid latitude', Place.isValidLatitude(39.9) && !Place.isValidLatitude(91));
  check('same location', Place.DEFAULT.sameLocation(new Place(39.9042, 116.4074, 0, '', '')));

  // 标题行「GPS」徽标：只有跟随 GPS 才显示；预设城市 / 手动坐标什么都不显示
  // （与 Android HeaderBadgeTest、首页 header 的条件渲染同一条规则）。
  check('gps badge shown when following gps',
    PlaceBadgeLogic.showsGps(PlaceSource.GPS) && PlaceBadgeLogic.GPS_TEXT === 'GPS');
  check('gps badge hidden for preset and manual',
    !PlaceBadgeLogic.showsGps(PlaceSource.MANUAL) && !PlaceBadgeLogic.showsGps(PlaceSource.DEFAULT));

  // 预设城市自带国家码：选中后就能当场按 ZoneTable 算出标准时区（与 Android ZoneTableTest 对齐）。
  let everyPresetHasCountry: boolean = true;
  for (const preset of Place.PRESETS) {
    if (preset.countryCode.length !== 2) {
      everyPresetHasCountry = false;
    }
  }
  check('every preset carries a country code', everyPresetHasCountry);
  equal('china preset stays utc+8', 8 * 3600,
    ZoneTable.offsetSeconds(Place.PRESETS[8].countryCode, Place.PRESETS[8].longitude, 0));

  // 第 11 个起是境外城市：前 10 个大致按 UTC 偏移从西到东（檀香山 −10 … 悉尼 +10），
  // 末尾两个是极圈城市（摩尔曼斯克 +3、中山站 +8），用来验证极昼／极夜。
  const overseasMinutes: number[] = [-600, -480, -300, 0, 60, 240, 330, 540, 480, 600, 180, 480];
  let overseasOffsetsOk: boolean = true;
  let overseasNamesOk: boolean = true;
  for (let i = 0; i < overseasMinutes.length; i++) {
    const preset: Place = Place.PRESETS[10 + i];
    if (ZoneTable.offsetSeconds(preset.countryCode, preset.longitude, 0) !== overseasMinutes[i] * 60) {
      overseasOffsetsOk = false;
    }
    // 名字由 Settings.cityLabel 查 CityIndex 得到：查不到就只能显示经纬度了。
    if (CityIndex.nearest(preset.latitude, preset.longitude, 'zh') === null) {
      overseasNamesOk = false;
    }
  }
  check('overseas presets resolve by country code', overseasOffsetsOk);
  check('overseas presets have a city name', overseasNamesOk);

  // 极圈城市：摩尔曼斯克（68.97°N 33.08°E，ru → UTC+3）与中山站（69.37°S 76.38°E，cn → UTC+8）。
  // 名字和按钮文案一样走 CityIndex；时区靠国家码，不依赖逆地理编码。
  const murmansk: Place = Place.PRESETS[20];
  const zhongshan: Place = Place.PRESETS[21];
  equal('murmansk latitude', 68.97, murmansk.latitude);
  equal('murmansk longitude', 33.08, murmansk.longitude);
  equal('zhongshan latitude', -69.37, zhongshan.latitude);
  equal('zhongshan longitude', 76.38, zhongshan.longitude);
  equal('murmansk zone is utc+3', 3 * 3600,
    ZoneTable.offsetSeconds(murmansk.countryCode, murmansk.longitude, 0));
  equal('zhongshan zone is utc+8', 8 * 3600,
    ZoneTable.offsetSeconds(zhongshan.countryCode, zhongshan.longitude, 0));
  const murmanskName = CityIndex.nearest(murmansk.latitude, murmansk.longitude, 'zh');
  equal('murmansk name', '摩尔曼斯克', murmanskName === null ? 'null' : murmanskName.name);
  const zhongshanName = CityIndex.nearest(zhongshan.latitude, zhongshan.longitude, 'zh');
  equal('zhongshan name', '南极中山站', zhongshanName === null ? 'null' : zhongshanName.name);

  // 极昼／极夜：卡片上「日出 / 日落」两格没有时刻，显示 "--:--"，下方另行提示极昼／极夜。
  const december = Date.UTC(2026, 11, 21, 12, 0, 0);
  const murmanskWinter: SolarSnapshot = SolarTimeSnapshot.compute(
    december, murmansk.latitude, murmansk.longitude, 'zh-CN', 3 * 3600, murmansk.countryCode);
  equal('murmansk december is polar night', PolarState.POLAR_NIGHT, murmanskWinter.polar);
  equal('murmansk sunrise shows dash', '--:--', TimeFormat.clock(murmanskWinter.sunriseLocalSeconds));
  equal('murmansk sunset shows dash', '--:--', TimeFormat.clock(murmanskWinter.sunsetLocalSeconds));
  const zhongshanSummer: SolarSnapshot = SolarTimeSnapshot.compute(
    december, zhongshan.latitude, zhongshan.longitude, 'zh-CN', 8 * 3600, zhongshan.countryCode);
  equal('zhongshan december is midnight sun', PolarState.MIDNIGHT_SUN, zhongshanSummer.polar);
  equal('zhongshan sunrise shows dash', '--:--', TimeFormat.clock(zhongshanSummer.sunriseLocalSeconds));
  equal('zhongshan sunset shows dash', '--:--', TimeFormat.clock(zhongshanSummer.sunsetLocalSeconds));
}

// ---- 「是不是中国境内」：国家码优先，没有国家码才退回包围盒 ----
{
  // 与页面/卡片同一条管线：有国家码按国家码查 ZoneTable，表里没有才由 SolarTimeMath 兜底。
  const zoneOf = (latitude: number, longitude: number, countryCode: string): number =>
    ZoneTable.offsetSeconds(countryCode, longitude,
      SolarTimeMath.standardZoneOffsetSeconds(latitude, longitude, countryCode));

  // 回归：早先只按经纬度包围盒（73–135°E / 18–54°N）判断，新德里（77.2°E, 28.6°N）落在框内，
  // 于是被当成中国 —— 时区显示 UTC+8（应为 +5:30），底图也去拉高德的瓦片。
  const delhiLatitude = 28.6139;
  const delhiLongitude = 77.2090;
  check('delhi with country code in is not in china',
    !SolarTimeMath.isInChina(delhiLatitude, delhiLongitude, 'in'));
  equal('delhi with country code in resolves utc+5:30', 19800,
    zoneOf(delhiLatitude, delhiLongitude, 'in'));

  // 对照：上海 + cn 仍然是境内、仍然 +8。
  check('shanghai with country code cn is in china',
    SolarTimeMath.isInChina(31.2304, 121.4737, 'cn'));
  equal('shanghai with country code cn resolves utc+8', 28800,
    zoneOf(31.2304, 121.4737, 'cn'));

  // 港澳台按国家码算境内，也是 +8。
  let everyChinaCodeOk: boolean = true;
  for (const code of SolarTimeMath.CHINA_COUNTRY_CODES) {
    if (!SolarTimeMath.isInChina(31.2304, 121.4737, code) || zoneOf(31.2304, 121.4737, code) !== 28800) {
      everyChinaCodeOk = false;
    }
  }
  check('cn/hk/mo/tw all count as china and stay utc+8', everyChinaCodeOk);

  // 国家码大小写不敏感（空白视为未知）。
  check('country code is case insensitive',
    SolarTimeMath.isInChina(31.2304, 121.4737, 'CN')
      && !SolarTimeMath.isInChina(delhiLatitude, delhiLongitude, ' in '));

  // 没有国家码时才用包围盒：新德里仍在框内 → 退回旧行为（判境内、+8）。
  // 这是**有意保留**的兜底（与 Android 一致）：包围盒只是粗略近似，所以三端都优先用国家码。
  check('delhi without country code falls back to the bbox (known approximation)',
    SolarTimeMath.isInChina(delhiLatitude, delhiLongitude));
  equal('delhi without country code falls back to +8', 28800,
    zoneOf(delhiLatitude, delhiLongitude, ''));

  // 加德满都 27.7N / 85.3E：无国家码 → 包围盒判境内（+8）；有 np → 境外且 +5:45。
  check('kathmandu without country code uses the bbox', SolarTimeMath.isInChina(27.7, 85.3));
  equal('kathmandu without country code is +8 via the bbox', 28800, zoneOf(27.7, 85.3, ''));
  check('kathmandu with country code np is not in china', !SolarTimeMath.isInChina(27.7, 85.3, 'np'));
  equal('kathmandu with country code np resolves utc+5:45', 20700, zoneOf(27.7, 85.3, 'np'));

  // 境内没有国家码时也必须 +8：乌鲁木齐 87.6°E 按经度近似会被算成 +6。
  equal('urumqi without country code stays utc+8', 28800, zoneOf(43.8256, 87.6168, ''));

  // 端到端：快照里的当地偏移也跟着国家码走（与页面/卡片一致：偏移由 ZoneTable 算好再传进来）。
  const delhiSnapshot = SolarTimeSnapshot.compute(
    Date.UTC(2026, 10, 14, 4, 0, 0), delhiLatitude, delhiLongitude, 'zh-Hans',
    zoneOf(delhiLatitude, delhiLongitude, 'in'), 'in');
  equal('delhi snapshot uses utc+5:30', 19800, delhiSnapshot.localOffsetSeconds);
  const delhiSnapshotNoCode = SolarTimeSnapshot.compute(
    Date.UTC(2026, 10, 14, 4, 0, 0), delhiLatitude, delhiLongitude, 'zh-Hans');
  equal('delhi snapshot without country code falls back to +8', 28800,
    delhiSnapshotNoCode.localOffsetSeconds);

  // 预设城市自带国家码：选中新德里就当场是 +5:30，不必等逆地理回来。
  const delhiPreset: Place = Place.PRESETS[16];
  equal('delhi preset carries country code in', 'in', delhiPreset.countryCode);
  equal('delhi preset resolves utc+5:30', 19800,
    zoneOf(delhiPreset.latitude, delhiPreset.longitude, delhiPreset.countryCode));
}

// ---- 国家标准时间（core/CivicTime）：中国 +8、南极中国站 +8、其它国家用国家标准 ----
{
  equal('urumqi uses china standard time', 480,
    CivicTimeLogic.standardOffsetMinutes(43.8256, 87.6168, 'cn'));
  equal('beijing uses china standard time', 480,
    CivicTimeLogic.standardOffsetMinutes(39.9042, 116.4074, 'cn'));
  equal('zhongshan uses china standard time', 480,
    CivicTimeLogic.standardOffsetMinutes(-69.37, 76.38, 'aq'));
  equal('great wall station uses china standard time', 480,
    CivicTimeLogic.standardOffsetMinutes(-62.22, -58.96, 'aq'));
  equal('kunlun station uses china standard time', 480,
    CivicTimeLogic.standardOffsetMinutes(-80.42, 77.12, 'aq'));
  equal('murmansk uses russia standard time', 180,
    CivicTimeLogic.standardOffsetMinutes(68.97, 33.08, 'ru'));
  // 鸿蒙这边没有城市级 tzdata，纽约按国家标准 −300（与 Android 的 ZoneTable 口径一致）。
  equal('new york uses us eastern standard time', -300,
    CivicTimeLogic.standardOffsetMinutes(40.71, -74.01, 'us'));
  equal('kathmandu keeps its 45 minute offset', 345,
    CivicTimeLogic.standardOffsetMinutes(27.7, 85.3, 'np'));
  equal('civic time also returns seconds', 28800,
    CivicTimeLogic.standardOffsetSeconds(43.8256, 87.6168, 'cn'));

  // 南极的非中国站不能套用 +8：挪威 Troll（72.0°S 2.5°E）按本国/经度是 UTC+0。
  check('non-chinese antarctic station is not +8',
    !CivicTimeLogic.isChineseAntarcticStation(-72.01, 2.53));
  equal('troll keeps its own zone', 0,
    CivicTimeLogic.standardOffsetMinutes(-72.01, 2.53, 'aq'));

  // 端到端：乌鲁木齐快照拿到的当地偏移就是 +8，真太阳时与标准时间相差约 2 小时 10 分。
  const urumqiSnapshot: SolarSnapshot = SolarTimeSnapshot.compute(
    Date.UTC(2026, 10, 14, 4, 0, 0), 43.8256, 87.6168, 'zh-Hans',
    CivicTimeLogic.standardOffsetSeconds(43.8256, 87.6168, 'cn'), 'cn');
  equal('urumqi snapshot local offset is utc+8', 28800, urumqiSnapshot.localOffsetSeconds);
}

// ---- 位置地图瓦片 ----
{
  const shanghai = MapTilesLogic.layerFor(31.2304, 121.4737);
  const tokyo = MapTilesLogic.layerFor(35.6812, 139.7671);
  check('amap inside China', shanghai.datum === MapDatum.GCJ02 && shanghai.name.indexOf('amap') === 0);
  check('outside China now prefers ESRI', tokyo.datum === MapDatum.WGS84 && tokyo.name === 'esri');
  check('china bounds', MapTilesLogic.isInChina(31.23, 121.47) && !MapTilesLogic.isInChina(35.68, 139.76));

  // 自动选底图也按国家码判境内：新德里（in）用 ESRI，上海（cn）用高德；
  // 没有国家码时才退回包围盒（新德里在框内 → 旧行为高德，加德满都同理）。
  check('auto layer picks esri for delhi with country code in',
    MapTilesLogic.layerFor(28.6139, 77.2090, 'in').name === 'esri');
  check('auto layer picks amap for shanghai with country code cn',
    MapTilesLogic.layerFor(31.2304, 121.4737, 'cn').name === 'amap-vector');
  check('auto layer falls back to the bbox without a country code',
    MapTilesLogic.layerForStyle(MapStyle.AUTO, 28.6139, 77.2090).name === 'amap-vector'
      && MapTilesLogic.layerForStyle(MapStyle.AUTO, 35.6812, 139.7671).name === 'esri');

  // 高德底图是 GCJ-02：上海一带的偏移在千米级（0.001°~0.01°）。
  const gcj = MapTilesLogic.toGcj02(31.2304, 121.4737);
  const dLat = Math.abs(gcj[0] - 31.2304);
  const dLon = Math.abs(gcj[1] - 121.4737);
  check('gcj02 offset inside China', dLat > 0.001 && dLat < 0.01 && dLon > 0.001 && dLon < 0.01,
    `${dLat},${dLon}`);
  const abroad = MapTilesLogic.toGcj02(35.6812, 139.7671);
  check('gcj02 leaves abroad untouched', abroad[0] === 35.6812 && abroad[1] === 139.7671);
  const display = MapTilesLogic.displayPoint(tokyo, 35.6812, 139.7671);
  check('osm keeps wgs84', display[0] === 35.6812);

  // 缩放 0 时全世界就是一片瓦片的中心。
  const world = MapTilesLogic.tilePoint(0, 0, 0);
  near('tile point at zoom 0', 0.5, world[0], 1e-9);
  near('tile point at zoom 0 y', 0.5, world[1], 1e-9);
  const tile = MapTilesLogic.tilePoint(31.2304, 121.4737, 12);
  const back = MapTilesLogic.pointToLatLon(tile[0], tile[1], 12);
  near('tile point round trip lat', 31.2304, back[0], 1e-6);
  near('tile point round trip lon', 121.4737, back[1], 1e-6);

  // 手指向右拖（+x）等于看更西边，经度应变小。
  const moved = MapTilesLogic.shift(31.2304, 121.4737, 12, TILE_PX, 0);
  check('drag east looks west', moved[1] < 121.4737, `${moved[1]}`);
  near('drag keeps latitude', 31.2304, moved[0], 1e-9);

  const widthPx = 988;
  const heightPx = 570;
  const tiles = MapTilesLogic.visibleTiles(shanghai, 31.2304, 121.4737, 12, widthPx, heightPx);
  check('tiles cover viewport', tiles.length >= 12, `${tiles.length}`);
  let covered = true;
  for (const one of tiles) {
    if (one.leftPx > widthPx || one.leftPx + TILE_PX < 0 || one.topPx > heightPx || one.topPx + TILE_PX < 0) {
      covered = false;
    }
  }
  check('no tile outside viewport', covered);
  // 中心落在视口正中：至少有一片瓦片横跨中线。
  let spansCenter = false;
  for (const one of tiles) {
    if (one.leftPx <= widthPx / 2 && one.leftPx + TILE_PX >= widthPx / 2) {
      spansCenter = true;
    }
  }
  check('center covered', spansCenter);
  check('amap tile url', tiles[0].url.indexOf('is.autonavi.com/appmaptile') > 0 && tiles[0].url.indexOf('&z=12') > 0);
  const forcedOsmLayer = MapTilesLogic.layerForStyle(MapStyle.OSM, 35.6812, 139.7671);
  const osmTile = MapTilesLogic.visibleTiles(forcedOsmLayer, 35.6812, 139.7671, 12, widthPx, heightPx)[0];
  check('forced osm tile url', osmTile.url.indexOf('tile.openstreetmap.org/12/') > 0);
  // ESRI 的路径顺序是 z/y/x：上海 z12 应为 /12/1673/3430（y 在前）。
  const esriLayer = MapTilesLogic.layerForStyle(MapStyle.ESRI, 31.2304, 121.4737);
  check('esri tile url uses z/y/x order',
    esriLayer.name === 'esri' &&
      MapTilesLogic.tileUrl(esriLayer, 12, 3430, 1673).indexOf('/12/1673/3430') > 0);
  const esriTile = MapTilesLogic.visibleTiles(esriLayer, 31.2304, 121.4737, 12, widthPx, heightPx)[0];
  check('esri layer builds esri urls', esriTile.url.indexOf('server.arcgisonline.com') > 0);
  check('zoom clamped', MapTilesLogic.clampZoom(1) === MIN_ZOOM && MapTilesLogic.clampZoom(99) === MAX_ZOOM);

  // 设置页可选的底图：自动按位置判断，其余三种强制指定。
  check('style key auto', MapTilesLogic.styleFromKey('auto') === MapStyle.AUTO);
  check('style key satellite', MapTilesLogic.styleFromKey('amap-satellite') === MapStyle.AMAP_SATELLITE);
  check('style key esri', MapTilesLogic.styleFromKey('esri') === MapStyle.ESRI);
  check('unknown style key falls back to auto', MapTilesLogic.styleFromKey('nope') === MapStyle.AUTO);
  check('option keys match styles', MAP_STYLE_OPTIONS.length === 5
    && MapTilesLogic.styleFromKey(MAP_STYLE_OPTIONS[3].key) === MapStyle.AMAP_VECTOR);
  equal('map style option order', 'AUTO,ESRI,OSM,AMAP_VECTOR,AMAP_SATELLITE',
    MAP_STYLE_OPTIONS.map((option): string => MapStyle[option.style]).join(','));
  equal('auto hint (simplified)',
    '自动：境内用高德，境外用 Esri 街道图；连不上时依次回退 OSM、高德',
    MapTilesLogic.autoHint('zh-CN'));
  equal('auto hint (traditional)',
    '自動：境內用高德，境外用 Esri 街道圖；連不上時依次回退 OSM、高德',
    MapTilesLogic.autoHint('zh-Hant'));
  equal('auto hint (english)',
    'Auto: AMap inside China, Esri Street Map elsewhere; falls back to OSM, then AMap',
    MapTilesLogic.autoHint('en-US'));
  const forcedOsm = MapTilesLogic.layerForStyle(MapStyle.OSM, 31.2304, 121.4737);
  check('osm forced inside china', forcedOsm.datum === MapDatum.WGS84 && forcedOsm.name === 'osm');
  const esriAttribution: string = MapTilesLogic.layerForStyle(MapStyle.ESRI, 31.2304, 121.4737).attribution;
  equal('esri attribution localized to chinese',
    '底图 © Esri, HERE, Garmin, © OpenStreetMap 贡献者',
    MapTilesLogic.localizedAttribution(esriAttribution, 'zh-CN'));
  equal('esri attribution localized to traditional chinese',
    '底图 © Esri, HERE, Garmin, © OpenStreetMap 貢獻者',
    MapTilesLogic.localizedAttribution(esriAttribution, 'zh-Hant'));
  equal('esri attribution stays english in english ui', esriAttribution,
    MapTilesLogic.localizedAttribution(esriAttribution, 'en-US'));
  const osmAttribution: string = MapTilesLogic.layerForStyle(MapStyle.OSM, 31.2304, 121.4737).attribution;
  const vectorAttribution: string =
    MapTilesLogic.layerForStyle(MapStyle.AMAP_VECTOR, 31.2304, 121.4737).attribution;
  const satelliteAttribution: string =
    MapTilesLogic.layerForStyle(MapStyle.AMAP_SATELLITE, 31.2304, 121.4737).attribution;
  check('osm attribution is not the esri one',
    osmAttribution !== esriAttribution && osmAttribution.indexOf('OpenStreetMap') >= 0);
  check('each map style has its own attribution',
    vectorAttribution !== esriAttribution && vectorAttribution !== osmAttribution &&
      satelliteAttribution !== esriAttribution && satelliteAttribution !== osmAttribution &&
      satelliteAttribution !== vectorAttribution);
  check('manual tile concurrency is at most 6',
    MANUAL_TILE_CONCURRENCY >= 1 && MANUAL_TILE_CONCURRENCY <= 6);
  check('esri full attribution keeps OSM contributors',
    MapTilesLogic.ESRI_FULL_ATTRIBUTION.indexOf('OpenStreetMap contributors') >= 0);
  check('esri full attribution keeps the GIS user community',
    MapTilesLogic.ESRI_FULL_ATTRIBUTION.indexOf('GIS User Community') >= 0);
  const esriAbout: string = MapTilesLogic.aboutAttribution(MapStyle.ESRI, 'zh-CN');
  const osmAbout: string = MapTilesLogic.aboutAttribution(MapStyle.OSM, 'zh-CN');
  const amapAbout: string = MapTilesLogic.aboutAttribution(MapStyle.AMAP_VECTOR, 'zh-CN');
  check('about attributions differ per source',
    esriAbout !== osmAbout && esriAbout !== amapAbout && osmAbout !== amapAbout);
  check('the about page shows the full esri attribution, not the card short one',
    esriAbout !== MapTilesLogic.layerForStyle(MapStyle.ESRI, 0, 0).attribution);
  check('esri about link is present',
    MapTilesLogic.aboutLink(MapStyle.ESRI).indexOf('arcgisonline') >= 0);
  check('osm about link is present',
    MapTilesLogic.aboutLink(MapStyle.OSM).indexOf('openstreetmap.org') >= 0);
  const forcedSatellite = MapTilesLogic.layerForStyle(MapStyle.AMAP_SATELLITE, 35.6812, 139.7671);
  check('satellite forced outside china', forcedSatellite.datum === MapDatum.GCJ02
    && forcedSatellite.name === 'amap-satellite');
  const satelliteTile = MapTilesLogic.visibleTiles(forcedSatellite, 31.2304, 121.4737, 12, widthPx, heightPx)[0];
  check('satellite tile url', satelliteTile.url.indexOf('webst0') > 0 && satelliteTile.url.indexOf('style=6') > 0);
  check('auto layer still follows place',
    MapTilesLogic.layerForStyle(MapStyle.AUTO, 31.2304, 121.4737).name === 'amap-vector'
    && MapTilesLogic.layerForStyle(MapStyle.AUTO, 35.6812, 139.7671).name === 'esri');
}

// ---- 地图底图兜底：空白瓦片判定 + 回退/降级状态机 ----
{
  const solid = (color: number): number[] => new Array(1024).fill(color);
  const shaded = (count: number, step: number): number[] => {
    const colors: number[] = [];
    for (let index = 0; index < 1024; index++) {
      const value: number = 100 + (index % count) * step;
      colors.push((value << 16) | (value << 8) | value);
    }
    return colors;
  };

  check('pure grey tile is blank', MapTileLogic.analyze(solid(0x808080)).isBlank);
  const greyText: number[] = solid(0x808080);
  for (let index = 0; index < 16; index++) {
    greyText[index * 7] = 0xFFFFFF;
  }
  check('grey tile with watermark text is blank', MapTileLogic.analyze(greyText).isBlank);
  check('multi colour tile is not blank', !MapTileLogic.analyze(shaded(16, 17)).isBlank);
  const blue = MapTileLogic.analyze(solid(0x1E6EB5));
  check('pure blue is ocean, not blank', blue.isOcean && !blue.isBlank);

  // 颜色种类边界：7 种算空白，8 种、9 种不算（量化后仍是不同颜色，方差都在 400 以内）。
  const palette = (count: number): number[] => {
    const base: number[] = [0x707070, 0x807070, 0x708070, 0x707080, 0x808080,
      0x708080, 0x807080, 0x808070, 0x907070];
    const colors: number[] = [];
    for (let index = 0; index < 1024; index++) {
      colors.push(base[index % count]);
    }
    return colors;
  };
  check('seven colour kinds is blank', MapTileLogic.analyze(palette(7)).isBlank);
  check('eight colour kinds is not blank', !MapTileLogic.analyze(palette(8)).isBlank);
  check('nine colour kinds is not blank', !MapTileLogic.analyze(palette(9)).isBlank);

  // 整屏：所有看过的瓦片都空白才算这一屏空白；空集合不算。
  check('empty viewport is not blank', !MapTileLogic.viewportIsBlank([]));
  check('all blank tiles make the viewport blank',
    MapTileLogic.viewportIsBlank([MapTileLogic.analyze(solid(0x808080)),
      MapTileLogic.analyze(solid(0xF0F0F0))]));
  check('one content tile keeps the viewport alive',
    !MapTileLogic.viewportIsBlank([MapTileLogic.analyze(solid(0x808080)),
      MapTileLogic.analyze(shaded(16, 17))]));

  // ---- 状态机 ----
  const now: number = 1_700_000_000_000;
  const london: number[] = [51.5074, -0.1278];
  let state = new MapFallbackState();
  for (let index = 0; index < 3; index++) {
    state = MapFallback.onTileFailed(MapStyle.AUTO, london[0], london[1], 'gb', 12, state, now + index);
  }
  check('three esri failures mark z12 unavailable',
    state.zoomUnavailable(MapStyle.ESRI, 12) && !state.fellBack);
  const fallbackPlan = MapFallback.plan(MapStyle.AUTO, london[0], london[1], 'gb', state);
  check('overseas auto still plans esri before degrading',
    !fallbackPlan.fellBack && fallbackPlan.effective === MapStyle.ESRI);
  // 探测相关用例用一份「已回退」状态：ESRI 成为境外偏好后，OSM 失败不再触发回退。
  const fbState = new MapFallbackState();
  fbState.fellBack = true;
  fbState.fallbackFailures = 3;
  fbState.probeAtMillis = now + MapFallback.PROBE_INTERVAL_MILLIS;
  const partial = MapFallback.onTileFailed(MapStyle.AUTO, london[0], london[1], 'gb', 12,
    MapFallback.onTileFailed(MapStyle.AUTO, london[0], london[1], 'gb', 12, new MapFallbackState(), now), now + 1);
  const recovered = MapFallback.onTileLoaded(MapStyle.AUTO, london[0], london[1], 'gb', 12, partial, now + 100);
  check('any osm success resets the failure counter', !recovered.fellBack && recovered.osmFailures === 0);

  // 手动选择底图：不回退、不探测。
  let manual = new MapFallbackState();
  for (let index = 0; index < 5; index++) {
    manual = MapFallback.onTileFailed(MapStyle.OSM, london[0], london[1], 'gb', 12, manual, now + index);
  }
  check('manual style never falls back', !manual.fellBack && manual.osmFailures === 0);

  // 降级链：z12 → z11 → z10 → z3，z3 仍空白 → 底图不可用。
  let degrade = new MapFallbackState();
  for (let index = 0; index < 3; index++) {
    degrade = MapFallback.onTileFailed(MapStyle.AUTO, london[0], london[1], 'gb', 12, degrade, now + index);
  }
  const afterFallback: MapTilePlan = MapFallback.plan(MapStyle.AUTO, london[0], london[1], 'gb', degrade);
  const later: number = now + 10_000;
  for (let index = 0; index < 3; index++) {
    degrade = MapFallback.onTileFailed(MapStyle.AUTO, london[0], london[1], 'gb', 12, degrade, later + index);
  }
  check('z12 has no tiles after three failures',
    MapFallback.zoomPlan(afterFallback, 12, degrade).zoom === 11);
  for (let index = 0; index < 3; index++) {
    degrade = MapFallback.onTileFailed(MapStyle.AUTO, london[0], london[1], 'gb', 11, degrade, later + 100 + index);
  }
  check('z11 degrades to z10', MapFallback.zoomPlan(afterFallback, 12, degrade).zoom === 10);
  for (let index = 0; index < 3; index++) {
    degrade = MapFallback.onTileFailed(MapStyle.AUTO, london[0], london[1], 'gb', 10, degrade, later + 200 + index);
  }
  check('z10 degrades to the z3 world map', MapFallback.zoomPlan(afterFallback, 12, degrade).zoom === 3
    && MapFallback.zoomPlan(afterFallback, 12, degrade).degraded);
  for (let index = 0; index < 3; index++) {
    degrade = MapFallback.onTileBlank(MapStyle.AUTO, london[0], london[1], 'gb', 3, degrade,
      later + 300 + index, 2);
  }
  check('a blank z3 shows the unavailable state', MapFallback.zoomPlan(afterFallback, 12, degrade).unavailable);

  // 有内容的 z3 会清掉网络失败记忆，但空白记忆保留（避免 z12 ↔ z3 来回跳）。
  const blanked = MapFallback.onTileBlank(MapStyle.AUTO, london[0], london[1], 'gb', 12, new MapFallbackState(),
    now, 3);
  check('blank tile is counted for diagnostics',
    blanked.blankTileCount === 1 && blanked.lastBlankZoom === 12 && blanked.lastBlankColorKinds === 3);

  // 5 分钟探测：到点才探；失败顺延 5 分钟，成功切回并清零（用合成回退状态）。
  check('probe is not due before five minutes',
    !MapFallback.probeDue(fbState, fbState.probeAtMillis - 1));
  check('probe is due at five minutes', MapFallback.probeDue(fbState, fbState.probeAtMillis));
  const probeFailed = MapFallback.onProbeResult(fbState, false, fbState.probeAtMillis);
  check('failed probe pushes the next probe five minutes out',
    probeFailed.fellBack &&
      probeFailed.probeAtMillis === fbState.probeAtMillis + MapFallback.PROBE_INTERVAL_MILLIS);
  const probeOk = MapFallback.onProbeResult(fbState, true, fbState.probeAtMillis);
  check('successful probe switches back to osm', !probeOk.fellBack && probeOk.osmFailures === 0);

  // 采样：256×256 按步长 8 抽 32×32 个点（最近邻）。
  const rgba: number[] = new Array(256 * 256 * 4).fill(0);
  const samples = MapTileLogic.sampleNearest(rgba, 256, 256);
  check('nearest sampling yields 32x32 colours', samples.length === 1024);

  // ---- 防「切城市后地图狂闪」的三条 ----
  // ① UI 只订阅有效 plan 快照：快照相同 → sameUiState true，Index 不 setState。
  const uiPlan: MapTilePlan = MapFallback.plan(MapStyle.AUTO, 51.5074, -0.1278, 'gb', new MapFallbackState());
  const uiZoom = MapFallback.zoomPlan(uiPlan, 12, new MapFallbackState());
  const first: MapUiState = uiStateOf(uiPlan, uiZoom);
  const second: MapUiState = uiStateOf(uiPlan, uiZoom);
  check('unchanged plan yields the same ui state', sameUiState(first, second));
  const otherZoom = MapFallback.zoomPlan(uiPlan, 11, new MapFallbackState());
  check('changed zoom yields a different ui state', !sameUiState(first, uiStateOf(uiPlan, otherZoom)));

  // ② z3 出图后 30 秒静默窗口未满 → 不清上级「没瓦片」记忆，不回弹（否则 z3↔z12 无限升降）。
  let chain = new MapFallbackState();
  for (let index = 0; index < 3; index++) {
    chain = MapFallback.onTileFailed(MapStyle.AUTO, 51.5074, -0.1278, 'gb', 12, chain, now + index);
  }
  const chainBase: number = now + 10_000;
  for (const zoom of [12, 11, 10]) {
    for (let index = 0; index < 3; index++) {
      chain = MapFallback.onTileFailed(MapStyle.AUTO, 51.5074, -0.1278, 'gb', zoom, chain,
        chainBase + zoom * 100 + index);
    }
  }
  check('chain starts at z3 after upper zooms fail',
    MapFallback.zoomPlan(MapFallback.plan(MapStyle.AUTO, 51.5074, -0.1278, 'gb', chain), 12, chain).zoom === 3);
  const quiet = MapFallback.onTileLoaded(MapStyle.AUTO, 51.5074, -0.1278, 'gb', 3, chain,
    chainBase + 20_000);
  check('z3 success does not rebound inside the 30s quiet window',
    MapFallback.zoomPlan(MapFallback.plan(MapStyle.AUTO, 51.5074, -0.1278, 'gb', quiet), 12, quiet).zoom === 3);
  const rebound = MapFallback.onTileLoaded(MapStyle.AUTO, 51.5074, -0.1278, 'gb', 3, quiet,
    chainBase + 20_000 + MapFallback.RECOVER_QUIET_MILLIS + 1_000);
  check('z3 success rebounds after the quiet window',
    MapFallback.zoomPlan(MapFallback.plan(MapStyle.AUTO, 51.5074, -0.1278, 'gb', rebound), 12, rebound).zoom === 12);

  // ③ 回弹后 5 分钟冷却：再次 z3 出图也不回弹。
  const cooled = rebound.copy();
  cooled.lastReboundMillis = chainBase + 40_000;
  cooled.lastFailureMillis = -1;
  cooled.esriUnavailableMask = (1 << 12) | (1 << 11) | (1 << 10);
  cooled.esriBlankMask = 0;
  const stillCooling = MapFallback.onTileLoaded(MapStyle.AUTO, 51.5074, -0.1278, 'gb', 3, cooled,
    cooled.lastReboundMillis + 60_000);
  check('no rebound within the five minute cooldown',
    MapFallback.zoomPlan(MapFallback.plan(MapStyle.AUTO, 51.5074, -0.1278, 'gb', stillCooling), 12,
      stillCooling).zoom === 3);

  // ④ 程序化改视口后 2 秒内的失败不计（自身取消请求造成的假失败）。
  const viewportSettling = MapFallback.markViewportSettling(new MapFallbackState(), now);
  const ignoredFailure = MapFallback.onTileFailed(MapStyle.AUTO, 51.5074, -0.1278, 'gb', 12,
    viewportSettling, now + 1_000);
  check('failures inside the viewport settle window are ignored', ignoredFailure.osmFailures === 0);
  const countedFailure = MapFallback.onTileFailed(MapStyle.AUTO, 51.5074, -0.1278, 'gb', 12,
    viewportSettling, now + 2_500);
  check('failures after the settle window are counted', countedFailure.zoomFailures === 1);

  // ---- 首屏并行探测：decide / zoomsAbove / cacheKey / shouldProbe / tileOf ----
  const amap = new AmapProbe();
  equal('osm reachable wins with z12', MapStyle.OSM, decide(true, amap).source);
  equal('osm reachable keeps z12', 12, decide(true, amap).zoom);
  amap.setState(12, AmapProbe.CONTENT);
  const z12Decision = decide(false, amap);
  check('amap z12 is preferred when osm is down',
    z12Decision.source === MapStyle.AMAP_VECTOR && z12Decision.zoom === 12 && !z12Decision.unavailable);
  amap.setState(12, AmapProbe.EMPTY);
  amap.setState(10, AmapProbe.CONTENT);
  equal('amap falls back to z10', 10, decide(false, amap).zoom);
  amap.setState(10, AmapProbe.EMPTY);
  amap.setState(3, AmapProbe.CONTENT);
  equal('amap falls back to z3', 3, decide(false, amap).zoom);
  amap.setState(3, AmapProbe.EMPTY);
  check('all probes blank means unavailable', decide(false, amap).unavailable);

  // 三态早退：更高精度还在飞时不能拿低精度抢答。
  const earlyZ3 = new AmapProbe();
  earlyZ3.setState(3, AmapProbe.CONTENT);
  check('z3 content with z12/z10 still flying does not early exit',
    !shouldEarlyExit(earlyZ3, [12, 10, 3]));
  earlyZ3.setState(12, AmapProbe.EMPTY);
  earlyZ3.setState(10, AmapProbe.EMPTY);
  check('z3 content with higher zooms settled can early exit', shouldEarlyExit(earlyZ3, [12, 10, 3]));
  equal('settled z3 case chooses z3', 3, decide(false, earlyZ3).zoom);

  const earlyZ12 = new AmapProbe();
  earlyZ12.setState(12, AmapProbe.CONTENT);
  equal('best content zoom tracks the tri-state', 12, bestContentZoom(earlyZ12));
  check('z12 content exits immediately', shouldEarlyExit(earlyZ12, [12, 10, 3]));
  const earlyZ10 = new AmapProbe();
  earlyZ10.setState(12, AmapProbe.EMPTY);
  earlyZ10.setState(10, AmapProbe.CONTENT);
  check('z10 content with z12 settled can early exit', shouldEarlyExit(earlyZ10, [12, 10, 3]));
  equal('settled z10 case chooses z10', 10, decide(false, earlyZ10).zoom);
  const noContent = new AmapProbe();
  noContent.setState(12, AmapProbe.EMPTY);
  noContent.setState(10, AmapProbe.EMPTY);
  noContent.setState(3, AmapProbe.EMPTY);
  check('no content never early exits', !shouldEarlyExit(noContent, [12, 10, 3]));
  // 端到端：z3 先回有内容，z12 后回有内容 → 最终必须选 z12。
  const lateZ12 = new AmapProbe();
  lateZ12.setState(3, AmapProbe.CONTENT);
  check('late z12 keeps the probe waiting', !shouldEarlyExit(lateZ12, [12, 10, 3]));
  lateZ12.setState(12, AmapProbe.CONTENT);
  equal('late z12 wins over earlier z3', 12, decide(false, lateZ12).zoom);
  check('late z12 now allows early exit', shouldEarlyExit(lateZ12, [12, 10, 3]));

  // ---- 渐进升级：先到先用、更好的才升级、冻结条件 ----
  const progressive = new ProgressiveProbe(0);
  check('first z3 is shown immediately',
    progressive.consider(MapStyle.AMAP_VECTOR, 3, true, 312));
  check('later z12 upgrades the z3',
    progressive.consider(MapStyle.AMAP_VECTOR, 12, true, 1830));
  equal('final zoom after progressive upgrade', 12, progressive.zoom);
  equal('progressive diagnostic', '首图 z3 @312ms，升级 z12 @1830ms', progressive.describe(2000));

  const z12First = new ProgressiveProbe(0);
  z12First.consider(MapStyle.AMAP_VECTOR, 12, true, 300);
  check('z3 arriving after z12 is ignored', !z12First.consider(MapStyle.AMAP_VECTOR, 3, true, 900));
  equal('z12 stays after late z3', 12, z12First.zoom);

  const sourceUpgrade = new ProgressiveProbe(0);
  sourceUpgrade.consider(MapStyle.AMAP_VECTOR, 12, true, 300);
  check('osm z12 upgrades an amap z12', sourceUpgrade.consider(MapStyle.OSM, 12, true, 900));
  equal('source upgraded to osm', MapStyle.OSM, sourceUpgrade.source);

  const alreadyBest = new ProgressiveProbe(0, MapStyle.OSM);
  alreadyBest.consider(MapStyle.OSM, 12, true, 300);
  check('osm z12 ignores everything later', !alreadyBest.consider(MapStyle.OSM, 12, true, 900));
  check('osm z12 is a stop condition', alreadyBest.stopped(900));

  const interacted = new ProgressiveProbe(0);
  interacted.consider(MapStyle.AMAP_VECTOR, 3, true, 200);
  interacted.markUserInteracted();
  check('user interaction freezes upgrades', !interacted.consider(MapStyle.AMAP_VECTOR, 12, true, 800));

  const tooLate = new ProgressiveProbe(0);
  tooLate.consider(MapStyle.AMAP_VECTOR, 3, true, 200);
  check('upgrade after ten seconds is ignored',
    !tooLate.consider(MapStyle.AMAP_VECTOR, 12, true, 10_201));

  const emptyProbe = new ProgressiveProbe(0);
  check('no result before four seconds is not unavailable', !emptyProbe.unavailable(3_999));
  check('no result at four seconds is unavailable', emptyProbe.unavailable(4_000));
  check('blank results never become content', !emptyProbe.consider(MapStyle.AMAP_VECTOR, 3, false, 100));
  equal('higher zoom beats a different source',
    false, isBetterTile(MapStyle.OSM, 3, MapStyle.AMAP_VECTOR, 12));

  // ---- 先换源、再降级：同级按区域偏好选源 ----
  const domestic = new ProgressiveProbe(0, MapStyle.AMAP_VECTOR);
  check('domestic prefers amap at the same zoom',
    domestic.consider(MapStyle.AMAP_VECTOR, 12, true, 100));
  check('domestic ignores osm at the same zoom',
    !domestic.consider(MapStyle.OSM, 12, true, 200));

  const domesticFallback = new ProgressiveProbe(0, MapStyle.AMAP_VECTOR);
  check('blank amap z12 lets osm z12 through immediately',
    domesticFallback.consider(MapStyle.OSM, 12, true, 300));
  equal('domestic fallback uses osm', MapStyle.OSM, domesticFallback.source);

  const abroad = new ProgressiveProbe(0, MapStyle.OSM);
  check('abroad preference ignores osm blank', !abroad.consider(MapStyle.OSM, 12, false, 100));
  check('abroad falls back to amap z12 when osm is blank',
    abroad.consider(MapStyle.AMAP_VECTOR, 12, true, 300));
  equal('abroad fallback uses amap', MapStyle.AMAP_VECTOR, abroad.source);

  const downgrade = new ProgressiveProbe(0, MapStyle.AMAP_VECTOR);
  downgrade.consider(MapStyle.AMAP_VECTOR, 10, true, 100);
  check('higher zoom upgrades from z10 to z12',
    downgrade.consider(MapStyle.OSM, 12, true, 900));
  equal('downgrade chain ends at z12', 12, downgrade.zoom);

  // 南极中山站：countryCode=cn → 偏好高德，但高德 z12 空白、OSM z12 有内容 → OSM z12。
  const zhongshanPreferred = MapFallback.preferredStyle(MapStyle.AUTO, -69.37, 76.38, 'cn');
  equal('zhongshan is region-preferred to amap', MapStyle.AMAP_VECTOR, zhongshanPreferred);
  const zhongshanProbe = new ProgressiveProbe(0, zhongshanPreferred);
  check('zhongshan amap z12 blank is skipped',
    !zhongshanProbe.consider(MapStyle.AMAP_VECTOR, 12, false, 200));
  check('zhongshan osm z12 wins', zhongshanProbe.consider(MapStyle.OSM, 12, true, 400));
  equal('zhongshan end-to-end source', MapStyle.OSM, zhongshanProbe.source);
  equal('zhongshan end-to-end zoom', 12, zhongshanProbe.zoom);

  // ---- ESRI：境外自动偏好源；三源按级别 + 优先级选择 ----
  equal('abroad auto prefers esri', MapStyle.ESRI,
    MapFallback.preferredStyle(MapStyle.AUTO, 35.6812, 139.7671, 'jp'));
  const esriProbe = new ProgressiveProbe(0, MapStyle.ESRI);
  check('esri z12 content is used', esriProbe.consider(MapStyle.ESRI, 12, true, 100));
  equal('esri z12 end-to-end', MapStyle.ESRI, esriProbe.source);
  const esriBlankOsm = new ProgressiveProbe(0, MapStyle.ESRI);
  check('esri blank falls to osm z12', esriBlankOsm.consider(MapStyle.OSM, 12, true, 200));
  equal('esri blank uses osm', MapStyle.OSM, esriBlankOsm.source);
  const bothForeignFail = new ProgressiveProbe(0, MapStyle.ESRI);
  check('both foreign blanks fall to amap z12',
    bothForeignFail.consider(MapStyle.AMAP_VECTOR, 12, true, 300));
  equal('both foreign blanks use amap', MapStyle.AMAP_VECTOR, bothForeignFail.source);
  const allZ12Fail = new ProgressiveProbe(0, MapStyle.ESRI);
  check('all z12 blanks fall to esri z3', allZ12Fail.consider(MapStyle.ESRI, 3, true, 400));
  equal('three-source fallback prefers esri z3', MapStyle.ESRI, allZ12Fail.source);
  equal('three-source fallback zoom is z3', 3, allZ12Fail.zoom);
  equal('esri ranks above osm at the same zoom', 2,
    sourceRank(MapStyle.ESRI, MapStyle.AMAP_VECTOR));

  equal('zooms above 12 is empty', '', zoomsAbove(12).join(','));
  equal('zooms above 10', '12,11', zoomsAbove(10).join(','));
  equal('zooms above 3', '12,11,10', zoomsAbove(3).join(','));

  equal('cache key groups points within 100m', cacheKey(31.2304, 121.4737), cacheKey(31.23041, 121.47372));
  check('cache key changes between cities', cacheKey(31.2304, 121.4737) !== cacheKey(35.6812, 139.7671));

  const emptyCache = new ProbeCache();
  check('manual choice never probes', !shouldProbe(MapStyle.AMAP_VECTOR, 'k', emptyCache, now));
  check('manual esri never probes', !needsProbe(MapStyle.ESRI, 'k', emptyCache, now));
  // 手动底图：连续失败 3 次 → 不可用；成功一块即恢复。
  const manualTiles = new ManualTileTracker();
  manualTiles.onResult(false);
  manualTiles.onResult(false);
  check('two manual failures are not unavailable', !manualTiles.unavailable);
  manualTiles.onResult(false);
  check('three manual failures become unavailable', manualTiles.unavailable);
  manualTiles.onResult(true);
  check('a successful tile recovers the manual map',
    !manualTiles.unavailable && manualTiles.failures === 0);
  check('auto probes when cache is empty', shouldProbe(MapStyle.AUTO, 'k', emptyCache, now));
  const freshCache = new ProbeCache();
  freshCache.key = 'k';
  freshCache.millis = now;
  check('fresh cache skips probing', !needsProbe(MapStyle.AUTO, 'k', freshCache, now + 1000));
  check('expired cache probes again',
    needsProbe(MapStyle.AUTO, 'k', freshCache, now + MapFallback.PROBE_CACHE_MILLIS + 1));
  check('changed place invalidates the cache', needsProbe(MapStyle.AUTO, 'other', freshCache, now));

  check('osm probe tile is a z3 osm tile',
    tileOf(MapStyle.OSM, 51.5074, -0.1278, 3).indexOf('tile.openstreetmap.org/3/') > 0);
  check('esri probe tile uses z/y/x',
    tileOf(MapStyle.ESRI, 31.2304, 121.4737, 12).indexOf('/12/1673/3430') > 0);
  check('amap probe tile carries the zoom',
    tileOf(MapStyle.AMAP_VECTOR, 51.5074, -0.1278, 12).indexOf('&z=12') > 0);

  const z10Applied = applyDecision(new MapFallbackState(),
    new ProbeDecision(MapStyle.AMAP_VECTOR, 10, false), now);
  check('decision marks higher zooms unavailable',
    z10Applied.zoomUnavailable(MapStyle.AMAP_VECTOR, 12) &&
      z10Applied.zoomUnavailable(MapStyle.AMAP_VECTOR, 11) &&
      !z10Applied.zoomUnavailable(MapStyle.AMAP_VECTOR, 10));
  check('decision sets the five minute rebound cooldown', z10Applied.lastReboundMillis === now);
  const unavailableApplied = applyDecision(new MapFallbackState(),
    new ProbeDecision(MapStyle.AMAP_VECTOR, 12, true), now);
  check('unavailable decision marks every probed zoom',
    unavailableApplied.zoomUnavailable(MapStyle.AMAP_VECTOR, 12) &&
      unavailableApplied.zoomUnavailable(MapStyle.AMAP_VECTOR, 3));
}

// ---- 定位不可用（未知态）：占位符 / 系统时区 / 逐时六格 / 未知态地图 ----
{
  check('gps intent without a fix is unknown', UnknownLocationLogic.isUnknown(true, false));
  check('a fix ends the unknown state', !UnknownLocationLogic.isUnknown(true, true));
  check('no gps intent is never unknown', !UnknownLocationLogic.isUnknown(false, false));

  // 点「实时跟随 GPS」：先落意图再看权限 —— 未授权也必须留下意图并立刻进入未知态。
  const deniedTap = UnknownLocationLogic.applyFollowTap(false, false);
  check('follow tap without permission still sets the intent', deniedTap.gpsIntent);
  check('follow tap without permission enters the unknown state', deniedTap.locationUnknown);
  const grantedNoFix = UnknownLocationLogic.applyFollowTap(true, false);
  check('follow tap with permission but no fix is still unknown',
    grantedNoFix.gpsIntent && grantedNoFix.locationUnknown);
  const grantedWithFix = UnknownLocationLogic.applyFollowTap(true, true);
  check('follow tap with permission and a fix is known',
    grantedWithFix.gpsIntent && !grantedWithFix.locationUnknown);

  // 未知态昼夜按系统时区钟点判：6 ≤ 小时 < 18 为白天。
  const dayAt = (hour: number, minute: number = 0): number =>
    Date.UTC(2026, 10, 16, hour, minute, 0);
  check('08:00 is daytime', UnknownLocationLogic.isDaytimeAt(dayAt(8), 0));
  check('17:59 is daytime', UnknownLocationLogic.isDaytimeAt(dayAt(17, 59), 0));
  check('18:00 is nighttime', !UnknownLocationLogic.isDaytimeAt(dayAt(18), 0));
  check('05:59 is nighttime', !UnknownLocationLogic.isDaytimeAt(dayAt(5, 59), 0));
  // 跨时区两个方向：UTC 23:00 在 +8 是次日 07:00（白天）；UTC 10:00 在 −5 是 05:00（夜间）。
  check('utc 23:00 at +8 is daytime', UnknownLocationLogic.isDaytimeAt(dayAt(23), 8 * 3600));
  check('utc 10:00 at -5 is nighttime', !UnknownLocationLogic.isDaytimeAt(dayAt(10), -5 * 3600));

  // 西半球偏移（UTC−5 = −18000）必须原样保留，不能拿负数当「没传」。
  const nowMillis: number = 1_700_000_000_000;
  equal('negative offsets survive', -18000, UnknownLocationLogic.offsetSecondsOr(-18000, nowMillis));
  equal('null offset falls back to the system zone',
    UnknownLocationLogic.systemOffsetSeconds(nowMillis), UnknownLocationLogic.offsetSecondsOr(null, nowMillis));
  equal('zero is a valid offset', 0, UnknownLocationLogic.offsetSecondsOr(0, nowMillis));

  check('time placeholder uses ascii only', LocationPlaceholders.isPlaceholderText(LocationPlaceholders.TIME));
  check('short placeholder uses ascii only', LocationPlaceholders.isPlaceholderText(LocationPlaceholders.SHORT));
  check('dash placeholder uses ascii only', LocationPlaceholders.isPlaceholderText(LocationPlaceholders.DASH));
  check('temperature placeholder uses ascii only',
    LocationPlaceholders.isPlaceholderText(LocationPlaceholders.TEMPERATURE));
  equal('time placeholder', '--:--:--', LocationPlaceholders.TIME);
  equal('short placeholder', '--', LocationPlaceholders.SHORT);
  equal('temperature placeholder', '-°', LocationPlaceholders.TEMPERATURE);
  check('em dash is rejected', !LocationPlaceholders.isPlaceholderText('——'));

  // 逐时六格：首格「现在」，其余按系统时间逐小时（跨午夜回绕），温度全 `-°`。
  const unknownLabels: string[] = UnknownLocationLogic.hourlyLabels(
    Date.UTC(2026, 10, 16, 13, 55) / 1000, 8 * 3600, 'zh-CN', 6);
  equal('unknown hourly labels', '现在,22时,23时,0时,1时,2时', unknownLabels.join(','));
  const unknownTemps: string[] = UnknownLocationLogic.hourlyTemperatures(6);
  equal('unknown hourly temp count', 6, unknownTemps.length);
  check('unknown hourly temps are all -°',
    unknownTemps.every((temp: string): boolean => temp === LocationPlaceholders.TEMPERATURE));

  // 未知态天气占位：不读任何缓存。
  const unknownWeather = UnknownLocationLogic.weatherPlaceholders();
  equal('unknown weather temperature is a dash', '--', unknownWeather.temperature);
  equal('unknown weather text is empty', '', unknownWeather.text);
  equal('unknown weather range is empty', '', unknownWeather.range);

  // 未知态圆盘：昼弧 180°、夜弧 180°。
  equal('unknown day arc starts at -180', -180, UnknownLocationLogic.dayArcStartDegrees());
  equal('unknown day arc sweeps 180', 180, UnknownLocationLogic.dayArcSweepDegrees());

  // 未知态地图：缓存命中零探测；无缓存按两块 z3 的结果定源；都失败 → 不可用。
  const emptyUnknownCache: UnknownMapCache | null = null;
  const cacheHit: UnknownMapCache = new UnknownMapCache();
  cacheHit.source = 'amap';
  cacheHit.millis = nowMillis;
  const cachedDecision: UnknownMapDecision = UnknownLocationLogic.decideMap(cacheHit, nowMillis, false, false, false);
  check('cached unknown map skips probing',
    cachedDecision.fromCache && cachedDecision.source === MapStyle.AMAP_VECTOR && cachedDecision.zoom === 3);
  const expired: UnknownMapCache = new UnknownMapCache();
  expired.source = 'osm';
  expired.millis = nowMillis - UnknownLocationLogic.CACHE_TTL_MILLIS - 1;
  check('expired unknown cache probes again',
    !UnknownLocationLogic.decideMap(expired, nowMillis, false, false, false).fromCache);
  equal('unknown map prefers esri when it answers', MapStyle.ESRI,
    UnknownLocationLogic.decideMap(emptyUnknownCache, nowMillis, true, true, true).source);
  equal('unknown map takes osm when esri is blank', MapStyle.OSM,
    UnknownLocationLogic.decideMap(emptyUnknownCache, nowMillis, false, true, true).source);
  equal('unknown map takes amap when both foreign sources fail', MapStyle.AMAP_VECTOR,
    UnknownLocationLogic.decideMap(emptyUnknownCache, nowMillis, false, false, true).source);
  check('unknown map is unavailable when all three probes fail',
    UnknownLocationLogic.decideMap(emptyUnknownCache, nowMillis, false, false, false).unavailable);
  check('unknown probe uses three z3 sources',
    UnknownLocationLogic.probeTile(MapStyle.ESRI).indexOf('server.arcgisonline.com') > 0 &&
      UnknownLocationLogic.probeTile(MapStyle.OSM).indexOf('/3/6/2') > 0 &&
      UnknownLocationLogic.probeTile(MapStyle.AMAP_VECTOR).indexOf('x=6') > 0);
}

// ---- 太阳卡圆盘几何（core/SunPath；逐条对齐 Android SunPathGeometryTest 的 18 项口径）----
{
  const width: number = 400;
  const height: number = 400;
  const radius: number = SunPathGeometry.RADIUS_RATIO * Math.min(width, height);
  const centerX: number = width / 2;
  const centerY: number = height / 2;

  // 1. 赤道春分：日出 06:00、日落 18:00 → 地平线过圆心。
  const equinox: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 12.0, false, false);
  near('equinox horizon through center', centerY, equinox.horizonY, 0.5);
  check('equinox is neither whole day nor whole night',
    !equinox.isWholeCircleDay() && !equinox.isWholeCircleNight());

  // 2. 上海夏至：昼长 14h → 地平线在圆心下方（≈ 0.263R）。
  const summer: SunPath = SunPathGeometry.compute(width, height, 4.99, 19.01, 12.0, false, false);
  check('midsummer horizon below center', summer.horizonY > centerY, `${summer.horizonY}`);
  near('midsummer horizon offset', centerY + radius * 0.263, summer.horizonY, 1.5);
  check('midsummer noon sun above horizon', summer.sunY < summer.horizonY);

  // 3. 中纬度冬至：昼长 < 12h → 地平线在圆心上方，正午太阳仍在地平线以上。
  const winter: SunPath = SunPathGeometry.compute(width, height, 7.01, 16.99, 12.0, false, false);
  check('midwinter horizon above center', winter.horizonY < centerY, `${winter.horizonY}`);
  check('midwinter noon sun above horizon', winter.sunY < winter.horizonY);

  // 4. 极昼：地平线沉到圆下方，整圆白天，半夜太阳也在地平线上；没有白天弧可切。
  const polarDay: SunPath = SunPathGeometry.compute(width, height, null, null, 0.5, true, false);
  check('polar day horizon below circle', polarDay.horizonY > centerY + radius, `${polarDay.horizonY}`);
  check('polar day whole circle is day', polarDay.isWholeCircleDay() && !polarDay.isWholeCircleNight());
  check('polar day midnight sun is up', polarDay.isSunUp());
  check('polar day has no day arc span', SunPathGeometry.dayArcSpan(null, null) === null);

  // 5. 极夜：地平线升到圆上方，整圆夜晚，正午太阳也在地平线以下；极夜没有上中天标签。
  const polarNight: SunPath = SunPathGeometry.compute(width, height, null, null, 12.0, false, true);
  check('polar night horizon above circle', polarNight.horizonY < centerY - radius, `${polarNight.horizonY}`);
  check('polar night whole circle is night',
    polarNight.isWholeCircleNight() && !polarNight.isWholeCircleDay());
  check('polar night noon sun is down', !polarNight.isSunUp());
  check('polar day keeps transit label', polarDay.hasTransitLabel());
  check('polar night drops transit label', !polarNight.hasTransitLabel());

  // 6. 12:00 圆顶、00:00 圆底、06:00 最左、18:00 最右；角度定义 θ(12)=0、θ(18)=+π/2、θ(6)=−π/2。
  const atNoon: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 12.0, false, false);
  near('12:00 sun x', centerX, atNoon.sunX, 0.5);
  near('12:00 sun y at top', centerY - radius, atNoon.sunY, 0.5);
  const atMidnight: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 0.0, false, false);
  near('00:00 sun x', centerX, atMidnight.sunX, 0.5);
  near('00:00 sun y at bottom', centerY + radius, atMidnight.sunY, 0.5);
  const atSix: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 6.0, false, false);
  near('06:00 sun x at left', centerX - radius, atSix.sunX, 0.5);
  near('06:00 sun y', centerY, atSix.sunY, 0.5);
  const atEighteen: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 18.0, false, false);
  near('18:00 sun x at right', centerX + radius, atEighteen.sunX, 0.5);
  near('18:00 sun y', centerY, atEighteen.sunY, 0.5);
  near('angle at 12:00', 0, SunPathGeometry.angleOfDayHour(12.0), 1e-9);
  near('angle at 18:00', Math.PI / 2, SunPathGeometry.angleOfDayHour(18.0), 1e-9);
  near('angle at 06:00', -Math.PI / 2, SunPathGeometry.angleOfDayHour(6.0), 1e-9);
  near('angle at 00:00', Math.PI, Math.abs(SunPathGeometry.angleOfDayHour(0.0)), 1e-9);

  // 6b. 南半球（−69.4°S 这类）：x 轴镜像 —— 06:00 在右、18:00 在左；12:00 仍在上、00:00 仍在下；
  //     地平线只由日出决定，南北半球同昼长时完全相同。
  const southSix: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 6.0, false, false, true);
  check('southern 06:00 x right of center', southSix.sunX > centerX, `${southSix.sunX}`);
  const southEighteen: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 18.0, false, false, true);
  check('southern 18:00 x left of center', southEighteen.sunX < centerX, `${southEighteen.sunX}`);
  const southNoon: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 12.0, false, false, true);
  near('southern 12:00 still at top', centerY - radius, southNoon.sunY, 0.5);
  const southMidnight: SunPath = SunPathGeometry.compute(width, height, 6.0, 18.0, 0.0, false, false, true);
  near('southern 00:00 still at bottom', centerY + radius, southMidnight.sunY, 0.5);
  check('southern flag propagated', southNoon.southernHemisphere && !equinox.southernHemisphere);
  near('southern horizon equals northern', equinox.horizonY, southNoon.horizonY, 0.001);
  // 白天弧：北半球从左（−180°）顺时针扫 180°，南半球从右（0°）逆时针扫 −180°；
  // 两端各外扩 0.8°，所以起点各挪 0.8°、扫角各多 1.6°。
  const southArc: SunArcSpan | null = SunPathGeometry.dayArcSpan(6.0, 18.0, true);
  check('southern day arc exists', southArc !== null);
  near('southern arc starts at +0.8 after extension', 0.8,
    southArc === null ? -999 : southArc.startDegrees, 1e-3);
  near('southern arc sweeps -181.6 after extension', -181.6,
    southArc === null ? -999 : southArc.sweepDegrees, 1e-3);

  // 6c. 运动方向箭头：圆内侧 0.72R 的 30° 短弧，北半球顺时针、南半球逆时针。
  const arrowNorth: MotionArrow = SunPathGeometry.motionArrow(equinox, 12.0);
  const arrowSouth: MotionArrow = SunPathGeometry.motionArrow(southNoon, 12.0);
  check('north motion arrow ends clockwise of start', arrowNorth.endX > arrowNorth.startX,
    `${arrowNorth.startX} -> ${arrowNorth.endX}`);
  check('south motion arrow ends counterclockwise of start', arrowSouth.endX < arrowSouth.startX,
    `${arrowSouth.startX} -> ${arrowSouth.endX}`);
  // 南半球 = 北半球关于竖轴（x = centerX）的镜像，且方向相反。
  near('south arrow start mirrors north start', 2 * centerX - arrowNorth.startX,
    arrowSouth.startX, 0.5);
  near('south arrow end mirrors north end', 2 * centerX - arrowNorth.endX, arrowSouth.endX, 0.5);
  near('south arrow start y matches north', arrowNorth.startY, arrowSouth.startY, 0.5);
  near('south arrow end y matches north', arrowNorth.endY, arrowSouth.endY, 0.5);
  const arrowRadiusNorth: number = Math.sqrt(
    Math.pow(arrowNorth.startX - centerX, 2) + Math.pow(arrowNorth.startY - centerY, 2));
  const arrowRadiusNorthEnd: number = Math.sqrt(
    Math.pow(arrowNorth.endX - centerX, 2) + Math.pow(arrowNorth.endY - centerY, 2));
  near('motion arrow start at 0.72R', equinox.radius * 0.72, arrowRadiusNorth, 0.5);
  near('motion arrow end at 0.72R', equinox.radius * 0.72, arrowRadiusNorthEnd, 0.5);
  const angleOfPoint = (x: number, y: number): number => Math.atan2(y - centerY, x - centerX);
  let arrowSpan: number = Math.abs(angleOfPoint(arrowNorth.endX, arrowNorth.endY) -
    angleOfPoint(arrowNorth.startX, arrowNorth.startY));
  if (arrowSpan > Math.PI) {
    arrowSpan = 2 * Math.PI - arrowSpan;
  }
  near('motion arrow spans 30 degrees', 30, arrowSpan * 180 / Math.PI, 0.1);
  let southArrowSpan: number = Math.abs(angleOfPoint(arrowSouth.endX, arrowSouth.endY) -
    angleOfPoint(arrowSouth.startX, arrowSouth.startY));
  if (southArrowSpan > Math.PI) {
    southArrowSpan = 2 * Math.PI - southArrowSpan;
  }
  near('southern motion arrow spans 30 degrees', 30, southArrowSpan * 180 / Math.PI, 0.1);
  check('motion arrow tip is the arc end',
    arrowNorth.tipX === arrowNorth.endX && arrowNorth.tipY === arrowNorth.endY);
  const tipToSun: number = Math.sqrt(
    Math.pow(arrowNorth.tipX - equinox.sunX, 2) + Math.pow(arrowNorth.tipY - equinox.sunY, 2));
  check('motion arrow clears the sun point', tipToSun > 6, `${tipToSun}`);
  const southTipToSun: number = Math.sqrt(
    Math.pow(arrowSouth.tipX - southNoon.sunX, 2) + Math.pow(arrowSouth.tipY - southNoon.sunY, 2));
  check('southern motion arrow clears the sun point', southTipToSun > 6, `${southTipToSun}`);

  // 7. 圆心在画布中央、半径 = 0.38 × min(w, h)，与宽高比无关。
  const sizes: number[][] = [[400, 300], [300, 400], [1080, 1080], [100, 800], [720, 1280]];
  let geometryOk: boolean = true;
  for (const size of sizes) {
    const p: SunPath = SunPathGeometry.compute(size[0], size[1], 6.0, 18.0, 12.0, false, false);
    if (Math.abs(p.centerX - size[0] / 2) > 0.5 || Math.abs(p.centerY - size[1] / 2) > 0.5 ||
      Math.abs(p.radius - 0.38 * Math.min(size[0], size[1])) > 0.5) {
      geometryOk = false;
    }
  }
  check('radius and center follow canvas size', geometryOk);

  // 8. 地平线弦端正好落在日出 / 日落刻度上。
  const chordPath: SunPath = SunPathGeometry.compute(width, height, 4.99, 19.01, 12.0, false, false);
  const halfChord: number = SunPathGeometry.horizonHalfChord(chordPath);
  check('horizon chord exists', halfChord > 0);
  near('chord left end = sunrise x',
    SunPathGeometry.hourX(chordPath.centerX, chordPath.radius, 4.99), chordPath.centerX - halfChord, 0.5);
  near('chord right end = sunset x',
    SunPathGeometry.hourX(chordPath.centerX, chordPath.radius, 19.01), chordPath.centerX + halfChord, 0.5);
  near('chord y = sunrise y',
    SunPathGeometry.hourY(chordPath.centerY, chordPath.radius, 4.99), chordPath.horizonY, 0.5);

  // 9. 白天弧扫角 = 昼长比例；跨 24:00 时补 2π；两端各外扩 0.8°（起点 -0.8°、扫角 +1.6°）。
  const twelveHourArc: SunArcSpan | null = SunPathGeometry.dayArcSpan(6.0, 18.0);
  check('twelve hour arc exists', twelveHourArc !== null);
  near('twelve hour arc starts 0.8 degrees early', -180.8,
    twelveHourArc === null ? -999 : twelveHourArc.startDegrees, 1e-3);
  near('twelve hour arc sweeps 181.6', 181.6,
    twelveHourArc === null ? -999 : twelveHourArc.sweepDegrees, 1e-3);
  const summerArc: SunArcSpan | null = SunPathGeometry.dayArcSpan(4.99, 19.01);
  near('summer arc sweep includes the extension', 14.02 / 24 * 360 + 1.6,
    summerArc === null ? -999 : summerArc.sweepDegrees, 0.1);
  const wrappedArc: SunArcSpan | null = SunPathGeometry.dayArcSpan(3.0, 0.5);
  near('wrapped arc sweep includes the extension', 21.5 / 24 * 360 + 1.6,
    wrappedArc === null ? -999 : wrappedArc.sweepDegrees, 0.1);
  // 昼长接近 24 小时：扫角封顶 360°，留给夜晚的扫角 ≥ 0。
  const nearlyWholeArc: SunArcSpan | null = SunPathGeometry.dayArcSpan(0.0, 23.999);
  const nearlySweep: number = nearlyWholeArc === null ? -999 : Math.abs(nearlyWholeArc.sweepDegrees);
  check('near polar day arc is capped at 360', nearlySweep <= 360 + 1e-6, `${nearlySweep}`);
  check('night sweep stays non-negative', 360 - nearlySweep >= -1e-6, `${360 - nearlySweep}`);
  check('arc extension constant is 0.8 degrees', SunPathGeometry.ARC_END_EXTENSION_DEGREES === 0.8);

  // ---- 标签锚点：画布比例取卡片真实值 294×194，间距按 UI 的 dp（1dp = 1 单位）----
  const dialWidth: number = 294;
  const dialHeight: number = 194;
  const sideGap: number = 10;
  const noonGap: number = 8;
  const labelDrop: number = 18;
  const labelRise: number = 10;
  const sideInset: number = 8;
  const labelWidth: number = 30;
  const labelHeight: number = 16;
  const dial = (sunriseHour: number | null, sunsetHour: number | null, trueSolarHour: number = 12,
    isPolarDay: boolean = false, isPolarNight: boolean = false): SunPath =>
    SunPathGeometry.compute(dialWidth, dialHeight, sunriseHour, sunsetHour, trueSolarHour,
      isPolarDay, isPolarNight);
  const anchors = (path: SunPath, sunriseHour: number | null, sunsetHour: number | null): SunLabelAnchors =>
    SunPathGeometry.labelAnchors(path, sunriseHour, sunsetHour, sideGap, noonGap, labelDrop, labelRise);
  const boundaryAt = (path: SunPath, y: number): number[] => {
    const dy: number = y - path.centerY;
    const half: number = Math.sqrt(Math.max(0, path.radius * path.radius - dy * dy));
    return [path.centerX - half, path.centerX + half];
  };

  // 10. 赤道春分：标签在交点外侧、抬高 labelRise；上中天在圆顶上方；文案锚在圆心。
  const equinoxPath: SunPath = dial(6.0, 18.0);
  const equinoxAnchors: SunLabelAnchors = anchors(equinoxPath, 6.0, 18.0);
  near('equinox sunrise label y', equinoxPath.centerY - labelRise, equinoxAnchors.sunriseY, 0.5);
  near('equinox sunset label y', equinoxPath.centerY - labelRise, equinoxAnchors.sunsetY, 0.5);
  const equinoxBounds: number[] = boundaryAt(equinoxPath, equinoxAnchors.sunriseY);
  near('equinox sunrise label outside left', equinoxBounds[0] - sideGap, equinoxAnchors.sunriseX, 0.5);
  near('equinox sunset label outside right', equinoxBounds[1] + sideGap, equinoxAnchors.sunsetX, 0.5);
  near('noon label x', equinoxPath.centerX, equinoxAnchors.noonX, 0.5);
  near('noon label y above top', equinoxPath.centerY - equinoxPath.radius - noonGap,
    equinoxAnchors.noonY, 0.5);
  near('polar label x at center', equinoxPath.centerX, equinoxAnchors.polarX, 0.5);
  near('polar label y at center', equinoxPath.centerY, equinoxAnchors.polarY, 0.5);
  check('equinox labels clear of horizon',
    equinoxAnchors.sunriseY + labelHeight / 2 <= equinoxPath.horizonY - 1);

  // 10b. 南半球标签：日出换到右边、日落换到左边；上中天仍在圆顶。
  const southPath: SunPath = SunPathGeometry.compute(dialWidth, dialHeight, 6.0, 18.0, 12.0,
    false, false, true);
  const southAnchors: SunLabelAnchors = anchors(southPath, 6.0, 18.0);
  check('southern sunrise label on the right', southAnchors.sunriseX > southPath.centerX,
    `${southAnchors.sunriseX}`);
  check('southern sunset label on the left', southAnchors.sunsetX < southPath.centerX,
    `${southAnchors.sunsetX}`);
  const southSunrisePointX: number = SunPathGeometry.hourX(southPath.centerX, southPath.radius, 6.0, true);
  const southSunsetPointX: number = SunPathGeometry.hourX(southPath.centerX, southPath.radius, 18.0, true);
  check('southern sunrise label sits at the right intersection',
    Math.abs(southAnchors.sunriseX - southSunrisePointX) < 1e-6);
  check('southern sunset label sits at the left intersection',
    Math.abs(southAnchors.sunsetX - southSunsetPointX) < 1e-6);
  near('southern noon label still above top', southPath.centerY - southPath.radius - noonGap,
    southAnchors.noonY, 0.5);

  // 11. 上海夏至：地平线下移，标签跟着下去（仍比地平线高 labelRise）。
  const summerPath: SunPath = dial(4.99, 19.01);
  const summerAnchors: SunLabelAnchors = anchors(summerPath, 4.99, 19.01);
  check('summer sunrise label below center', summerAnchors.sunriseY > summerPath.centerY,
    `${summerAnchors.sunriseY}`);
  near('summer sunrise label clears horizon', summerPath.horizonY - labelRise,
    summerAnchors.sunriseY, 0.5);
  near('summer sunset label clears horizon', summerPath.horizonY - labelRise,
    summerAnchors.sunsetY, 0.5);
  check('summer labels clear of horizon',
    summerAnchors.sunriseY + labelHeight / 2 <= summerPath.horizonY - 1);

  // 12. 极昼：保留上中天；没有交点时日出/日落锚点退到圆的最左/最右。
  const polarDayPath: SunPath = dial(null, null, 12, true, false);
  const polarDayAnchors: SunLabelAnchors = anchors(polarDayPath, null, null);
  check('polar day transit label', polarDayPath.hasTransitLabel());
  near('polar day sunrise anchor left', polarDayPath.centerX - polarDayPath.radius - sideGap,
    polarDayAnchors.sunriseX, 0.5);
  near('polar day sunrise anchor y', polarDayPath.centerY, polarDayAnchors.sunriseY, 0.5);
  near('polar day sunset anchor right', polarDayPath.centerX + polarDayPath.radius + sideGap,
    polarDayAnchors.sunsetX, 0.5);
  near('polar day noon label y', polarDayPath.centerY - polarDayPath.radius - noonGap,
    polarDayAnchors.noonY, 0.5);

  // 13. 极夜：没有上中天，只留圆心那行「极夜」。
  const polarNightPath: SunPath = dial(null, null, 12, false, true);
  const polarNightAnchors: SunLabelAnchors = anchors(polarNightPath, null, null);
  check('polar night no transit label', !polarNightPath.hasTransitLabel());
  near('polar night label x', polarNightPath.centerX, polarNightAnchors.polarX, 0.5);
  near('polar night label y', polarNightPath.centerY, polarNightAnchors.polarY, 0.5);

  // 14. 日出 0:00（日落 24:00）：地平线与圆相切于最下方，两个标签贴在底点两侧。
  const tangentPath: SunPath = dial(0.0, 24.0, 0.0);
  const tangentAnchors: SunLabelAnchors = anchors(tangentPath, 0.0, 24.0);
  near('tangent horizon at bottom', tangentPath.centerY + tangentPath.radius, tangentPath.horizonY, 0.5);
  check('tangent whole circle is day', tangentPath.isWholeCircleDay());
  near('tangent chord degenerates', 0, SunPathGeometry.horizonHalfChord(tangentPath), 0.5);
  near('tangent sunrise label y', tangentPath.centerY + tangentPath.radius - labelRise,
    tangentAnchors.sunriseY, 0.5);
  near('tangent sunset label y', tangentPath.centerY + tangentPath.radius - labelRise,
    tangentAnchors.sunsetY, 0.5);
  const tangentBounds: number[] = boundaryAt(tangentPath, tangentAnchors.sunriseY);
  near('tangent sunrise label outside bottom-left', tangentBounds[0] - sideGap,
    tangentAnchors.sunriseX, 0.5);
  near('tangent sunset label outside bottom-right', tangentBounds[1] + sideGap,
    tangentAnchors.sunsetX, 0.5);
  check('tangent sunrise label in left half',
    tangentAnchors.sunriseX < tangentPath.centerX - tangentPath.radius * 0.3);
  check('tangent sunset label in right half',
    tangentAnchors.sunsetX > tangentPath.centerX + tangentPath.radius * 0.3);
  const tangentDistance: number = Math.sqrt(
    Math.pow(tangentAnchors.sunriseX - tangentPath.centerX, 2) +
    Math.pow(tangentAnchors.sunriseY - tangentPath.bottomY(), 2));
  check('tangent label near bottom point', tangentDistance <= tangentPath.radius * 0.7,
    `${tangentDistance}`);

  // 15. 高纬度昼长 1 小时：两交点只隔约 15°，标签分列左右交点外侧、彼此不重叠。
  const shortPath: SunPath = dial(11.5, 12.5);
  const shortAnchors: SunLabelAnchors = anchors(shortPath, 11.5, 12.5);
  const leftIntersectionX: number = SunPathGeometry.hourX(shortPath.centerX, shortPath.radius, 11.5);
  const rightIntersectionX: number = SunPathGeometry.hourX(shortPath.centerX, shortPath.radius, 12.5);
  check('short day left intersection left of center', leftIntersectionX < shortPath.centerX);
  check('short day right intersection right of center', rightIntersectionX > shortPath.centerX);
  check('short day sunrise label left of left intersection',
    shortAnchors.sunriseX < leftIntersectionX, `${shortAnchors.sunriseX} vs ${leftIntersectionX}`);
  check('short day sunset label right of right intersection',
    shortAnchors.sunsetX > rightIntersectionX, `${shortAnchors.sunsetX} vs ${rightIntersectionX}`);
  check('short day labels apart', shortAnchors.sunsetX - shortAnchors.sunriseX > sideGap * 2);
  near('short day label drops below top', shortPath.centerY - shortPath.radius + labelDrop,
    shortAnchors.sunriseY, 0.5);
  const shortHalfAtLabel: number = Math.sqrt(Math.max(0, shortPath.radius * shortPath.radius -
    Math.pow(shortAnchors.sunriseY - shortPath.centerY, 2)));
  near('short day label outside circle', shortPath.centerX - shortHalfAtLabel - sideGap,
    shortAnchors.sunriseX, 0.5);
  check('short day label below noon label',
    shortAnchors.sunriseY - labelHeight / 2 >= shortAnchors.noonY - labelHeight);

  // 16. 五个场景（含极昼/极夜）的标签都不越出 280×194 的小卡片（左右各留 ≥8）。
  const smallWidth: number = 280;
  const smallCases: number[][] = [[6.0, 18.0], [4.99, 19.01], [11.5, 12.5], [0.0, 24.0]];
  let labelsInside: boolean = true;
  for (const one of smallCases) {
    const p: SunPath = SunPathGeometry.compute(smallWidth, dialHeight, one[0], one[1], 12, false, false);
    const a: SunLabelAnchors = SunPathGeometry.labelAnchors(p, one[0], one[1], sideGap, noonGap,
      labelDrop, labelRise);
    if (a.sunriseX - labelWidth < sideInset || a.sunsetX + labelWidth > smallWidth - sideInset ||
      a.noonX - labelWidth / 2 < sideInset || a.noonX + labelWidth / 2 > smallWidth - sideInset ||
      a.noonY - labelHeight < -1 || a.sunriseY + labelHeight / 2 > dialHeight + 1 ||
      a.sunsetY + labelHeight / 2 > dialHeight + 1) {
      labelsInside = false;
    }
  }
  for (const polar of [[true, false], [false, true]]) {
    const p: SunPath = SunPathGeometry.compute(smallWidth, dialHeight, null, null, 12, polar[0], polar[1]);
    const a: SunLabelAnchors = SunPathGeometry.labelAnchors(p, null, null, sideGap, noonGap,
      labelDrop, labelRise);
    if (a.polarX - labelWidth / 2 < sideInset || a.polarX + labelWidth / 2 > smallWidth - sideInset ||
      a.polarY - labelHeight / 2 < 0 || a.polarY + labelHeight / 2 > dialHeight) {
      labelsInside = false;
    }
    if (polar[0] && a.noonX - labelWidth / 2 < sideInset) {
      labelsInside = false;
    }
  }
  check('dial labels stay inside the canvas', labelsInside);

  // 17. 地平线：固定为画布左右各内缩 4（vp），普通日/短昼/冬至/极昼/极夜/相切长度完全相同。
  const horizonInset: number = 4;
  const expectedHorizonLength: number = dialWidth - horizonInset * 2;
  const horizonScenarios: number[][] = [[6.0, 18.0], [4.99, 19.01], [7.01, 16.99], [11.5, 12.5], [0.0, 24.0]];
  const horizonLengths: number[] = [];
  let horizonOk: boolean = true;
  for (const one of horizonScenarios) {
    const p: SunPath = dial(one[0], one[1]);
    if (p.radius <= 0) {
      horizonOk = false;
    }
    const s: HorizonSpan = SunPathGeometry.horizonSpan(dialWidth, horizonInset);
    horizonLengths.push(s.length());
    if (Math.abs(s.startX - horizonInset) > 0.5 ||
      Math.abs(s.endX - (dialWidth - horizonInset)) > 0.5 ||
      Math.abs(s.length() - expectedHorizonLength) > 0.5) {
      horizonOk = false;
    }
  }
  for (const polar of [[true, false], [false, true]]) {
    const p: SunPath = dial(null, null, 12, polar[0], polar[1]);
    if (p.radius <= 0) {
      horizonOk = false;
    }
    const s: HorizonSpan = SunPathGeometry.horizonSpan(dialWidth, horizonInset);
    horizonLengths.push(s.length());
    if (Math.abs(s.startX - horizonInset) > 0.5 ||
      Math.abs(s.endX - (dialWidth - horizonInset)) > 0.5 ||
      Math.abs(s.length() - expectedHorizonLength) > 0.5) {
      horizonOk = false;
    }
  }
  check('horizon starts/ends at canvas inset', horizonOk, `${horizonLengths.join(',')}`);
  check('horizon length identical across all scenarios',
    Math.max(...horizonLengths) - Math.min(...horizonLengths) < 0.001);
  near('horizon fixed length', dialWidth - horizonInset * 2, horizonLengths[0], 0.5);

  const narrowSpan: HorizonSpan = SunPathGeometry.horizonSpan(160, horizonInset);
  near('narrow horizon starts at inset', horizonInset, narrowSpan.startX, 0.5);
  near('narrow horizon ends at width - inset', 160 - horizonInset, narrowSpan.endX, 0.5);
}

// ---- 太阳卡：轨迹线宽 / 太阳点（= 时间轴圆点）逐项一致 / 配色对比 ----
{
  equal('day arc uses the android gold', '#EAD095', SunDialColors.DAY_ARC);
  equal('day sun dot uses the android gold', '#D9AC1C', SunDialColors.DAY_SUN_DOT);
  const arcContrast: number = SunDialColors.contrastRatio(
    SunDialColors.DAY_ARC, SunDialColors.DAY_CARD);
  check('day arc contrast stays in the 1.4-1.5 band',
    arcContrast >= 1.4 && arcContrast <= 1.55, `${arcContrast}`);
  const coreOnCard: number = SunDialColors.contrastRatio(
    SunDialColors.DAY_SUN_DOT, SunDialColors.DAY_CARD);
  check('sun dot core contrast is at least 2.0', coreOnCard >= 2.0, `${coreOnCard}`);
  const warmthGap: number = SunDialColors.warmth(SunDialColors.DAY_ARC) -
    SunDialColors.warmth(SunDialColors.NIGHT_DASH);
  check('day arc differs from the night dash in hue', warmthGap >= 0.15, `${warmthGap}`);
  const dotContrast: number = SunDialColors.contrastRatio(
    SunDialColors.DAY_SUN_DOT, SunDialColors.DAY_ARC);
  check('sun dot separates from the day arc', dotContrast >= 1.3, `${dotContrast}`);
  check('sun dot is clearly apart from the arc in rgb',
    SunDialColors.rgbDistance(SunDialColors.DAY_SUN_DOT, SunDialColors.DAY_ARC) >= 100,
    `${SunDialColors.rgbDistance(SunDialColors.DAY_SUN_DOT, SunDialColors.DAY_ARC)}`);

  // 轨迹线宽：白天 1.6、夜晚 1.5（虚线 4/4）；极昼/极夜整圆沿用同一组宽度。
  equal('day arc is a thin 1.6vp line', 1.6, SunDialColors.DAY_ARC_WIDTH);
  equal('night arc is a thin 1.5vp line', 1.5, SunDialColors.NIGHT_ARC_WIDTH);
  equal('night dash shrinks to 4vp', 4, SunDialColors.NIGHT_DASH_LENGTH);
  check('arc lines are thinner than before', SunDialColors.DAY_ARC_WIDTH < 2.5
    && SunDialColors.NIGHT_ARC_WIDTH < 2.5 && SunDialColors.DAY_ARC_WIDTH > SunDialColors.NIGHT_ARC_WIDTH);

  // 时间轴圆点：原样保留（以后不要再动）—— 0 / 0.45 / 1、alpha 1 / 0.45 / 0。
  near('timeline dot radius is 5.5vp', 5.5, SunDialColors.DOT_RADIUS, 0.001);
  equal('timeline dot colour stops are unchanged', '0,0.45,1',
    SunDialColors.DOT_STOPS.join(','));
  equal('timeline dot alpha stops are unchanged', '1,0.45,0',
    SunDialColors.DOT_ALPHAS.join(','));
  equal('timeline gradient colours follow its alpha stops', '#FFD9A520,#73D9A520,#00D9A520',
    SunDialColors.dotGradientColors('#D9A520').join(','));

  // 太阳点：纯色核心 2.5vp + 独立光晕（2.5 → 5.5vp，0.35 → 0），核心 alpha 1。
  near('sun dot core radius', 2.5, SunDialColors.SUN_DOT_CORE_RADIUS, 0.001);
  near('sun dot glow outer radius', 5.5, SunDialColors.SUN_DOT_GLOW_RADIUS, 0.001);
  near('sun dot glow starts at the core radius', SunDialColors.SUN_DOT_CORE_RADIUS,
    SunDialColors.SUN_DOT_GLOW_START_RADIUS, 0.001);
  equal('sun dot core is fully opaque', 1, SunDialColors.SUN_DOT_CORE_ALPHA);
  equal('sun dot glow starts at 0.35 alpha', 0.35, SunDialColors.SUN_DOT_GLOW_ALPHA);
  check('sun dot core radius equals timeline radius x 0.45',
    Math.abs(SunDialColors.SUN_DOT_CORE_RADIUS - SunDialColors.DOT_RADIUS * 0.45) <= 0.05,
    `${SunDialColors.SUN_DOT_CORE_RADIUS}`);
  equal('sun dot core is gold by day', '#D9AC1C', SunDialColors.DAY_SUN_DOT);
  equal('sun dot core is gold by night', '#F5D68A', SunDialColors.NIGHT_SUN_DOT);
  equal('sun glow colours fade from 0.35 to 0', '#59D9AC1C,#00D9AC1C',
    SunDialColors.sunGlowColors(SunDialColors.DAY_SUN_DOT).join(','));
  equal('night sun glow stays gold', '#59F5D68A,#00F5D68A',
    SunDialColors.sunGlowColors(SunDialColors.NIGHT_SUN_DOT).join(','));
  equal('night arc stays gold', '#F5D68A', SunDialColors.NIGHT_ARC);
}

// ---- 预设城市「南极中山站」的显示名（中文 / 英文两列）----
{
  const zhongshanZh = CityIndex.nearest(-69.37, 76.38, 'zh-Hans');
  const zhongshanEn = CityIndex.nearest(-69.37, 76.38, 'en-US');
  check('zhongshan station keeps the new chinese name',
    zhongshanZh !== null && zhongshanZh.name === '南极中山站',
    `${zhongshanZh === null ? 'null' : zhongshanZh.name}`);
  check('zhongshan station keeps the new english name',
    zhongshanEn !== null && zhongshanEn.name === 'Zhongshan Station, Antarctica',
    `${zhongshanEn === null ? 'null' : zhongshanEn.name}`);
}

// ---- 夜间弧必须与白天弧互补，不能把整圈重画一遍 ----
{
  const daySweep: number = 181.6;
  const nightSweep: number = SunPathGeometry.nightSweepDegrees(daySweep);
  near('night arc length is 360 minus the day arc', 178.4, nightSweep, 1e-6);
  near('day plus night fills the circle', 360, Math.abs(daySweep) + nightSweep, 1e-6);
  near('southern night arc has the same length', 178.4,
    SunPathGeometry.nightSweepDegrees(-daySweep), 1e-6);
  equal('polar day has no night arc', 0, SunPathGeometry.nightSweepDegrees(360));
  equal('polar night is a full circle of night', 360, SunPathGeometry.nightSweepDegrees(0));
  equal('northern night ends at start plus 360', 360, SunPathGeometry.nightEndDegrees(0, false));
  equal('southern night ends at start minus 360', -360, SunPathGeometry.nightEndDegrees(0, true));
  const start: number = -180.8;
  const nightStart: number = start + daySweep;
  near('night arc really starts at the sunset point', 0.8, nightStart, 1e-6);
  near('night arc ends at the sunrise point after a full turn', 179.2,
    SunPathGeometry.nightEndDegrees(start, false), 1e-6);
  near('night arc span from those endpoints', 178.4,
    SunPathGeometry.nightEndDegrees(start, false) - nightStart, 1e-6);
}

// ---- 大卡片顶部四档退化：地名优先保完整 ----
{
  const base: number = 12;
  const utc: number = 5 * base;
  const label: number = 4 * base;
  const shichen: number = 2 * base;
  equal('short district stays at tier 0', DistrictLayoutTier.FULL,
    DistrictLayoutTier.of(utc, 6 * base, label, shichen, 300));
  // 「新疆维吾尔自治区乌鲁木齐市水磨沟区」约 17 个汉字（12fp 时放不下档 0，9fp 时仍放不下档 1 的 17×9）。
  equal('long district drops the label', DistrictLayoutTier.HIDE_LABEL,
    DistrictLayoutTier.of(utc, 17 * base, label, shichen, 300));
  // 缩到 9fp 仍不够：再隐藏 UTC。
  equal('extreme district also drops the utc label', DistrictLayoutTier.HIDE_UTC,
    DistrictLayoutTier.of(utc, 40 * 9, 9, shichen, 400));
  // 更长：只能省略号。
  equal('even longer district needs ellipsis', DistrictLayoutTier.ELLIPSIS,
    DistrictLayoutTier.of(utc, 60 * 9, 9, shichen, 400));
  equal('long english district drops the label', DistrictLayoutTier.HIDE_LABEL,
    DistrictLayoutTier.of(utc, 22 * base, label, shichen, 380));
}

// ---- 近极昼标签退让：三个标签矩形两两不相交 ----
{
  const polarPath: SunPath = SunPathGeometry.compute(294, 194, 1.5, 22.5, 12, false, false, true);
  const polarAnchors: SunLabelAnchors = SunPathGeometry.labelAnchors(polarPath, 1.5, 22.5,
    10, 8, 18, 10, 11, 4, 5);
  const labelWidth: number = 5 * 11 * 0.6 + 4;
  const labelHeight: number = 11 * 1.2 + 4;
  const sunriseRect: number[] = SunPathGeometry.rectOf(polarAnchors.sunriseX, polarAnchors.sunriseY,
    labelWidth, labelHeight, false);
  const sunsetRect: number[] = SunPathGeometry.rectOf(polarAnchors.sunsetX, polarAnchors.sunsetY,
    labelWidth, labelHeight, true);
  const noonRect: number[] = SunPathGeometry.rectOf(polarAnchors.noonX, polarAnchors.noonY,
    labelWidth, labelHeight, false, true);
  check('near polar sunrise and sunset labels do not overlap',
    !SunPathGeometry.rectsOverlap(sunriseRect, sunsetRect));
  check('near polar sunrise and noon labels do not overlap',
    !SunPathGeometry.rectsOverlap(sunriseRect, noonRect));
  check('near polar sunset and noon labels do not overlap',
    !SunPathGeometry.rectsOverlap(sunsetRect, noonRect));
  // 南半球镜像：日出在右、日落在左。
  check('near polar southern sunrise stays on the right',
    polarPath.southernHemisphere && polarAnchors.sunriseX > polarPath.centerX);
  check('near polar southern sunset stays on the left',
    polarAnchors.sunsetX < polarPath.centerX);
  // 极昼/极夜没有日出日落标签（小时为 null，视图不渲染两侧标签）。
  const wholeDay: SunPath = SunPathGeometry.compute(294, 194, null, null, 12, true, false, true);
  const wholeDayAnchors: SunLabelAnchors = SunPathGeometry.labelAnchors(wholeDay, null, null,
    10, 8, 18, 10, 11, 4, 5);
  check('polar day anchors keep null side hours',
    SunPathGeometry.dayArcSpan(null, null) === null && wholeDayAnchors.sunriseX >= 0);
}

// ---- 南半球标签放到地平线下方；北半球保持原样 ----
{
  const labelWidth: number = 5 * 11 * 0.6 + 4;
  const labelHeight: number = 11 * 1.2 + 4;
  // 悉尼（正常昼长）：两个标签都在地平线下，左/右分列。
  const sydney: SunPath = SunPathGeometry.compute(294, 194, 6.0, 18.0, 12, false, false, true);
  const sydneyAnchors: SunLabelAnchors = SunPathGeometry.labelAnchors(sydney, 6, 18, 10, 8, 18, 10);
  check('sydney labels sit below the horizon',
    sydneyAnchors.sunriseY > sydney.horizonY && sydneyAnchors.sunsetY > sydney.horizonY);
  check('sydney sunrise stays right, sunset stays left',
    sydneyAnchors.sunriseX > sydney.centerX && sydneyAnchors.sunsetX < sydney.centerX);
  const sydneyChord: number = SunPathGeometry.horizonHalfChord(sydney);
  near('sydney sunrise sits on its intersection', sydney.centerX + sydneyChord,
    sydneyAnchors.sunriseX, 1e-9);
  near('sydney sunset sits on its intersection', sydney.centerX - sydneyChord,
    sydneyAnchors.sunsetX, 1e-9);
  check('sydney side labels do not overlap',
    !SunPathGeometry.rectsOverlap(
      SunPathGeometry.rectOf(sydneyAnchors.sunriseX, sydneyAnchors.sunriseY, labelWidth, labelHeight, false),
      SunPathGeometry.rectOf(sydneyAnchors.sunsetX, sydneyAnchors.sunsetY, labelWidth, labelHeight, true)));

  // 南极中山站（22.7h / 00:21 / 23:39，近极昼）：以交点为基准，仅最小推开。
  const zhongshan: SunPath = SunPathGeometry.compute(294, 194, 0.35, 23.65, 12, false, false, true);
  const zhongshanAnchors: SunLabelAnchors = SunPathGeometry.labelAnchors(zhongshan, 0.35, 23.65,
    10, 8, 18, 10);
  const zhongshanChord: number = SunPathGeometry.horizonHalfChord(zhongshan);
  const sunrisePoint: number = zhongshan.centerX + zhongshanChord;
  const sunsetPoint: number = zhongshan.centerX - zhongshanChord;
  check('zhongshan labels sit below the horizon',
    zhongshanAnchors.sunriseY > zhongshan.horizonY &&
      zhongshanAnchors.sunsetY > zhongshan.horizonY);
  check('zhongshan sunrise stays within 40% of the card',
    Math.abs(zhongshanAnchors.sunriseX - sunrisePoint) <= 294 * 0.4);
  check('zhongshan sunset stays within 40% of the card',
    Math.abs(zhongshanAnchors.sunsetX - sunsetPoint) <= 294 * 0.4);
  const zhongshanRects: number[][] = [
    SunPathGeometry.rectOf(zhongshanAnchors.sunriseX, zhongshanAnchors.sunriseY, labelWidth,
      labelHeight, false),
    SunPathGeometry.rectOf(zhongshanAnchors.sunsetX, zhongshanAnchors.sunsetY, labelWidth,
      labelHeight, true),
    SunPathGeometry.rectOf(zhongshanAnchors.noonX, zhongshanAnchors.noonY, labelWidth,
      labelHeight, false, true)
  ];
  check('zhongshan three labels are pairwise disjoint',
    !SunPathGeometry.rectsOverlap(zhongshanRects[0], zhongshanRects[1]) &&
      !SunPathGeometry.rectsOverlap(zhongshanRects[0], zhongshanRects[2]) &&
      !SunPathGeometry.rectsOverlap(zhongshanRects[1], zhongshanRects[2]));

  // 极端极昼：日出=日落=同一个点，允许退到边缘，但间距仍 ≥ 60% 卡片宽。
  const samePoint: SunPath = SunPathGeometry.compute(294, 194, 12, 12, 12, false, false, true);
  const samePointAnchors: SunLabelAnchors = SunPathGeometry.labelAnchors(samePoint, 12, 12, 10, 8, 18, 10);
  check('same point labels still sit below the horizon',
    samePointAnchors.sunriseY > samePoint.horizonY &&
      samePointAnchors.sunsetY > samePoint.horizonY);
  check('same point labels fall back to the edges with 60% spacing',
    Math.abs(samePointAnchors.sunriseX - samePointAnchors.sunsetX) >= 294 * 0.6);

  // 北京（北半球）：锚点与现状完全一致，仍在地平线上方。
  const beijing: SunPath = SunPathGeometry.compute(294, 194, 6.4, 16.9, 12, false, false, false);
  const beijingAnchors: SunLabelAnchors = SunPathGeometry.labelAnchors(beijing, 6.4, 16.9,
    10, 8, 18, 10);
  near('beijing sunrise x unchanged', 65.43784736562158, beijingAnchors.sunriseX, 1e-9);
  near('beijing sunrise y unchanged', 79.29416168790857, beijingAnchors.sunriseY, 1e-9);
  near('beijing sunset x unchanged', 223.9141435910342, beijingAnchors.sunsetX, 1e-9);
  near('beijing sunset y unchanged', 66.0623887884268, beijingAnchors.sunsetY, 1e-9);
  near('beijing noon y unchanged', 15.280000000000001, beijingAnchors.noonY, 1e-9);
  check('beijing labels stay above the horizon',
    beijingAnchors.sunriseY < beijing.horizonY && beijingAnchors.sunsetY < beijing.horizonY);
}

// ---- 标签文案「说明 + 时间」与新宽度下的三场景布局 ----
{
  equal('dial sunrise label (zh)', '日出 06:24', DialLabels.sunrise('zh-CN', '06:24'));
  equal('dial sunset label (zh)', '日落 16:54', DialLabels.sunset('zh-CN', '16:54'));
  equal('dial noon label (zh)', '上中天 11:39', DialLabels.noon('zh-CN', '11:39'));
  equal('dial sunrise label (en)', 'Sunrise 06:24', DialLabels.sunrise('en-US', '06:24'));
  equal('dial noon label (en)', 'Solar noon 11:39', DialLabels.noon('en-US', '11:39'));
  equal('dial polar label (zh)', '极昼', DialLabels.polar(true, 'zh-CN'));
  equal('dial polar label (en)', 'Polar night', DialLabels.polar(false, 'en-US'));

  const size: number = 11;
  const padding: number = 4;
  const zhTexts: string[] = ['日出 06:24', '日落 16:54', '上中天 11:39'];
  const sunriseWidth: number = SunPathGeometry.estimateLabelWidth(zhTexts[0], size, padding);
  const sunsetWidth: number = SunPathGeometry.estimateLabelWidth(zhTexts[1], size, padding);
  const noonWidth: number = SunPathGeometry.estimateLabelWidth(zhTexts[2], size, padding);
  check('new label is wider than the old 5-char estimate', sunriseWidth > 5 * size * 0.6 + padding);
  check('solar noon label is the widest', noonWidth > sunriseWidth && noonWidth > sunsetWidth);
  const h: number = size * 1.2 + padding;

  const layoutOf = (path: SunPath, a: number | null, b: number | null): number[][] => {
    const anchors: SunLabelAnchors = SunPathGeometry.labelAnchors(path, a, b, 10, 8, 18, 10,
      size, padding, 5, zhTexts);
    return [
      SunPathGeometry.rectOf(anchors.sunriseX, anchors.sunriseY, sunriseWidth, h, !path.southernHemisphere),
      SunPathGeometry.rectOf(anchors.sunsetX, anchors.sunsetY, sunsetWidth, h, path.southernHemisphere),
      SunPathGeometry.rectOf(anchors.noonX, anchors.noonY, noonWidth, h, false, true)
    ];
  };
  const noOverlap = (rects: number[][]): boolean =>
    !SunPathGeometry.rectsOverlap(rects[0], rects[1]) &&
      !SunPathGeometry.rectsOverlap(rects[0], rects[2]) &&
      !SunPathGeometry.rectsOverlap(rects[1], rects[2]);
  const inside = (rects: number[][]): boolean => rects.every((r: number[]): boolean =>
    r[0] >= -0.01 && r[2] <= 294.01 && r[1] >= -0.01 && r[3] <= 194.01);

  const beijingScene: SunPath = SunPathGeometry.compute(294, 194, 6.4, 16.9, 12, false, false, false);
  check('beijing three labels disjoint with descriptions', noOverlap(layoutOf(beijingScene, 6.4, 16.9)));
  check('beijing three labels stay inside the canvas', inside(layoutOf(beijingScene, 6.4, 16.9)));
  const sydneyScene: SunPath = SunPathGeometry.compute(294, 194, 6.0, 18.0, 12, false, false, true);
  check('sydney three labels disjoint with descriptions', noOverlap(layoutOf(sydneyScene, 6, 18)));
  check('sydney three labels stay inside the canvas', inside(layoutOf(sydneyScene, 6, 18)));
  const zhongshanScene: SunPath = SunPathGeometry.compute(294, 194, 0.35, 23.65, 12, false, false, true);
  check('zhongshan three labels disjoint with descriptions', noOverlap(layoutOf(zhongshanScene, 0.35, 23.65)));
  check('zhongshan three labels stay inside the canvas', inside(layoutOf(zhongshanScene, 0.35, 23.65)));
}

// ---- 顶部标签行：左右两半的四档 ----
{
  const utc: number = 36;
  const place: number = 72;
  const label: number = 48;
  const shichen: number = 24;
  equal('halves tier 0 when both halves fit', DistrictLayoutTier.FULL,
    DistrictLayoutTier.ofHalves(utc, place, label, shichen, 160));
  equal('halves tier 1 when only the right half is crowded', DistrictLayoutTier.HIDE_LABEL,
    DistrictLayoutTier.ofHalves(utc, 20, label, shichen, 70));
  equal('halves tier 2 when the left half is crowded', DistrictLayoutTier.HIDE_UTC,
    DistrictLayoutTier.ofHalves(utc, 60, label, shichen, 80));
  equal('halves tier 3 when even the place alone does not fit', DistrictLayoutTier.ELLIPSIS,
    DistrictLayoutTier.ofHalves(utc, 200, label, shichen, 80));

  // 按地点名称长度选档（用户规格）：短→0、中→1、长→2、极长→3。
  const nameTier = (placeWidth: number, nameLength: number): number =>
    DistrictLayoutTier.ofNameLength(36, placeWidth, 48, 24, 160, nameLength);
  equal('name length tier 0 for a short place', DistrictLayoutTier.FULL, nameTier(60, 5));
  equal('name length tier 1 for a medium place', DistrictLayoutTier.HIDE_LABEL, nameTier(180, 15));
  equal('name length tier 2 for a long place', DistrictLayoutTier.HIDE_UTC, nameTier(264, 22));
  equal('name length tier 3 for a very long place', DistrictLayoutTier.ELLIPSIS, nameTier(480, 40));
  // 各档元素可见性：0 有真太阳时；1 无真太阳时、有时区；2/3 无时区；3 压缩。
  check('tier 0 shows the solar-time label', DistrictLayoutTier.FULL < DistrictLayoutTier.HIDE_LABEL);
  check('tier 1 keeps the utc label but hides the solar-time label',
    DistrictLayoutTier.HIDE_LABEL < DistrictLayoutTier.HIDE_UTC);
  check('tier 2/3 hide the utc label',
    DistrictLayoutTier.HIDE_UTC < DistrictLayoutTier.ELLIPSIS);

  // 档位 + 字号联合求解：先 12fp 试档，档内缩到 9fp，仍放不下才退下一档。
  const hkPlan: DistrictLayoutPlan = DistrictLayoutSolver.solve(36, 132, 48, 24, 160, 345);
  equal('hong kong lands on tier 1', DistrictLayoutTier.HIDE_LABEL, hkPlan.tier);
  equal('hong kong keeps 12fp', 12, hkPlan.fontSize);
  const beijingPlan: DistrictLayoutPlan = DistrictLayoutSolver.solve(36, 36, 48, 24, 160, 345);
  equal('beijing lands on tier 0', DistrictLayoutTier.FULL, beijingPlan.tier);
  equal('beijing keeps 12fp', 12, beijingPlan.fontSize);
  const sydneyPlan: DistrictLayoutPlan = DistrictLayoutSolver.solve(36, 276, 48, 24, 160, 260);
  equal('sydney falls to the last tier that still runs', DistrictLayoutTier.ELLIPSIS, sydneyPlan.tier);
  equal('sydney keeps 12fp', 12, sydneyPlan.fontSize);
  const hugePlan: DistrictLayoutPlan = DistrictLayoutSolver.solve(36, 480, 48, 24, 160, 260);
  equal('40 chars lands on tier 3', DistrictLayoutTier.ELLIPSIS, hugePlan.tier);
  equal('40 chars stays 12fp instead of shrinking', 12, hugePlan.fontSize);
  check('the solver never shrinks below 12fp',
    hkPlan.fontSize === 12 && beijingPlan.fontSize === 12 && sydneyPlan.fontSize === 12 &&
      hugePlan.fontSize === 12);
  // 回归：自然宽度 ≤ 该档可用宽时，字号必须保持 12。
  const fitsPlan: DistrictLayoutPlan = DistrictLayoutSolver.solve(36, 120, 48, 24, 160, 345);
  equal('a fitting name keeps 12fp', 12, fitsPlan.fontSize);

  // 英文长名（Bilecik…）半栏放不下、整行放得下 → 退到档 1，绝不停在档 0 被截断。
  const bilecikPlan: DistrictLayoutPlan = DistrictLayoutSolver.solve(36, 240, 48, 24, 160, 345);
  equal('a long english name drops out of tier 0', DistrictLayoutTier.HIDE_LABEL, bilecikPlan.tier);
  check('a name wider than half never stays on tier 0',
    DistrictLayoutSolver.solve(36, 170, 48, 24, 160, 345).tier !== DistrictLayoutTier.FULL);
  equal('only a name wider than the row reaches tier 3', DistrictLayoutTier.ELLIPSIS,
    DistrictLayoutSolver.solve(36, 330, 48, 24, 160, 345).tier);
}

// ---- 地名反查策略：5 km + 30 天 + 60 秒采样 ----
{
  check('half a kilometre is trusted', !PlaceNamePolicy.shouldQuery(0.5, 1000));
  check('six kilometres triggers a query', PlaceNamePolicy.shouldQuery(6, 1000));
  check('a month old name triggers a query',
    PlaceNamePolicy.shouldQuery(1, 31 * 24 * 60 * 60 * 1000));
  check('unknown distance always triggers a query', PlaceNamePolicy.shouldQuery(-1, 1000));
  check('5 km exactly is trusted', PlaceNamePolicy.trustsNameAt(5.0));
  check('5.1 km is not trusted', !PlaceNamePolicy.trustsNameAt(5.1));
  equal('gps sample interval is 60 seconds', 60, PlaceNamePolicy.LOCATION_SAMPLE_INTERVAL_SECONDS);
}

// ---- 换地点：缓存 key 必须含坐标，视口状态必须重置 ----
{
  check('tile cache key contains the coordinates',
    cacheKey(39.9042, 116.4074) !== cacheKey(-33.8688, 151.2093));
  check('tile urls contain the new tile coordinates',
    tileOf(MapStyle.OSM, 39.9042, 116.4074, 12) !== tileOf(MapStyle.OSM, -33.8688, 151.2093, 12));
  check('a place change must reset the map',
    MapTilesLogic.shouldResetForPlace(39.9042, 116.4074, -33.8688, 151.2093));
  check('the same place does not reset the map',
    !MapTilesLogic.shouldResetForPlace(39.9042, 116.4074, 39.9042, 116.4074));
}

console.log(`\n${passed} checks passed, ${failures.length} failed`);
if (failures.length > 0) {
  for (const failure of failures) {
    console.log(`  FAIL ${failure}`);
  }
  process.exit(1);
}
