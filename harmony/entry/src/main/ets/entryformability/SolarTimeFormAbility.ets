import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppStore } from '../services/Store';
import { CardService } from '../services/CardService';

/**
 * 桌面卡片的生命周期入口。
 *
 * onAddForm / onUpdateForm 必须同步拿到数据，因此这里只用缓存的天气与关键时间；
 * 真正的取数在后台补一次，取到后再推给卡片。
 */
export default class SolarTimeFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    AppStore.init(this.context);
    const formId: string = SolarTimeFormAbility.formIdOf(want);
    if (formId.length > 0) {
      AppStore.addFormId(formId);
    }
    SolarTimeFormAbility.refreshLater();
    return formBindingData.createFormBindingData(CardService.buildData());
  }

  onUpdateForm(formId: string): void {
    AppStore.init(this.context);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(CardService.buildData()))
      .catch((error: BusinessError) => {
        console.warn(`onUpdateForm ${formId} failed: ${error.code} ${error.message}`);
      });
    SolarTimeFormAbility.refreshLater();
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片上没有常驻进程：点一下卡片就重新取数并回推（卡片里的真太阳时是快照）。
    AppStore.init(this.context);
    CardService.refresh().catch((error: BusinessError) => {
      console.warn(`onFormEvent refresh failed: ${error.code} ${error.message}`);
    });
  }

  onRemoveForm(formId: string): void {
    AppStore.init(this.context);
    AppStore.removeFormId(formId);
  }

  onFormAcquired(formId: string, want: Want): void {
    AppStore.init(this.context);
    AppStore.addFormId(formId);
  }

  private static formIdOf(want: Want): string {
    const parameters: Record<string, Object> = want.parameters === undefined ? {} : want.parameters;
    const identity: Object | undefined = parameters[formInfo.FormParam.IDENTITY_KEY];
    return identity === undefined || identity === null ? '' : String(identity);
  }

  /** 卡片进程里不能长时间占用，取数交给异步任务，取到后就地推一次。 */
  private static refreshLater(): void {
    setTimeout(() => {
      CardService.refresh().catch((error: BusinessError) => {
        console.warn(`card refresh failed: ${error.code} ${error.message}`);
      });
    }, 300);
  }
}
