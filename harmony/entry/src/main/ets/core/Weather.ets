/**
 * 当前天气（气温 + WMO 天气码）与逐时预报的解析、分类与槽位排布。
 *
 * 主源是 Open-Meteo：免费、无需 Key、全球可用，**逐时粒度 1 小时**（CC BY 4.0）。
 * 主源失败时降级到备用源 7Timer!，它的 civil 产品是**逐时粒度 3 小时**（界面底部署名随之切换）。
 *
 * 「步长」是随数据一起缓存的一等公民（见 [WeatherSource.stepHoursOf]）：界面永远只画 6 个槽位，
 * 但槽位之间的间隔跟着数据源走 —— 拿 1 小时的网格去配 3 小时的数据，标签就会和实际读数错位。
 *
 * 这里只有纯逻辑：请求与缓存放在 services/WeatherService.ets，
 * 以便 core-check（Tools/verify-core.js）能脱离鸿蒙 SDK 直接跑数值自检。
 */

export enum WeatherCondition {
  CLEAR = 0,
  PARTLY_CLOUDY = 1,
  OVERCAST = 2,
  FOG = 3,
  DRIZZLE = 4,
  RAIN = 5,
  HEAVY_RAIN = 6,
  SHOWERS = 7,
  SNOW = 8,
  HEAVY_SNOW = 9,
  THUNDER = 10
}

/**
 * 逐时数据的数据源；**步长跟着来源走**（主源 1 小时、备用源 3 小时）。
 *
 * 用字符串常量而不是枚举：这两个值会原样写进偏好（`weather_cache` 的 `source` 键），
 * 与 Android 侧的 `Source.id` 完全一致，排查时两边日志能直接对上。
 */
export class WeatherSource {
  /** 主源：Open-Meteo（CC BY 4.0）。 */
  static readonly OPEN_METEO: string = 'open-meteo';
  /** 备用源：7Timer!（civil 产品，3 小时粒度，不给 `current` 块）。 */
  static readonly SEVEN_TIMER: string = '7timer';
  static readonly OPEN_METEO_STEP_HOURS: number = 1;
  static readonly SEVEN_TIMER_STEP_HOURS: number = 3;

  /** 缓存里的来源字符串（可能来自旧版本或被人为改坏）→ 规范值，认不出来一律当主源。 */
  static of(id: string): string {
    return id === WeatherSource.SEVEN_TIMER ? WeatherSource.SEVEN_TIMER : WeatherSource.OPEN_METEO;
  }

  /** 该来源的逐时步长（小时）。 */
  static stepHoursOf(id: string): number {
    return WeatherSource.of(id) === WeatherSource.SEVEN_TIMER
      ? WeatherSource.SEVEN_TIMER_STEP_HOURS
      : WeatherSource.OPEN_METEO_STEP_HOURS;
  }

  /** 界面/诊断里的短名。 */
  static displayName(id: string): string {
    return WeatherSource.of(id) === WeatherSource.SEVEN_TIMER ? '7Timer!' : 'Open-Meteo';
  }

  /** 界面底部署名（跟着实际源切换：CC BY 4.0 只对 Open-Meteo 要求）。 */
  static attribution(id: string): string {
    return WeatherSource.of(id) === WeatherSource.SEVEN_TIMER
      ? '7Timer!'
      : 'Open-Meteo（CC BY 4.0）';
  }
}

/** 主源失败之后的处理方案（纯判定，便于自检）。 */
export enum WeatherFallback {
  /** 缓存还没过期：什么都不做，界面继续用缓存（不清空）。 */
  KEEP_CACHE = 0,
  /** 缓存已过期，或根本没有缓存：去问备用源 7Timer!。 */
  TRY_SEVEN_TIMER = 1
}

/** 界面上的一个逐时槽位：用哪个采样点，以及它是不是「现在」那一格。 */
export class WeatherSlot {
  epochSeconds: number;
  isNow: boolean;

  constructor(epochSeconds: number, isNow: boolean) {
    this.epochSeconds = epochSeconds;
    this.isNow = isNow;
  }
}

/**
 * 主源的一份完整结果：实时读数 + 逐时序列。
 *
 * 两者缺一都算失败（只有 `current` 没有 `hourly`，或 JSON 被截断）→ 降级到备用源，
 * 否则界面会拿到一份「有气温、没有逐时」的半残数据。
 */
export class PrimaryWeather {
  snapshot: WeatherSnapshot;
  hourly: HourPoint[];

  constructor(snapshot: WeatherSnapshot, hourly: HourPoint[]) {
    this.snapshot = snapshot;
    this.hourly = hourly;
  }
}

export class WeatherSnapshot {
  temperatureC: number;
  code: number;

