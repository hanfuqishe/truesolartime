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

  /** 取二进制（瓦片、探测图片）：非 2xx / 网络错误一律 null。 */
  static async getBytes(url: string, headers: Record<string, string>, timeoutMs: number): Promise<Uint8Array | null> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (response.responseCode !== http.ResponseCode.OK) {
        return null;
      }
      return new Uint8Array(response.result as ArrayBuffer);
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      console.warn(`GET ${url} failed: ${failure.code} ${failure.message}`);
      return null;
    } finally {
      request.destroy();
    }
  }
}
