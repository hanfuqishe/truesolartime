/**
 * 屏幕常亮：设置页里的开关落到 Window 上，应用在前台时不自动熄屏。
 *
 * 退到后台后系统照旧按「休眠」时间熄屏，这里不需要额外收尾；回到前台（onPageShow）
 * 再按当前偏好设一次，这样在设置页里改完立刻生效。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { AppStore } from './Store';

export class KeepAwake {
  static apply(context: common.UIAbilityContext | null): void {
    if (context === null) {
      return;
    }
    const enabled: boolean = AppStore.keepScreenOn();
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowKeepScreenOn(enabled).catch((error: BusinessError) => {
        console.warn(`keep screen on failed: ${error.code} ${error.message}`);
      });
    }).catch((error: BusinessError) => {
      console.warn(`get window failed: ${error.code} ${error.message}`);
    });
  }
}
