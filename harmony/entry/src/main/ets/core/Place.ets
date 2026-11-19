/**
 * 常用城市与当前选定的观测点。
 */

export enum PlaceSource {
  DEFAULT = 0,
  GPS = 1,
  MANUAL = 2
}

export class Place {
  latitude: number;
  longitude: number;
  source: PlaceSource;
  /** 用户自定义名字；内置城市为空，改用 labelKey 走多语言资源。 */
  label: string;
  /** 内置城市的多语言资源键，例如 "city_beijing"。 */
  labelKey: string;
  /**
   * 内置城市所属国家/地区（ISO 3166-1 alpha-2，小写），例如 `cn` / `hk` / `us`。
   *
   * 有了它，选中预设城市后 ZoneTable 能**当场**算出标准时区，不必等逆地理编码回来。
   * 空串表示未知（GPS / 手动坐标），由逆地理结果补。
   */
  countryCode: string;

  constructor(latitude: number, longitude: number, source: PlaceSource, label: string, labelKey: string,
      countryCode: string = '') {
    this.latitude = latitude;
    this.longitude = longitude;
    this.source = source;
    this.label = label;
    this.labelKey = labelKey;
    this.countryCode = countryCode;
  }

  static readonly DEFAULT: Place = new Place(39.9042, 116.4074, PlaceSource.DEFAULT, '', 'city_beijing', 'cn');

  static readonly PRESETS: Place[] = [
    new Place(39.9042, 116.4074, PlaceSource.MANUAL, '', 'city_beijing', 'cn'),
    new Place(31.2304, 121.4737, PlaceSource.MANUAL, '', 'city_shanghai', 'cn'),
    new Place(23.1291, 113.2644, PlaceSource.MANUAL, '', 'city_guangzhou', 'cn'),
    new Place(22.5431, 114.0579, PlaceSource.MANUAL, '', 'city_shenzhen', 'cn'),
    new Place(30.5728, 104.0668, PlaceSource.MANUAL, '', 'city_chengdu', 'cn'),
    new Place(34.3416, 108.9398, PlaceSource.MANUAL, '', 'city_xian', 'cn'),
    new Place(45.8038, 126.5350, PlaceSource.MANUAL, '', 'city_harbin', 'cn'),
    new Place(43.8256, 87.6168, PlaceSource.MANUAL, '', 'city_urumqi', 'cn'),
    new Place(29.6520, 91.1721, PlaceSource.MANUAL, '', 'city_lhasa', 'cn'),
    new Place(22.3193, 114.1694, PlaceSource.MANUAL, '', 'city_hongkong', 'hk'),
    // 境外常用城市：按 UTC 偏移从西到东排。名字由 Settings.cityLabel 查 CityIndex 得到
    // （core/CityIndex 里都有这些城市），所以 label 与 labelKey 留空，随界面语言变化。
    new Place(21.3069, -157.8583, PlaceSource.MANUAL, '', '', 'us'),   // 檀香山
    new Place(34.0522, -118.2437, PlaceSource.MANUAL, '', '', 'us'),   // 洛杉矶
    new Place(40.7128, -74.0060, PlaceSource.MANUAL, '', '', 'us'),    // 纽约
    new Place(51.5074, -0.1278, PlaceSource.MANUAL, '', '', 'gb'),     // 伦敦
    new Place(48.8566, 2.3522, PlaceSource.MANUAL, '', '', 'fr'),      // 巴黎
    new Place(25.2048, 55.2708, PlaceSource.MANUAL, '', '', 'ae'),     // 迪拜
    new Place(28.6139, 77.2090, PlaceSource.MANUAL, '', '', 'in'),     // 新德里
    new Place(35.6762, 139.6503, PlaceSource.MANUAL, '', '', 'jp'),    // 东京
    new Place(1.3521, 103.8198, PlaceSource.MANUAL, '', '', 'sg'),     // 新加坡
    new Place(-33.8688, 151.2093, PlaceSource.MANUAL, '', '', 'au'),   // 悉尼
    // 极圈城市：验证极昼／极夜。名字由离线城市表（core/CityIndex）给出，跟其他境外城市一样
    // 随界面语言变化；国家码只用来定标准时区。
    // 摩尔曼斯克（68.97°N 33.08°E）：俄罗斯，北极圈内，夏季极昼、冬季极夜；
    //   ru + 经度 33.08°E < 40°E → UTC+3（莫斯科时间）。
    new Place(68.9700, 33.0800, PlaceSource.MANUAL, '', '', 'ru'),
    // 中山站（69.37°S 76.38°E）：中国南极考察站，南极圈内；显式用 cn → UTC+8
    //（站上按中国站务惯例使用北京时间；ZoneTable 没有 aq 条目，写 aq 会按经度取整成 +5）。
    new Place(-69.3700, 76.3800, PlaceSource.MANUAL, '', '', 'cn'),
    // 三端同步补到 24 个（4 列 × 6 行整）：开罗、里约热内卢，坐标与 Android 逐位一致。
    new Place(30.0444, 31.2357, PlaceSource.MANUAL, '', '', 'eg'),
    new Place(-22.9068, -43.1729, PlaceSource.MANUAL, '', '', 'br')
  ];

  static readonly MIN_LATITUDE: number = -90.0;
  static readonly MAX_LATITUDE: number = 90.0;
  static readonly MIN_LONGITUDE: number = -180.0;
  static readonly MAX_LONGITUDE: number = 180.0;

  static isValidLatitude(value: number): boolean {
    return !isNaN(value) && value >= Place.MIN_LATITUDE && value <= Place.MAX_LATITUDE;
  }

  static isValidLongitude(value: number): boolean {
    return !isNaN(value) && value >= Place.MIN_LONGITUDE && value <= Place.MAX_LONGITUDE;
  }

  sameLocation(other: Place): boolean {
    return Math.abs(this.latitude - other.latitude) < 1e-6 && Math.abs(this.longitude - other.longitude) < 1e-6;
  }

  /**
   * 该观测点若正好是「常用城市」里的某个预设点，返回那个预设点；手工坐标与 GPS 返回 null。
   *
   * 等价于 Android 的 `Place.labelResName != null`：预设城市才有城市名可显示，
   * 手工输入 / GPS 定位只能等逆地理结果，等不到就显示占位符。
   */
  static presetOf(place: Place): Place | null {
    if (place.source === PlaceSource.GPS) {
      return null;
    }
    for (const preset of Place.PRESETS) {
      if (place.sameLocation(preset)) {
        return preset;
      }
    }
    return null;
  }
}
