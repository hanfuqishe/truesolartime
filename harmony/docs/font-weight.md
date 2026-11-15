# 系统「字体大小 / 字体粗细」对卡片的影响，以及自带字体能不能躲开（实测）

测试环境：HarmonyOS 6.0.0（API 20）模拟器 `HRM6`（1280×2832 / 560dpi）。
用模拟器 **设置 → 显示和亮度 → 字体大小和界面缩放** 里的两个滑杆；滑杆的数值可以直接从
`uitest dumpLayout` 的 Slider 节点读到（`字体大小 2.0 = 标准`、`字体粗细 1.0 = 标准`、`1.5 = 粗`）。
每次改完都 `aa force-stop` + `aa start` 重启应用再截图。

量法（与 Android / iOS 同一套口径）：卡片 bbox 取橙色底像素的行剖面；墨迹 = 卡内橙色范围里
`G>165 且 B>165` 的像素；三带按卡内相对位置分组（label / date / hourly）。

## 1. 字体大小：没有观察到影响

| 字体大小 | 卡片 | label 墨迹 | date 墨迹 | hourly 墨迹 |
|---|---|---|---|---|
| 2.0（标准） | 1167×673 | 7848 | 5543 | 23383 |
| 5.0（特大） | 1167×667 | 7848 | 5543 | 23383 |

两行都在「字体粗细 = 1.5」下量：粗细相同、字号从标准拨到特大，三段墨迹**一个像素都不差**。
需要注意：**同屏系统设置页自己的字号也没变**（`字体大小` / `字体粗细` 两个标签的 bounds 在
2.0 与 5.0 两档完全一致），所以这条只能说「拨到特大后没有任何可观察变化」，不能算证明了
「卡片对字号缩放免疫」——很可能是这个模拟器镜像没有真正下发字号。卡片字号都是数字字面量，
且时钟字号按栏宽反推，即使系统字号生效，卡片也应是最后受影响的部分。

## 2. 字体粗细：系统字体下卡片被明显描粗

| 字体粗细 | 卡片 | label 墨迹 | date 墨迹 | clock 墨迹 |
|---|---|---|---|---|
| 1.0（标准） | 1167×673 | 5298 | 3161 | 22749 |
| 1.5（粗） | 1167×667 | **7848（+48%）** | **5543（+75%）** | **30978（+36%）** |

卡片宽度不变，各段文字的 x 范围只增 2~9px（描边外扩）、步进基本不变 —— 与华为 EMUI 的
`font_weight_scale` 一样是**渲染层描粗**，不是换字面。截图：`hx-base.jpeg` / `hx-bold.jpeg`。

## 3. 自带字体：**能**躲开（前提是注册位置对了）

做法：把 Noto Sans SC 的两个子集（Regular / Medium，与 Android 版同一份，SIL OFL 1.1）
放进 `entry/src/main/resources/rawfile/font/`，在 **`pages/Index.aboutToAppear()`** 里
`font.registerFont({ familyName, familySrc: $rawfile('font/xxx.ttf') })`，
卡片文本全部 `.fontFamily(...)`，并把行高钉到运行时量出的系统字体行盒比例（见 §4）。

结果（同一份构建，只拨滑杆）：

| 字体粗细 | 卡片 | label 墨迹 | hourly 墨迹 |
|---|---|---|---|
| 1.0（标准） | 1167×671 | 5543 | 21174 |
| 1.5（粗） | 1167×667 | **5548（+0.09%）** | **21242（+0.32%）** |

对照系统字体的 +48% / +75%，自带字体的卡片笔画**基本不再随滑杆变化**（残差是亚像素抗锯齿）。
截图：`hx-f3-base.jpeg` / `hx-f3-bold.jpeg`。

### 3.1 坑：在 UIAbility 里注册不生效

第一版把 `font.registerFont` 放在 `EntryAbility.onWindowStageCreate()` 里（`loadContent` 之前），
照常编译、不报错，但**卡片仍然是系统字面**：
同一段 `UTC+8` 在系统字体与"自带字体"两版里墨迹 208/208 px、宽度 119/119 px —— 完全没换。
把注册搬到页面的 `aboutToAppear()` 后，同一段文字立刻变成 156 px 墨迹 / 242 px 宽。
所以注册必须放在**页面侧**（`registerFont` 是同步 API，在 `aboutToAppear` 里调用即可，
第一帧就用自带字面，不会闪一帧系统字体）。

### 3.2 残余：时钟字号的自适应仍然量的是系统字体

`clockWidthRatio()` 用 `MeasureUtils.measureTextSize` 量「00:00」的宽度来反推时钟字号。
这个 API **不认** `font.registerFont` 注册的字族（传了 `fontFamily` 也没用），所以系统粗细一变，
量出来的宽度就变 → 冷启动时若粗细 ≠ 标准，时钟数字会小约 4%（clock 带高 113 → 108px），
卡片高度跟着 671 → 667。文字笔画本身已完全免疫，这一条只影响「数字撑满一栏」的拟合精度；
彻底解决要靠隐藏 Text + `onAreaChange` 实测宽度，本期没做。

## 4. 行高钉死（不写死数字）

自带字体的垂直度量被改写成 1.20em（`hhea/typo`），与系统字体不同，行盒会变 → 卡片高度会变。
做法：

- `systemLineBoxRatio()`：用 `MeasureUtils.measureTextSize({ textContent: 'Hg', fontSize: 100 })`
  的**高度** ÷ `vp2px(100)`，得到**系统字体自己**的「行盒 / 字号」比例（只量一次并缓存）；
- `cardLineHeight(size)` = `字号 × 该比例`，卡片里每个 `Text` 都 `.lineHeight(...)`。

实测：系统字体 673px 高 → 自带字体 671px 高（残差 2px = 0.3%，来自比例取整）。

## 5. 产物与体积

| 项 | 值 |
|---|---|
| 字体文件 | `entry/src/main/resources/rawfile/font/card_sans_regular.ttf`（204,188 B）、`card_sans_medium.ttf`（1,248,496 B） |
| 字族名 | `SolartimeCardRegular`（Normal）、`SolartimeCardMedium`（Medium）—— 两个字面分开注册，避免系统在缺字重时合成粗体 |
| 注册位置 | `entry/src/main/ets/pages/Index.ets` 的 `aboutToAppear()`；名字常量在 `common/CardFont.ets` |
| HAP 体积 | 841,349 B → **2,307,809 B**（+1,466,460 B，+1.4 MB） |
| 生效范围 | 卡片区（大卡片 / 太阳卡 / 地图卡）的 26 个 `Text`；页头、设置页保持系统字体 |