  constructor(temperatureC: number, code: number) {
    this.temperatureC = temperatureC;
    this.code = code;
  }
}

/** 某个整点的小时预报。 */
export class HourPoint {
  epochSeconds: number;
  temperatureC: number;
  code: number;

  constructor(epochSeconds: number, temperatureC: number, code: number) {
    this.epochSeconds = epochSeconds;
    this.temperatureC = temperatureC;
    this.code = code;
  }
}

function floorMod(value: number, modulus: number): number {
  return ((value % modulus) + modulus) % modulus;
}

export class WeatherLogic {
  /** 取数的刷新间隔 30 分钟；位置移动超过 5 km 也重新取数。 */
  static readonly TTL_MILLIS: number = 30 * 60 * 1000;
  /** 显示用的保留时限（与小时预报一致）：刷新失败时继续显示最近一次取到的数据。 */
  static readonly HOURLY_MAX_AGE_MILLIS: number = 24 * 60 * 60 * 1000;
  /** 取数失败后的重试间隔：成功是 30 分钟一拍，失败时 5 分钟就再试一次。 */
  static readonly RETRY_AFTER_FAILURE_MILLIS: number = 5 * 60 * 1000;
  static readonly MOVE_THRESHOLD_KM: number = 5.0;
  /** 没有有效天气时天气位显示的占位符：半角减号（与 Android 的 `weather_unknown` 一致）。 */
  static readonly PLACEHOLDER: string = '-';
  /**
   * 逐时预报的槽位数：**恒为 6 个**，不随数据源变化。
   *
   * 变的是步长（1 小时源覆盖 6 小时、3 小时源覆盖 18 小时），不是格数 ——
   * 界面（首页大卡片、桌面卡片）按 6 等分排版，格数一变版面就散了。
   */
  static readonly SLOT_COUNT: number = 6;
  /** 显示用的时限（与小时预报一致）：取数失败时旧数据最长还能显示 24 小时。 */
  static readonly DISPLAY_MAX_AGE_MILLIS: number = 24 * 60 * 60 * 1000;
  /**
   * 单次 HTTP 请求的超时（连接 / 读取各自 5 秒）。
   *
   * 主源失败一次就立刻降级到 7Timer!，所以这里不能等太久：5 秒内拿不到就走备用源，
   * 避免界面长时间停在「更新中…」。
   */
  static readonly HTTP_TIMEOUT_MILLIS: number = 5000;
  /**
   * 低精度数据（备用源 3 小时）的升级重试节流：**前台首次 60 秒**。
   *
   * 连续失败会退避（见 [lowPrecisionRetryDelayMillis]）：60 → 120 → 300 秒封顶；
   * 后台（不可见 / 卡片刷新）一律 10 分钟。切回主源后这条规则自然不再触发。
   */
  static readonly LOW_PRECISION_RETRY_MILLIS: number = 60 * 1000;
  /** 前台连续失败的最大退避间隔（封顶 5 分钟）。 */
  static readonly LOW_PRECISION_MAX_BACKOFF_MILLIS: number = 5 * 60 * 1000;
  /** 后台（应用不可见，或卡片刷新路径）重试主源的最小间隔。 */
  static readonly LOW_PRECISION_BACKGROUND_RETRY_MILLIS: number = 10 * 60 * 1000;

  static buildUrl(latitude: number, longitude: number): string {
    return 'https://api.open-meteo.com/v1/forecast' +
      `?latitude=${latitude.toFixed(4)}&longitude=${longitude.toFixed(4)}` +
      '&current=temperature_2m,weather_code' +
      '&hourly=temperature_2m,weather_code&forecast_days=2&past_days=1&timezone=UTC';
  }

  /** 备用源 7Timer! 的取数地址（注意参数顺序是 lon 在前、lat 在后）。 */
  static buildSevenTimerUrl(latitude: number, longitude: number): string {
    return `https://www.7timer.info/bin/api.pl?lon=${longitude.toFixed(4)}` +
      `&lat=${latitude.toFixed(4)}&product=civil&output=json`;
  }

  /** 解析当前天气；结构不对时返回 null。 */
  static parse(json: string): WeatherSnapshot | null {
    let root: Record<string, Object>;
    try {
      root = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return null;
    }
    const current: Object | undefined = root['current'];
    if (current === undefined || current === null) {
      return null;
    }
    const fields: Record<string, Object> = current as Record<string, Object>;
    const temperature: Object | undefined = fields['temperature_2m'];
    if (temperature === undefined || temperature === null) {
      return null;
    }
    const code: Object | undefined = fields['weather_code'];
    return new WeatherSnapshot(Math.round(Number(temperature)), code === undefined ? 0 : Number(code));
  }

