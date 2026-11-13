import { bundleManager } from '@kit.AbilityKit';

/**
 * 应用自身的包信息。
 *
 * 版本号取自 AppScope/app.json5 的 versionName，界面里不再写死——两个平台统一用同一个版本号，
 * 也不会出现「关于页写着旧版本、包里却是新版本」的情况。
 */
export class AppInfo {
  private static cached: string = '';

  static versionName(): string {
    if (AppInfo.cached.length > 0) {
      return AppInfo.cached;
    }
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      AppInfo.cached = info.versionName;
    } catch (error) {
      AppInfo.cached = '';
    }
    return AppInfo.cached;
  }
}
