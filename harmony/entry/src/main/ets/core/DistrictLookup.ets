/**
 * 地名反查的「按地点换代」策略。
 *
 * 上一次请求卡住不能挡住新地点：每次新地点都递增 generation 并直接发请求，
 * 过期结果只按 generation 丢弃；只有「同一地点、超时窗口内」的重复触发才去重。
 */
export class DistrictLookupPolicy {
  /** 反查超时上限（毫秒）。 */
  static readonly LOOKUP_TIMEOUT_MILLIS: number = 6000;

  /** 新一代请求是否该发：generation 前进即发。 */
  static shouldStartNewRequest(currentGen: number, newGen: number): boolean {
    return newGen > currentGen;
  }

  /** 回调结果是否仍有效：只有本代结果能写入。 */
  static shouldAcceptResult(myGen: number, currentGen: number): boolean {
    return myGen === currentGen;
  }

  /**
   * 同一地点的重复触发是否该跳过（超时窗口内）。
   * 不同地点永远不跳过。
   */
  static shouldSkipDuplicate(samePlace: boolean, elapsedMillis: number): boolean {
    return samePlace && elapsedMillis >= 0 && elapsedMillis < DistrictLookupPolicy.LOOKUP_TIMEOUT_MILLIS;
  }
}