  /** 解析 hourly 序列（请求时指定 timezone=UTC，时间因此可直接当 UTC 解析）。 */
  static parseHourly(json: string): HourPoint[] {
    const points: HourPoint[] = [];
    let root: Record<string, Object>;
    try {
      root = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return points;
    }
    const hourly: Object | undefined = root['hourly'];
    if (hourly === undefined || hourly === null) {
      return points;
    }
    const fields: Record<string, Object> = hourly as Record<string, Object>;
    const times: Object[] = fields['time'] as Object[];
    const temps: Object[] = fields['temperature_2m'] as Object[];
    const codes: Object[] = fields['weather_code'] as Object[];
    if (!Array.isArray(times) || !Array.isArray(temps)) {
      return points;
    }
    const count: number = Math.min(times.length, temps.length);
    for (let index = 0; index < count; index++) {
      const epoch: number = WeatherLogic.parseUtcHour(times[index] as string);
      if (epoch < 0) {
        continue;
      }
      const temperature: number = Number(temps[index]);
      if (isNaN(temperature)) {
        continue;
      }
      const code: number = Array.isArray(codes) && codes.length > index ? Number(codes[index]) : 0;
      points.push(new HourPoint(epoch, Math.round(temperature), code));
    }
    return points;
  }

  /** "2026-11-02T04:00" → UTC 秒；格式不对返回 -1。 */
  static parseUtcHour(text: string): number {
    const match: RegExpMatchArray | null = text.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
    if (match === null) {
      return -1;
    }
    const millis: number = Date.UTC(
      Number.parseInt(match[1]),
      Number.parseInt(match[2]) - 1,
      Number.parseInt(match[3]),
      Number.parseInt(match[4]),
      Number.parseInt(match[5])
    );
    return Math.floor(millis / 1000);
  }

  /**
   * 解析 7Timer! 的 `dataseries`。
   *
   * 官方 `api.pl` **不给每个点的绝对时刻**，只给「模式起报时刻 `init`」（UTC，如 `"2026111606"`）
   * 加「相对 init 的小时数 `timepoint`」（实测 2026-11 的返回是 3, 6, 9, …）；旧文档/部分镜像里
   * 还出现过 `time` 字段（形如 `2025111603`）。两种都认，且都**向下对齐到 3 小时网格**
   * （UTC 的 0/3/6/…/21 点，也就是 7Timer! 自己的采样网格；换成 +08:00 就是本地的
   * 2/5/8/…/23 点，所以逐时行显示 `现在 / 23时 / 2时 / 5时 / 8时 / 11时`），
   * 免得界面上出现 `22时`、`1时` 这种不在网格上的标签。
   */
  static parseSevenTimer(json: string): HourPoint[] {
    const points: HourPoint[] = [];
    let root: Record<string, Object>;
    try {
      root = JSON.parse(json) as Record<string, Object>;
    } catch (error) {
      return points;
    }
    const series: Object[] = root['dataseries'] as Object[];
    if (!Array.isArray(series)) {
      return points;
    }
    const initValue: Object | undefined = root['init'];
    // 有 init 才能用 timepoint 推时刻；没有 init 且条目也没有 time 时，整条丢掉。
    const initEpoch: number = initValue === undefined || initValue === null
      ? -1
      : WeatherLogic.sevenTimerStampEpoch(String(initValue));
    for (const item of series) {
      if (item === undefined || item === null) {
        continue;
      }
      const fields: Record<string, Object> = item as Record<string, Object>;
      const temperatureValue: Object | undefined = fields['temp2m'];
      if (temperatureValue === undefined || temperatureValue === null) {
        continue;
      }
      const temperature: number = Number(temperatureValue);
      if (isNaN(temperature)) {
        continue;
      }
      let epoch: number = -1;
      const timeValue: Object | undefined = fields['time'];
      if (timeValue !== undefined && timeValue !== null) {
        epoch = WeatherLogic.sevenTimerStampEpoch(String(timeValue));
      }
      if (epoch < 0) {
        const timepointValue: Object | undefined = fields['timepoint'];
        if (initEpoch < 0 || timepointValue === undefined || timepointValue === null) {
          continue;
        }
        const timepoint: number = Number(timepointValue);
        if (isNaN(timepoint)) {
          continue;
        }
        epoch = initEpoch + timepoint * 3600;
      }
      const weatherValue: Object | undefined = fields['weather'];
      const code: number = WeatherLogic.wmoCodeOfSevenTimer(
        weatherValue === undefined || weatherValue === null ? '' : String(weatherValue));
      points.push(new HourPoint(
        WeatherLogic.alignToStep(epoch, WeatherSource.SEVEN_TIMER_STEP_HOURS),
        Math.round(temperature),
        code
      ));
    }
    // 采样点按时间排序：卡片按顺序往后取槽位，乱序会让「现在」跳格。
    points.sort((left: HourPoint, right: HourPoint): number => left.epochSeconds - right.epochSeconds);
    return points;
  }

