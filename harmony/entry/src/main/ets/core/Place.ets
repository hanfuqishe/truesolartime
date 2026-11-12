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

  constructor(latitude: number, longitude: number, source: PlaceSource, label: string, labelKey: string) {
    this.latitude = latitude;
    this.longitude = longitude;
    this.source = source;
    this.label = label;
    this.labelKey = labelKey;
  }

  static readonly DEFAULT: Place = new Place(39.9042, 116.4074, PlaceSource.DEFAULT, '', 'city_beijing');

  static readonly PRESETS: Place[] = [
    new Place(39.9042, 116.4074, PlaceSource.MANUAL, '', 'city_beijing'),
    new Place(31.2304, 121.4737, PlaceSource.MANUAL, '', 'city_shanghai'),
    new Place(23.1291, 113.2644, PlaceSource.MANUAL, '', 'city_guangzhou'),
    new Place(22.5431, 114.0579, PlaceSource.MANUAL, '', 'city_shenzhen'),
    new Place(30.5728, 104.0668, PlaceSource.MANUAL, '', 'city_chengdu'),
    new Place(34.3416, 108.9398, PlaceSource.MANUAL, '', 'city_xian'),
    new Place(45.8038, 126.5350, PlaceSource.MANUAL, '', 'city_harbin'),
    new Place(43.8256, 87.6168, PlaceSource.MANUAL, '', 'city_urumqi'),
    new Place(29.6520, 91.1721, PlaceSource.MANUAL, '', 'city_lhasa'),
    new Place(22.3193, 114.1694, PlaceSource.MANUAL, '', 'city_hongkong')
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
}
