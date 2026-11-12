/**
 * 极简 HTTP GET 封装：失败一律返回 null，调用方据此沿用缓存。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class HttpUtil {
  static async getText(url: string, headers: Record<string, string>, timeoutMs: number): Promise<string | null> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== http.ResponseCode.OK) {
        return null;
      }
      return response.result as string;
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      console.warn(`GET ${url} failed: ${failure.code} ${failure.message}`);
      return null;
    } finally {
      request.destroy();
    }
  }
}