  /** `2025111603` / `2026111606` 这类 UTC 时刻串（yyyyMMddHH）→ epoch 秒；解析不了返回 -1。 */
  static sevenTimerStampEpoch(stamp: string): number {
    const match: RegExpMatchArray | null = stamp.trim().match(/^(\d{4})(\d{2})(\d{2})(\d{2})$/);
    if (match === null) {
      return -1;
    }
    const millis: number = Date.UTC(
      Number.parseInt(match[1]),
      Number.parseInt(match[2]) - 1,
      Number.parseInt(match[3]),
      Number.parseInt(match[4])
    );
    return Math.floor(millis / 1000);
  }

  /**
   * 7Timer! 的天气词 → WMO 天气码（与主源共用同一套文案与图标）。
   *
   * 7Timer 用 `day`/`night` 后缀区分昼夜（`clearday` / `cloudynight`），先剥掉后缀再查表；
   * 表外的值按「多云」处理（宁可少报一个极端天气，也不要显示成晴）。
   */
  static wmoCodeOfSevenTimer(weather: string): number {
    let key: string = weather.trim().toLowerCase();
    if (key.endsWith('night')) {
      key = key.substring(0, key.length - 5);
    } else if (key.endsWith('day')) {
      key = key.substring(0, key.length - 3);
    }
    switch (key) {
      case 'clear':
      case 'sunny':
        return 0; // 晴
      case 'pcloudy':
        return 2; // 多云
      case 'mcloudy':
      case 'cloudy':
      case 'overcast':
        return 3; // 阴
      case 'humid':
      case 'fog':
      case 'foggy':
        return 45; // 雾
      case 'lightrain':
      case 'drizzle':
      case 'oshower':
      case 'ishower':
      case 'shower':
      case 'showers':
        return 80; // 阵雨 / 小雨
      case 'rain':
        return 63; // 中雨
      case 'heavyrain':
        return 65; // 大雨
      case 'lightsnow':
        return 71; // 小雪
      case 'snow':
      case 'snowrain':
      case 'rainsnow':
      case 'sleet':
        return 73; // 雪 / 雨夹雪
      case 'ts':
      case 'thunder':
      case 'thunderstorm':
        return 95; // 雷雨
      default:
        return 2; // 未知 → 多云
    }
  }

  /**
   * 主源的一份完整结果：实时读数 + 逐时序列。
   *
   * 两者缺一都算失败：只有 `current` 没有 `hourly`（或 JSON 被截断）时降级到备用源，
   * 否则界面会拿到一份「有气温、没有逐时」的半残数据。
   */
  static parsePrimary(json: string): PrimaryWeather | null {
    const snapshot: WeatherSnapshot | null = WeatherLogic.parse(json);
    if (snapshot === null) {
      return null;
    }
    const hourly: HourPoint[] = WeatherLogic.parseHourly(json);
    if (hourly.length === 0) {
      return null;
    }
    return new PrimaryWeather(snapshot, hourly);
  }

  /** 从逐时序列里取「现在」的读数（7Timer 没有 current 块）：不晚于当前时刻的最后一个点。 */
  static snapshotAt(points: HourPoint[], nowEpochSeconds: number): WeatherSnapshot | null {
    let chosen: HourPoint | null = null;
    for (const point of points) {
      if (point.epochSeconds <= nowEpochSeconds && (chosen === null || point.epochSeconds > chosen.epochSeconds)) {
        chosen = point;
      }
    }
    if (chosen === null) {
      // 全都在未来：退回最早的那一点（宁可显示最近的预报，也不要空格）。
      for (const point of points) {
        if (chosen === null || point.epochSeconds < chosen.epochSeconds) {
          chosen = point;
        }
      }
    }
    return chosen === null ? null : new WeatherSnapshot(chosen.temperatureC, chosen.code);
  }

  /** 把时刻向下对齐到 stepHours 小时的整点网格（UTC 网格：0/3/6/…/21 点）。 */
  static alignToStep(epochSeconds: number, stepHours: number): number {
    const step: number = Math.max(1, stepHours) * 3600;
    return epochSeconds - floorMod(epochSeconds, step);
  }

  /** 某个 UTC 秒在给定偏移下的本地小时数（0–23，负数偏移也不会算错）。 */
  static localHourOf(epochSeconds: number, zoneOffsetSeconds: number): number {
    return Math.floor(floorMod(epochSeconds + zoneOffsetSeconds, 86400) / 3600);
  }

