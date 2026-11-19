/**
 * 甯哥敤鍩庡競涓庡綋鍓嶉€夊畾鐨勮娴嬬偣銆?
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
    // 澧冨甯哥敤鍩庡競锛氭寜 UTC 鍋忕Щ浠庤タ鍒颁笢鎺掋€傚悕瀛楃敱 Settings.cityLabel 鏌?CityIndex 寰楀埌
    // 锛坈ore/CityIndex 閲岄兘鏈夎繖浜涘煄甯傦級锛屾墍浠?label 涓?labelKey 鐣欑┖锛岄殢鐣岄潰璇█鍙樺寲銆?
    new Place(21.3069, -157.8583, PlaceSource.MANUAL, '', '', 'us'),   // 妾€棣欏北
    new Place(34.0522, -118.2437, PlaceSource.MANUAL, '', '', 'us'),   // 娲涙潐鐭?
    new Place(40.7128, -74.0060, PlaceSource.MANUAL, '', '', 'us'),    // 绾界害
    new Place(51.5074, -0.1278, PlaceSource.MANUAL, '', '', 'gb'),     // 浼︽暒
    new Place(48.8566, 2.3522, PlaceSource.MANUAL, '', '', 'fr'),      // 宸撮粠
    new Place(25.2048, 55.2708, PlaceSource.MANUAL, '', '', 'ae'),     // 杩嫓
    new Place(28.6139, 77.2090, PlaceSource.MANUAL, '', '', 'in'),     // 鏂板痉閲?
    new Place(35.6762, 139.6503, PlaceSource.MANUAL, '', '', 'jp'),    // 涓滀含
    new Place(1.3521, 103.8198, PlaceSource.MANUAL, '', '', 'sg'),     // 鏂板姞鍧?
    new Place(-33.8688, 151.2093, PlaceSource.MANUAL, '', '', 'au'),   // 鎮夊凹
    // 鏋佸湀鍩庡競锛氶獙璇佹瀬鏄硷紡鏋佸銆傚悕瀛楃敱绂荤嚎鍩庡競琛紙core/CityIndex锛夌粰鍑猴紝璺熷叾浠栧澶栧煄甯備竴鏍?
    // 闅忕晫闈㈣瑷€鍙樺寲锛涘浗瀹剁爜鍙敤鏉ュ畾鏍囧噯鏃跺尯銆?
    // 鎽╁皵鏇兼柉鍏嬶紙68.97掳N 33.08掳E锛夛細淇勭綏鏂紝鍖楁瀬鍦堝唴锛屽瀛ｆ瀬鏄笺€佸啲瀛ｆ瀬澶滐紱
    //   ru + 缁忓害 33.08掳E < 40掳E 鈫?UTC+3锛堣帿鏂鏃堕棿锛夈€?
    new Place(68.9700, 33.0800, PlaceSource.MANUAL, '', '', 'ru'),
    // 涓北绔欙紙69.37掳S 76.38掳E锛夛細涓浗鍗楁瀬鑰冨療绔欙紝鍗楁瀬鍦堝唴锛涙樉寮忕敤 cn 鈫?UTC+8
    //锛堢珯涓婃寜涓浗绔欏姟鎯緥浣跨敤鍖椾含鏃堕棿锛沍oneTable 娌℃湁 aq 鏉＄洰锛屽啓 aq 浼氭寜缁忓害鍙栨暣鎴?+5锛夈€?
    new Place(-80.4169, 77.1161, PlaceSource.MANUAL, '', 'city_kunlun', 'cn'),
    // 涓夌鍚屾琛ュ埌 24 涓紙4 鍒?脳 6 琛屾暣锛夛細寮€缃椼€侀噷绾︾儹鍐呭崲锛屽潗鏍囦笌 Android 閫愪綅涓€鑷淬€?
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
