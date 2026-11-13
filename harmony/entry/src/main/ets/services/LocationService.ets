/**
 * 定位与权限。
 *
 * 只用 APPROXIMATELY_LOCATION（粗定位）：真太阳时只依赖经度，几公里的误差
 * 对应的时间差不到 1 秒，没必要为精确定位多要一个权限。
 */

import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class GeoPoint {
  latitude: number;
  longitude: number;

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

/** 一次取坐标的结果：失败时带上系统给的错误码，方便界面给出可操作提示。 */
export class LocationAttempt {
  point: GeoPoint | null;
  code: number;

  constructor(point: GeoPoint | null, code: number) {
    this.point = point;
    this.code = code;
  }
}

/** 系统「位置」总开关没打开时，鸿蒙定位接口返回的错误码。 */
const ERROR_LOCATION_SWITCH_OFF: number = 3301100;

const LOCATION_PERMISSIONS: Permissions[] = [
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION'
];

export class LocationService {
  /** 申请定位权限；已授权时立即返回 true。 */
  static async ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(context, LOCATION_PERMISSIONS);
      for (let index = 0; index < result.authResults.length; index++) {
        if (result.authResults[index] === 0) {
          return true;
        }
      }
      return false;
    } catch (error) {
      return false;
    }
  }

  static async hasPermission(): Promise<boolean> {
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = await LocationService.selfTokenId();
      const status: abilityAccessCtrl.GrantStatus =
        await manager.checkAccessToken(tokenId, 'ohos.permission.APPROXIMATELY_LOCATION');
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      return false;
    }
  }

  private static async selfTokenId(): Promise<number> {
    const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    );
    return info.appInfo.accessTokenId;
  }

  /** 取一次当前坐标；失败或超时返回 null。 */
  static async current(): Promise<GeoPoint | null> {
    return (await LocationService.attempt()).point;
  }

  /** 同上，但把失败原因（系统错误码）一并带出来。 */
  static async attempt(): Promise<LocationAttempt> {
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      scenario: geoLocationManager.LocationRequestScenario.UNSET,
      maxAccuracy: 100,
      timeoutMs: 10000
    };
    try {
      const location: geoLocationManager.Location = await geoLocationManager.getCurrentLocation(request);
      return new LocationAttempt(new GeoPoint(location.latitude, location.longitude), 0);
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      console.warn(`getCurrentLocation failed: ${failure.code} ${failure.message}`);
      return new LocationAttempt(null, failure.code);
    }
  }

  /** 系统「位置」开关没打开（下拉控制中心里的「位置」磁贴）。 */
  static isSwitchOff(code: number): boolean {
    return code === ERROR_LOCATION_SWITCH_OFF;
  }
}
