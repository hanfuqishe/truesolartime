/**
 * 卡片自带字体（Noto Sans SC 子集，SIL OFL 1.1）。
 *
 * 为什么要自带：HarmonyOS 系统设置里的「字体粗细」会在渲染层把系统字体的笔画描粗
 * （实测滑杆 1.0 → 1.5：卡片标签行墨迹 +48%、日期行 +75%）。
 * 自带字体走 App 自己的字族，理论上系统那层描粗管不到，卡片笔画才稳定。
 */
export const CARD_FONT_REGULAR: string = 'SolartimeCardRegular';
export const CARD_FONT_MEDIUM: string = 'SolartimeCardMedium';