  /**
   * 卡片要显示的时刻：从当前所在的 stepHours 小时块开始，按步长取 count 个（本地时区对齐）。
   * 返回 UTC 秒，可直接与 HourPoint.epochSeconds 对应。
   */
  static slots(nowEpochSeconds: number, zoneOffsetSeconds: number, count: number, stepHours: number): number[] {
    const step: number = stepHours * 3600;
    const local: number = nowEpochSeconds + zoneOffsetSeconds;
    const blockStart: number = local - floorMod(local, step);
    const result: number[] = [];
    for (let index = 0; index < count; index++) {
      result.push(blockStart + index * step - zoneOffsetSeconds);
    }
    return result;
  }

  /**
   * 界面真正要画的那 6 格（首页大卡片与桌面卡片共用这一条规则，与 Android 的 `visibleSlots` 一致）。
   *
   * - **首格永远是「现在」**：当前时刻之前最近的那个采样点（全都在未来时取第一个点）。
   *   它不是「当前整点」——3 小时源在 21:30 的「现在」是 20 点那一条读数。
   * - 之后按**数据源自己的步长**往后取：1 小时源是 现在/22时/23时/0时/1时/2时，
   *   3 小时源是 现在/23时/2时/5时/8时/11时（取决于采样网格）。标签一律用该点的实际本地小时数。
   * - 没有数据时退回按步长对齐的理论网格，让格子照样排出来（内容显示占位符）。
   *
   * @param skip 跳过前面几格（桌面卡片的第二排逐时行接在第一排后面）。
   */
  static visibleSlots(
    points: HourPoint[],
    nowEpochSeconds: number,
    zoneOffsetSeconds: number,
    count: number,
    stepHours: number,
    skip: number = 0
  ): WeatherSlot[] {
    const step: number = Math.max(1, stepHours) * 3600;
    const offset: number = Math.max(0, skip) * step;
    // 锚点：不晚于当前时刻的**最后一个**采样点（不是「当前整点」，3 小时源常常对不上整点）。
    let anchor: number = -1;
    for (const point of points) {
      if (point.epochSeconds <= nowEpochSeconds && point.epochSeconds > anchor) {
        anchor = point.epochSeconds;
      }
    }
    if (anchor < 0) {
      for (const point of points) {
        if (anchor < 0 || point.epochSeconds < anchor) {
          anchor = point.epochSeconds;
        }
      }
    }
    const shifted: number = nowEpochSeconds + offset;
    let start: number = 0;
    if (anchor >= 0) {
      start = anchor + offset;
    } else if (stepHours <= 1) {
      // 1 小时源按**本地整点**对齐（用户看到的就是整点）。
      const local: number = shifted + zoneOffsetSeconds;
      start = local - floorMod(local, 3600) - zoneOffsetSeconds;
    } else {
      // 3 小时源按 UTC 的 0/3/6/…/21 点对齐 —— 与 7Timer! 的采样网格一致，数据一到标签不会整体跳一格。
      start = WeatherLogic.alignToStep(shifted, stepHours);
    }
    const slots: WeatherSlot[] = [];
    for (let index = 0; index < count; index++) {
      slots.push(new WeatherSlot(start + index * step, skip <= 0 && index === 0));
    }
    return slots;
  }

  /** 槽位 → 逐时行标签：第一格「现在」，其余用该点实际所在的本地小时数（如 `23时` / `23:00`）。 */
  static slotLabels(slots: WeatherSlot[], zoneOffsetSeconds: number, language: string): string[] {
    const labels: string[] = [];
    for (const slot of slots) {
      labels.push(slot.isNow
        ? WeatherLogic.nowLabel(language)
        : WeatherLogic.hourLabel(WeatherLogic.localHourOf(slot.epochSeconds, zoneOffsetSeconds), language));
    }
    return labels;
  }

  static nowLabel(language: string): string {
    return language.startsWith('zh') ? '现在' : 'Now';
  }

  static hourLabel(hour: number, language: string): string {
    return language.startsWith('zh') ? `${hour}时` : `${hour}:00`;
  }

