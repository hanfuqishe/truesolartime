# 卡片自带字体（Noto Sans SC 子集，两个字面）

`app/src/main/res/font/` 下是 App 自带的卡片字体，只给**卡片内**和**桌面小组件**的文本用
（`ui/CardDensity.kt` 的 `cardTextStyle`、`res/values/styles.xml` 里的小组件样式）；设置页、页头
仍用系统字体，便于对照。

| 文件 | 字面 | 大小 | 用途 |
|---|---|---|---|
| `card_sans_medium.ttf` | Noto Sans SC **Medium (500)** | 1,248,496 B | 卡片里请求 Medium 的文本（时钟数字、各标签、「地区名」）+ 小组件全部文字 |
| `card_sans_regular.ttf` | Noto Sans SC **Regular (400)** | 204,188 B | 卡片里请求 Normal 的文本（日期行、白昼行、经纬度、地图版权） |

## 1. 为什么自带字体

华为 ELS-AN00 / EMUI-HarmonyOS 的「字体粗细」滑杆写的是 `Settings.System.font_weight_scale`，
它**不换字面**，而是在渲染层把笔画描粗：卡片 bbox 与各段文字带的 x 范围逐像素不变，只有墨迹上涨
（实测 system 字体 0.79 → 0.88：label +9.6%、date +13.6%）。用系统字族时换字重也躲不掉 ——
系统 `sans-serif` 在这一段只暴露两三个字面，把请求字重压下去只会从 +10% 翻到 −11%。

自带字体走 App 自己的 Typeface 与 `res/font` 资源，系统那层描粗管不到。实测（同一台机器、用真滑杆
把 `font_weight_scale` 从 0.79 拨到 0.88）：卡片三段文字带（label / date / hourly）的逐像素差异
**全部为 0**，只有时钟数字因为时间变了；而改造前（系统字体）同样两档的差异是 2770 / 2236 / 2864 像素。

## 2. 来源与许可证

| 项 | 值 |
|---|---|
| 字族 | **Noto Sans SC**（SIL Open Font License 1.1：可再分发、可商用、可嵌入、可子集化） |
| 上游文件 | `NotoSansSC[wght].ttf`（可变字体，wght 100–900，默认实例 100 = Thin） |
| 下载地址 | https://github.com/google/fonts/tree/main/ofl/notosanssc （经 jsDelivr 镜像 `https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf` 获取） |
| 上游大小 / SHA-256 | 17,772,300 B / `a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da` |
| 许可证原文 | [`android/FONT-OFL.txt`](../FONT-OFL.txt)（与上游 `ofl/notosanssc/OFL.txt` 一致） |
| 派生产物 | 静态实例 `wght=400` / `wght=500`，再按字符子集化（`--layout-features='*'`） |

复现命令（`py -3 -m pip install fonttools` 之后）：

```powershell
py -3 -m fontTools.varLib.instancer "NotoSansSC[wght].ttf" wght=400 -o NotoSansSC-Regular.ttf
py -3 -m fontTools.varLib.instancer "NotoSansSC[wght].ttf" wght=500 -o NotoSansSC-Medium.ttf
py -3 -m fontTools.subset NotoSansSC-Regular.ttf --text-file=chars_regular.txt `
    --layout-features='*' --name-IDs='1,2,3,4,5,6' --output-file=card_sans_regular.ttf
py -3 -m fontTools.subset NotoSansSC-Medium.ttf  --text-file=chars_medium.txt `
    --layout-features='*' --name-IDs='1,2,3,4,5,6' --output-file=card_sans_medium.ttf
```

`--layout-features='*'` 不能省：卡片时钟用 `fontFeatureSettings = "tnum"` 把数字做成等宽，
`tnum` 在 GSUB/GPOS 里；裁掉它会让「88:88」的宽度随时刻变化，`HeroClock` 按宽度反推字号
的逻辑会跟着抖。

## 3. 收了哪些字

`chars_regular.txt`（567 个码位）—— **只给 Normal 字重**用，固定文案够用：

1. `res/values*/**.xml` 里所有字符串值 + `android:text` / `contentDescription`（三个语言版本，
   含 `shichen_names`、`weekdays`、天气词、20 个预设城市名等）；
2. `app/src/main/java` 下所有 Kotlin 字符串字面量（`CityIndex.RAW` 的城市名、中文数字等）；
3. ASCII 可打印字符 + UI 会用到的符号（`·°′″−–—…「」《》、。：；！？（）` 等）。

`chars_medium.txt`（4000 个码位 = 上面 567 个 ∪ **GB2312 一级汉字 3755 个**）—— Medium 字重
还要负责**运行期**文本：卡片顶部标签行的「地区名」（`districtName`）来自定位 / 逆地理编码，
字符集不封闭。实测取 20 个典型行政区名（`上海市宝山区`/`杭州市西湖区`/`北京市朝阳区` …
`巴音郭楞蒙古自治州`），只收 UI 那 567 字时 **17/20 个名字都有缺字**，缺的字会回落到**系统字体**
—— 也就是恰好在这些字上又会被华为描粗。所以 Medium 字面必须把常用汉字整段带上。

体积代价：Medium 1.19 MB + Regular 0.19 MB ≈ **1.39 MB**，release APK 2.00 MB → **2.88 MB**。
若以后确认「地区名」可以接受回落，把 GB2312 那一档去掉重新子集即可，其余流程不变。

## 4. 桌面小组件（RemoteViews）

小组件只能走 XML：`res/values/styles.xml` 里 `WidgetClockMain` / `WidgetSunTime` / `WidgetHourLabel`
等样式与各 `TextView` 都写了 `android:fontFamily="@font/card_sans_medium"`（统一 Medium：小组件
原本就一半是 `sans-serif-medium`，混用两个字重会让同一屏里粗细不一）。

- **API 26+ 可用**：`@font/` 资源在 XML 里从 Android 8.0 起被接受，RemoteViews 用 App 自己的
  Resources 解析，实测在 ELS-AN00（Android 12 / API 31）桌面上确实换成了自带字形。
- **API 24/25**：`android:fontFamily` 指向资源时框架取不到字符串（`TypedArray.getString` 对
  reference 返回 null），TextView 退回默认族 —— 不崩，只是没换字体。
