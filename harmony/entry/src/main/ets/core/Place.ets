/**
 * 甯哥敤鍩庡競涓庡綋鍓嶉€夊畾鐨勮娴嬬偣銆?
 */

export enum PlaceSource {
  DEFAULT = 0,
  GPS = 1,
  MANUAL = 2
}

/** 常用城市分组（按大洲）。 */
export enum PlaceRegion {
  ASIA = 'asia',
  EUROPE = 'europe',
  AFRICA = 'africa',
  NORTH_AMERICA = 'north_america',
  SOUTH_AMERICA = 'south_america',
  OCEANIA = 'oceania',
  ANTARCTICA = 'antarctica'
}

export class Place {
  latitude: number;
  longitude: number;
  source: PlaceSource;
  /** 鐢ㄦ埛鑷畾涔夊悕瀛楋紱鍐呯疆鍩庡競涓虹┖锛屾敼鐢?labelKey 璧板璇█璧勬簮銆?*/
  label: string;
  /** 鍐呯疆鍩庡競鐨勫璇█璧勬簮閿紝渚嬪 "city_beijing"銆?*/
  labelKey: string;
  /**
   * 鍐呯疆鍩庡競鎵€灞炲浗瀹?鍦板尯锛圛SO 3166-1 alpha-2锛屽皬鍐欙級锛屼緥濡?`cn` / `hk` / `us`銆?
   *
   * 鏈変簡瀹冿紝閫変腑棰勮鍩庡競鍚?ZoneTable 鑳?*褰撳満**绠楀嚭鏍囧噯鏃跺尯锛屼笉蹇呯瓑閫嗗湴鐞嗙紪鐮佸洖鏉ャ€?
   * 绌轰覆琛ㄧず鏈煡锛圙PS / 鎵嬪姩鍧愭爣锛夛紝鐢遍€嗗湴鐞嗙粨鏋滆ˉ銆?
   */
  countryCode: string;
  /** 常用城市所在大洲（仅 PRESETS 使用）。 */
  region: PlaceRegion;

  constructor(latitude: number, longitude: number, source: PlaceSource, label: string, labelKey: string,
      countryCode: string = '', region: PlaceRegion = PlaceRegion.ASIA) {
    this.latitude = latitude;
    this.longitude = longitude;
    this.source = source;
    this.label = label;
    this.labelKey = labelKey;
    this.countryCode = countryCode;
    this.region = region;
  }

  static readonly DEFAULT: Place = new Place(39.9042, 116.4074, PlaceSource.DEFAULT, '', 'city_beijing', 'cn');