  /**
   * 六格逐时气温（与 Android `HeroExtras.hourTemperatures`、iOS `HeroCard.HourlyRow` 同一规则）。
   *
   * **首格（「现在」）用实时读数**，其余格用各自采样点的温度；没有该格采样点时是 null。
   * 「现在」为什么不用采样点：备用源 3 小时才一个采样点，那一格可能是几小时前的读数，
   * 而卡片日期行显示的是此刻的实时温度，两处挨着却不一样会显得其中一个错了。
   *
   * @param currentTemperatureC 卡片日期行用的那个实时温度；没有实时读数时退回该采样点温度。
   * @param skip 跳过前面几格（桌面卡片的第二排逐时行接在第一排后面）。
   */
  static hourTemperatures(
    points: HourPoint[],
    nowEpochSeconds: number,
    zoneOffsetSeconds: number,
    stepHours: number,
    currentTemperatureC: number | null,
    count: number = WeatherLogic.SLOT_COUNT,
    skip: number = 0
  ): (number | null)[] {
    const slots: WeatherSlot[] = WeatherLogic.visibleSlots(
      points, nowEpochSeconds, zoneOffsetSeconds, count, stepHours, skip);
    const byEpoch: Map<number, HourPoint> = new Map<number, HourPoint>();
    for (const point of points) {
      byEpoch.set(point.epochSeconds, point);
    }
    const temperatures: (number | null)[] = [];
    for (const slot of slots) {
      const point: HourPoint | undefined = byEpoch.get(slot.epochSeconds);
      if (slot.isNow) {
        temperatures.push(currentTemperatureC !== null
          ? currentTemperatureC
          : (point === undefined ? null : point.temperatureC));
      } else {
        temperatures.push(point === undefined ? null : point.temperatureC);
      }
    }
    return temperatures;
  }

  /**
   * 一格温度的文字：有读数时 `18°`（数字 + 度符号，不带 C），缺读数时 `-`。
   *
   * 占位符沿用 [PLACEHOLDER]（半角减号），不是 `--`：温度只有「有」和「没有」两种，
   * 两个字符在 22vp 的图标下面会挤成一条看不清的横线。
   */
  static temperatureLabel(temperatureC: number | null): string {
    return temperatureC === null
      ? WeatherLogic.PLACEHOLDER
      : `${Math.round(temperatureC)}°`;
  }

  /**
   * 主源失败之后怎么办（纯判定，便于自检）。
   *
   * - 没有缓存 → 去问备用源；
   * - 缓存还没过期（30 分钟内）→ **什么都不做**，界面继续显示缓存，不清空；
   * - 缓存过期 → 去问备用源（7Timer!）。
   */
  static fallbackFor(hasCache: boolean, cacheAgeMillis: number): WeatherFallback {
    if (!hasCache) {
      return WeatherFallback.TRY_SEVEN_TIMER;
    }
    if (cacheAgeMillis >= 0 && cacheAgeMillis <= WeatherLogic.TTL_MILLIS) {
      return WeatherFallback.KEEP_CACHE;
    }
    return WeatherFallback.TRY_SEVEN_TIMER;
  }

  /** 这份缓存还值不值得显示（24 小时内都算「旧数据但可显示」）。 */
  static isDisplayable(cacheAgeMillis: number): boolean {
    return cacheAgeMillis >= 0 && cacheAgeMillis <= WeatherLogic.DISPLAY_MAX_AGE_MILLIS;
  }

  /**
   * 这份缓存是不是「低精度」的：来自备用源 7Timer!、步长 3 小时。
   *
   * 低精度数据即使还没过期也要尽快升级回 Open-Meteo 的 1 小时网格 ——
   * 同样是 6 格，1 小时源覆盖 6 小时、3 小时源覆盖 18 小时，粒度差 3 倍。
   */
  static isLowPrecision(source: string, stepHours: number): boolean {
    return WeatherSource.of(source) === WeatherSource.SEVEN_TIMER
      || stepHours > WeatherSource.OPEN_METEO_STEP_HOURS;
  }

  /**
   * 拿着低精度数据时，距离下一次「试主源」的等待时长。
   *
   * - 后台（应用不可见 / 卡片刷新）→ 10 分钟，不参与 60 秒轮询；
   * - 前台：0~1 次连续失败 60 秒，2 次 120 秒，3 次及以上 300 秒（封顶 5 分钟）。
   */
  static lowPrecisionRetryDelayMillis(consecutiveFailures: number, isForeground: boolean): number {
    if (!isForeground) {
      return WeatherLogic.LOW_PRECISION_BACKGROUND_RETRY_MILLIS;
    }
    if (consecutiveFailures <= 1) {
      return WeatherLogic.LOW_PRECISION_RETRY_MILLIS;
    }
    if (consecutiveFailures === 2) {
      return 2 * WeatherLogic.LOW_PRECISION_RETRY_MILLIS;
    }
    return WeatherLogic.LOW_PRECISION_MAX_BACKOFF_MILLIS;
  }

