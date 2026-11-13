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
import { SolarTimeSnapshot } from './core/SolarSnapshot';
import { CityIndex } from './core/CityIndex';
import { TakeBand, TakeTemperature, TakeTimeLogic, MINUTES_PER_DAY } from './core/TakeTime';import { WeatherLogic, WeatherCondition, HourPoint } from './core/Weather';
import { DistrictNameLogic } from './core/DistrictName';
import { ChimeLogic } from './core/Chime';
import { Place } from './core/Place';
import { MapTilesLogic, MapDatum, TILE_PX, MIN_ZOOM, MAX_ZOOM } from './core/MapTiles';

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
  check('refresh when stale', WeatherLogic.shouldRefresh(31 * 60 * 1000, 0));
  check('refresh when moved', WeatherLogic.shouldRefresh(60 * 1000, 6));
  check('no refresh when fresh and still', !WeatherLogic.shouldRefresh(60 * 1000, 1));
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

// ---- 区划名 ----
{
  const names = DistrictNameLogic.composeNames(['南山区', '深圳市', '广东省']);
  check('composed names', names !== null && names.full === '南山区, 深圳市, 广东省', `${names ? names.full : 'null'}`);
  check('short name is finest level', names !== null && names.short === '南山区');
  check('placeholder dropped', DistrictNameLogic.composeNames(['市辖区', '北京市'])?.full === '北京市');
  check('duplicate dropped', DistrictNameLogic.composeNames(['深圳', '深圳', '广东'])?.full === '深圳, 广东');
  check('empty gives null', DistrictNameLogic.composeNames(['', '[]', '  ']) === null);
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
  equal('ten presets', 10, Place.PRESETS.length);
  check('valid latitude', Place.isValidLatitude(39.9) && !Place.isValidLatitude(91));
  check('same location', Place.DEFAULT.sameLocation(new Place(39.9042, 116.4074, 0, '', '')));
}

// ---- 位置地图瓦片 ----
{
  const shanghai = MapTilesLogic.layerFor(31.2304, 121.4737);
  const tokyo = MapTilesLogic.layerFor(35.6812, 139.7671);
  check('amap inside China', shanghai.datum === MapDatum.GCJ02 && shanghai.name.indexOf('amap') === 0);
  check('osm outside China', tokyo.datum === MapDatum.WGS84 && tokyo.name === 'osm');
  check('china bounds', MapTilesLogic.isInChina(31.23, 121.47) && !MapTilesLogic.isInChina(35.68, 139.76));

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
  const osmTile = MapTilesLogic.visibleTiles(tokyo, 35.6812, 139.7671, 12, widthPx, heightPx)[0];
  check('osm tile url', osmTile.url.indexOf('tile.openstreetmap.org/12/') > 0);
  check('zoom clamped', MapTilesLogic.clampZoom(1) === MIN_ZOOM && MapTilesLogic.clampZoom(99) === MAX_ZOOM);
}

console.log(`\n${passed} checks passed, ${failures.length} failed`);
if (failures.length > 0) {
  for (const failure of failures) {
    console.log(`  FAIL ${failure}`);
  }
  process.exit(1);
}