  static readonly PRESETS: Place[] = [
    new Place(39.9042, 116.4074, PlaceSource.MANUAL, '', 'city_beijing', 'cn', PlaceRegion.ASIA),
    new Place(31.2304, 121.4737, PlaceSource.MANUAL, '', 'city_shanghai', 'cn', PlaceRegion.ASIA),
    new Place(23.1291, 113.2644, PlaceSource.MANUAL, '', 'city_guangzhou', 'cn', PlaceRegion.ASIA),
    new Place(22.5431, 114.0579, PlaceSource.MANUAL, '', 'city_shenzhen', 'cn', PlaceRegion.ASIA),
    new Place(30.5728, 104.0668, PlaceSource.MANUAL, '', 'city_chengdu', 'cn', PlaceRegion.ASIA),
    new Place(34.3416, 108.9398, PlaceSource.MANUAL, '', 'city_xian', 'cn', PlaceRegion.ASIA),
    new Place(45.8038, 126.5350, PlaceSource.MANUAL, '', 'city_harbin', 'cn', PlaceRegion.ASIA),
    new Place(52.9721, 122.5388, PlaceSource.MANUAL, '', '', 'cn', PlaceRegion.ASIA),
    new Place(48.3669, 134.2895, PlaceSource.MANUAL, '', '', 'cn', PlaceRegion.ASIA),
    new Place(43.8256, 87.6168, PlaceSource.MANUAL, '', 'city_urumqi', 'cn', PlaceRegion.ASIA),
    new Place(39.4704, 75.9898, PlaceSource.MANUAL, '', '', 'cn', PlaceRegion.ASIA),
    new Place(29.6520, 91.1721, PlaceSource.MANUAL, '', 'city_lhasa', 'cn', PlaceRegion.ASIA),
    new Place(22.3193, 114.1694, PlaceSource.MANUAL, '', 'city_hongkong', 'hk', PlaceRegion.ASIA),
    new Place(16.8343, 112.3388, PlaceSource.MANUAL, '', '', 'cn', PlaceRegion.ASIA),
    new Place(25.7459, 123.4776, PlaceSource.MANUAL, '', '', 'cn', PlaceRegion.ASIA),
    new Place(35.6762, 139.6503, PlaceSource.MANUAL, '', '', 'jp', PlaceRegion.ASIA),
    new Place(37.5665, 126.9780, PlaceSource.MANUAL, '', '', 'kr', PlaceRegion.ASIA),
    new Place(39.0392, 125.7625, PlaceSource.MANUAL, '', '', 'kp', PlaceRegion.ASIA),
    new Place(43.1155, 131.8855, PlaceSource.MANUAL, '', '', 'ru', PlaceRegion.ASIA),
    new Place(1.3521, 103.8198, PlaceSource.MANUAL, '', '', 'sg', PlaceRegion.ASIA),
    new Place(13.7563, 100.5018, PlaceSource.MANUAL, '', '', 'th', PlaceRegion.ASIA),
    new Place(17.9757, 102.6331, PlaceSource.MANUAL, '', '', 'la', PlaceRegion.ASIA),
    new Place(-6.2088, 106.8456, PlaceSource.MANUAL, '', '', 'id', PlaceRegion.ASIA),
    new Place(28.6139, 77.2090, PlaceSource.MANUAL, '', '', 'in', PlaceRegion.ASIA),
    new Place(25.2048, 55.2708, PlaceSource.MANUAL, '', '', 'ae', PlaceRegion.ASIA),
    new Place(41.0082, 28.9784, PlaceSource.MANUAL, '', '', 'tr', PlaceRegion.ASIA),
    new Place(55.7558, 37.6173, PlaceSource.MANUAL, '', '', 'ru', PlaceRegion.EUROPE),
    new Place(51.5074, -0.1278, PlaceSource.MANUAL, '', '', 'gb', PlaceRegion.EUROPE),
    new Place(48.8566, 2.3522, PlaceSource.MANUAL, '', '', 'fr', PlaceRegion.EUROPE),
    new Place(52.5200, 13.4050, PlaceSource.MANUAL, '', '', 'de', PlaceRegion.EUROPE),
    new Place(41.9028, 12.4964, PlaceSource.MANUAL, '', '', 'it', PlaceRegion.EUROPE),
    new Place(40.4168, -3.7038, PlaceSource.MANUAL, '', '', 'es', PlaceRegion.EUROPE),
    new Place(64.1466, -21.9426, PlaceSource.MANUAL, '', '', 'is', PlaceRegion.EUROPE),
    new Place(68.9700, 33.0800, PlaceSource.MANUAL, '', '', 'ru', PlaceRegion.EUROPE),
    new Place(30.0444, 31.2357, PlaceSource.MANUAL, '', '', 'eg', PlaceRegion.AFRICA),
    new Place(-33.9249, 18.4241, PlaceSource.MANUAL, '', '', 'za', PlaceRegion.AFRICA),
    new Place(-1.2921, 36.8219, PlaceSource.MANUAL, '', '', 'ke', PlaceRegion.AFRICA),
    new Place(-1.9441, 30.0619, PlaceSource.MANUAL, '', '', 'rw', PlaceRegion.AFRICA),
    new Place(6.5244, 3.3792, PlaceSource.MANUAL, '', '', 'ng', PlaceRegion.AFRICA),
    new Place(21.3069, -157.8583, PlaceSource.MANUAL, '', '', 'us', PlaceRegion.NORTH_AMERICA),
    new Place(34.0522, -118.2437, PlaceSource.MANUAL, '', '', 'us', PlaceRegion.NORTH_AMERICA),
    new Place(40.7128, -74.0060, PlaceSource.MANUAL, '', '', 'us', PlaceRegion.NORTH_AMERICA),
    new Place(41.8781, -87.6298, PlaceSource.MANUAL, '', '', 'us', PlaceRegion.NORTH_AMERICA),
    new Place(19.4326, -99.1332, PlaceSource.MANUAL, '', '', 'mx', PlaceRegion.NORTH_AMERICA),
    new Place(49.2827, -123.1207, PlaceSource.MANUAL, '', '', 'ca', PlaceRegion.NORTH_AMERICA),
    new Place(-22.9068, -43.1729, PlaceSource.MANUAL, '', '', 'br', PlaceRegion.SOUTH_AMERICA),
    new Place(-23.5505, -46.6333, PlaceSource.MANUAL, '', '', 'br', PlaceRegion.SOUTH_AMERICA),
    new Place(-34.6037, -58.3816, PlaceSource.MANUAL, '', '', 'ar', PlaceRegion.SOUTH_AMERICA),
    new Place(-12.0464, -77.0428, PlaceSource.MANUAL, '', '', 'pe', PlaceRegion.SOUTH_AMERICA),
    new Place(-33.8688, 151.2093, PlaceSource.MANUAL, '', '', 'au', PlaceRegion.OCEANIA),
    new Place(-31.9523, 115.8613, PlaceSource.MANUAL, '', '', 'au', PlaceRegion.OCEANIA),
    new Place(-36.8485, 174.7633, PlaceSource.MANUAL, '', '', 'nz', PlaceRegion.OCEANIA),
    new Place(-80.4169, 77.1161, PlaceSource.MANUAL, '', 'city_kunlun', 'cn', PlaceRegion.ANTARCTICA)
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
   * 璇ヨ娴嬬偣鑻ユ濂芥槸銆屽父鐢ㄥ煄甯傘€嶉噷鐨勬煇涓璁剧偣锛岃繑鍥為偅涓璁剧偣锛涙墜宸ュ潗鏍囦笌 GPS 杩斿洖 null銆?
   *
   * 绛変环浜?Android 鐨?`Place.labelResName != null`锛氶璁惧煄甯傛墠鏈夊煄甯傚悕鍙樉绀猴紝
   * 鎵嬪伐杈撳叆 / GPS 瀹氫綅鍙兘绛夐€嗗湴鐞嗙粨鏋滐紝绛変笉鍒板氨鏄剧ず鍗犱綅绗︺€?
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