  /** 下一次「试主源」的时刻（毫秒时间戳）：`now + 退避间隔`，便于断言与诊断倒计时。 */
  static nextLowPrecisionRetryAt(nowMillis: number, consecutiveFailures: number,
    isForeground: boolean): number {
    return nowMillis + WeatherLogic.lowPrecisionRetryDelayMillis(consecutiveFailures, isForeground);
  }

  /** 低精度升级判定：低精度且距上次尝试已超过按「连续失败次数 × 前后台」算出的退避间隔。 */
  static shouldUpgradePrecision(source: string, stepHours: number, sinceAttemptMillis: number,
    consecutiveFailures: number = 0, isForeground: boolean = true): boolean {
    if (!WeatherLogic.isLowPrecision(source, stepHours)) {
      return false;
    }
    const delay: number = WeatherLogic.lowPrecisionRetryDelayMillis(consecutiveFailures, isForeground);
    return !(sinceAttemptMillis >= 0 && sinceAttemptMillis < delay);
  }

  /** 回到前台要不要**立刻**试一次（不受剩余退避秒数限制）：只有拿着低精度数据时才需要。 */
  static shouldForceUpgradeOnForeground(source: string, stepHours: number): boolean {
    return WeatherLogic.isLowPrecision(source, stepHours);
  }

  /**
   * 该不该去取数：**任意一条满足即刷新**。
   *
   *   ① 位置移动超过 5 km（用户换了地点）；
   *   ② 缓存过期（超过 30 分钟）且不在失败后的 5 分钟节流里（[shouldRefresh]）；
   *   ③ 当前是低精度数据（7Timer! / 3 小时），即使没过期也按「连续失败退避」尝试升级回
   *      1 小时源：前台 60 / 120 / 300 秒（封顶），后台一律 10 分钟。
   *
   * 「应用回到前台 / 切换地点」时的立即触发不走这里：调用方直接 force，见
   * services/WeatherService.ets 的 `refreshIfNeeded(place, force)`。
   */
  static needsFetch(
    ageMillis: number,
    movedKm: number,
    sinceAttemptMillis: number,
    source: string,
    stepHours: number,
    consecutiveFailures: number = 0,
    isForeground: boolean = true
  ): boolean {
    if (WeatherLogic.shouldRefresh(ageMillis, movedKm, sinceAttemptMillis)) {
      return true;
    }
    return WeatherLogic.shouldUpgradePrecision(source, stepHours, sinceAttemptMillis,
      consecutiveFailures, isForeground);
  }

  /** 诊断用的「数据过期 N 分钟」；没有缓存（负值）返回空串。 */
  static staleLabel(cacheAgeMillis: number): string {
    if (cacheAgeMillis < 0) {
      return '';
    }
    return `数据过期 ${Math.floor(cacheAgeMillis / 60000)} 分钟`;
  }

  static encodeHourly(points: HourPoint[]): string {
    return points.map((point: HourPoint): string => `${point.epochSeconds},${point.temperatureC},${point.code}`).join(';');
  }

  static decodeHourly(encoded: string): HourPoint[] {
    const points: HourPoint[] = [];
    if (encoded.length === 0) {
      return points;
    }
    for (const item of encoded.split(';')) {
      const parts: string[] = item.split(',');
      if (parts.length !== 3) {
        continue;
      }
      const epoch: number = Number.parseInt(parts[0]);
      const temperature: number = Number.parseInt(parts[1]);
      if (isNaN(epoch) || isNaN(temperature)) {
        continue;
      }
      const code: number = Number.parseInt(parts[2]);
      points.push(new HourPoint(epoch, temperature, isNaN(code) ? 0 : code));
    }
    return points;
  }

  /** 本地某一天的最高/最低温度，返回 [最低, 最高]；没覆盖这一天返回 null。 */
  static temperatureRange(
    points: HourPoint[],
    dayStartMillis: number,
    dayEndMillis: number,
    zoneOffsetMillis: number
  ): number[] | null {
    let min: number = Number.MAX_SAFE_INTEGER;
    let max: number = Number.MIN_SAFE_INTEGER;
    let found: boolean = false;
    for (const point of points) {
      const local: number = point.epochSeconds * 1000 + zoneOffsetMillis;
      if (local < dayStartMillis || local >= dayEndMillis) {
        continue;
      }
      found = true;
      min = Math.min(min, point.temperatureC);
      max = Math.max(max, point.temperatureC);
    }
    return found ? [min, max] : null;
  }

  /**
   * 缓存是否该刷新。
   *
   * `sinceAttemptMillis` 是距上一次**尝试**取数的时长：过期后按 5 分钟节流，
   * 免得取数失败时每次回到前台都打一次网络；成功取到后尝试时刻会一起更新。
   */
  static shouldRefresh(ageMillis: number, movedKm: number, sinceAttemptMillis: number): boolean {
    if (movedKm > WeatherLogic.MOVE_THRESHOLD_KM) {
      return true;
    }
    if (ageMillis >= 0 && ageMillis <= WeatherLogic.TTL_MILLIS) {
      return false;
    }
    return !(sinceAttemptMillis >= 0 && sinceAttemptMillis <= WeatherLogic.RETRY_AFTER_FAILURE_MILLIS);
  }

  /**
   * 未来 count 个小时的预报文案，例如「14时 多云 21°」/ "2:00 PM? "。
   * 槽位按本地整点对齐，找不到对应数据的小时直接跳过。
   */
  static forecastLabels(
    points: HourPoint[],
    nowEpochSeconds: number,
    zoneOffsetSeconds: number,
    count: number,
    language: string
  ): string[] {
    const slots: number[] = WeatherLogic.slots(nowEpochSeconds, zoneOffsetSeconds, count, 1);
    const labels: string[] = [];
    for (const slot of slots) {
      let match: HourPoint | null = null;
      for (const point of points) {
        if (point.epochSeconds === slot) {
          match = point;
          break;
        }
      }
      if (match === null) {
        continue;
      }
      const hour: number = new Date((slot + zoneOffsetSeconds) * 1000).getUTCHours();
      const name: string = WeatherLogic.conditionName(WeatherLogic.conditionOf(match.code), language);
      labels.push(language.startsWith('zh')
        ? `${hour}时 ${name} ${match.temperatureC}°`
        : `${hour}:00 ${name} ${match.temperatureC}°`);
    }
    return labels;
  }

  /** WMO 天气码 → 分类。 */
  static conditionOf(code: number): WeatherCondition {
    switch (code) {
      case 0:
        return WeatherCondition.CLEAR;
      case 1:
      case 2:
        return WeatherCondition.PARTLY_CLOUDY;
      case 3:
        return WeatherCondition.OVERCAST;
      case 45:
      case 48:
        return WeatherCondition.FOG;
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return WeatherCondition.DRIZZLE;
      case 61:
      case 63:
      case 66:
      case 67:
        return WeatherCondition.RAIN;
      case 65:
      case 82:
        return WeatherCondition.HEAVY_RAIN;
      case 80:
      case 81:
        return WeatherCondition.SHOWERS;
      case 71:
      case 73:
      case 77:
      case 85:
      case 86:
        return WeatherCondition.SNOW;
      case 75:
        return WeatherCondition.HEAVY_SNOW;
      case 95:
      case 96:
      case 99:
        return WeatherCondition.THUNDER;
      default:
        return WeatherCondition.OVERCAST;
    }
  }

  /** 天气码 → 可读文案。 */
  static conditionLabel(code: number, language: string): string {
    return WeatherLogic.conditionName(WeatherLogic.conditionOf(code), language);
  }

  /**
   * 天气码 → 图标名（对应 resources/base/media/wx_*.svg，由 Tools/gen-wx-icons.py 从
   * Android 的 VectorDrawable 转出）。卡片与主界面共用，避免两处各写一套映射。
   */
  static iconKey(code: number, isDay: boolean): string {
    switch (WeatherLogic.conditionOf(code)) {
      case WeatherCondition.CLEAR:
        return isDay ? 'clear_day' : 'clear_night';
      case WeatherCondition.PARTLY_CLOUDY:
        return isDay ? 'partly_day' : 'partly_night';
      case WeatherCondition.OVERCAST:
        return 'overcast';
      case WeatherCondition.FOG:
        return 'fog';
      case WeatherCondition.DRIZZLE:
        return 'drizzle';
      case WeatherCondition.RAIN:
        return 'rain';
      case WeatherCondition.HEAVY_RAIN:
        return 'heavy_rain';
      case WeatherCondition.SHOWERS:
        return 'showers';
      case WeatherCondition.SNOW:
        return 'snow';
      case WeatherCondition.HEAVY_SNOW:
        return 'heavy_snow';
      case WeatherCondition.THUNDER:
        return 'thunder';
      default:
        return 'unknown';
    }
  }

  static conditionName(condition: WeatherCondition, language: string): string {
    const zh: string[] = ['晴', '多云', '阴', '雾', '毛毛雨', '小雨', '大雨', '阵雨', '雪', '大雪', '雷雨'];
    const en: string[] = [
      'Clear', 'Partly cloudy', 'Overcast', 'Fog', 'Drizzle', 'Rain', 'Heavy rain', 'Showers', 'Snow', 'Heavy snow',
      'Thunder'
    ];
    const table: string[] = language.startsWith('zh') ? zh : en;
    return table[condition];
  }
}
