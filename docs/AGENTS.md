# 协作约定（供 AI 助手与后续会话参考）

本文件记录本仓库长期有效的**协作约定**与**踩过的坑**，目的是让后续会话不必从零摸索。

---

## 1. 子任务（subagent）复用约定

**核心原则：新任务如果与之前某个子任务属于同一主题，直接把增量要求发给那个子任务，不要新建。**

理由：子任务结束后上下文仍在，用 `send_message` 继续时它记得之前的实测数据、文件结构、基线数字；
新建子任务则要重新交代一遍，既费钱又容易漏掉约束。

判断流程：

1. 这个任务跟之前哪个子任务**同主题 / 有承袭关系**（同一批文件、同一套实测基线）？
   - 有 → `send_message` 给那个子任务，只写**增量**（"接着上次的 XXX，再做 YYY"）。
   - 没有 → 新建 `subagent`，把上下文写全。
2. 跨平台同步类任务，优先发给做过同类同步的子任务（它们知道两端的文件结构）。
3. 真机验证类任务，优先发给手上已有测量脚本、且熟悉两台机器 ROM 怪癖的子任务。
4. 只有在「原子任务上下文已太杂」或「主题确实全新」时才另起炉灶。

**主题分组参考**（每轮会话结束后按实际情况更新）：

| 主题 | 需要知道的背景 |
|---|---|
| 字体 / 字重 / 字号 | Noto Sans SC 子集怎么来的、华为是渲染层描粗（`font_weight_scale`）、`CardDensity`/`CardFontMath`/`fitTextStyle` 的结构 |
| 卡片排版 / 档位 / 分隔线 | 四档退化规则（`SmallRowLayout.cityRowTier`）、小组件 `*_default` 两套 id、分隔线只在档 0 上延、地区与线留 6dp |
| iOS / 鸿蒙同步 | 两端目录结构、`ZoneTable`/`GeoRegion`、断言脚本（`Scripts/main.swift`、`tools/core-check.ts`） |
| 城市预设 | 20 城清单、`countryCode` 传递链（Preset → Place → 持久化 → 时区查表） |
| 真机验证 | 像素测量脚本、两台机器的 adb 用法、ROM 坑（见下） |

---

## 2. 硬性约束（改代码时必须遵守）

- **不要自行提升版本号**。版本号由 `version.properties` + 构建钩子自动递增（Android 打包成功后 +1）。
- **不要执行 git 命令**（除非明确要求）；改完留工作区，由负责人统一提交。
- **iOS 除非明确要求，否则不主动编译**（推送 `ios/**` 会自动触发 CI 打包）。
- **Compose 禁用 `BoxWithConstraints` / `SubcomposeLayout`**：首页宽屏分支是 `Modifier.height(IntrinsicSize.Max)`，
  在里面用会崩。需要测量宽度时用 `onSizeChanged` + `TextMeasurer`。
- 编码：改文件前先确认原文件的换行风格（CRLF/LF）与是否带 BOM，保持原样；中文注释用 UTF-8。
  **不要用 PowerShell 5.1 读写 UTF-8 源码**，会按 GB2312 解码导致整文件乱码（曾发生一次，只能整份重写）。

---

## 3. 设备与实测

| 设备 | serial | 备注 |
|---|---|---|
| 华为 ELS-AN00 | `MDX0220321044102` | HarmonyOS 4.2 / Android 12；density 物理 530 + override 450；1200×2640 |
| 红米 2312DRA50C | `58f87d90` | Android 16 / HyperOS；1220×2712 @480dpi |

- **所有 adb 命令必须带 `-s <serial>`**（两台可能同时在线，误操作会改到另一台）。
- 账号侧无 root，`run-as` 不可用（release 包），无法直接读写 App 私有数据。

### ROM 坑（实测）

- 华为：「字体粗细」滑杆改 `system font_weight_scale`（正常 **0.79**，不是 1.0），是**渲染层描粗**：
  字形/字距/bbox 不变，只把笔画描粗；`Configuration.fontWeightAdjustment` 恒为 300（与滑杆无关），
  `font_weight_scale_normal` 只是当前值的镜像，**不能当参照**。滑杆「离开页面才提交」。
- 华为：`settings delete` 某些键**不触发刷新**，改完要 `put` 回值或重启 App 才生效。
- 红米：`device_font_scale` 完全不驱动渲染，只有 `font_scale` 生效。
- 红米：`settings delete secure font_weight_adjustment` 不刷新，必须 `put 0` 才回落。

### 验收基线（像素口径，卡片内容区）

| 设备 | 卡片尺寸 | 备注 |
|---|---|---|
| 华为 | 1088×618 @(56,460) | 换 Noto 字体后曾变 648，钉行高后需回到 618 |
| 红米 | 1100×660 @(60,390) | 同上，曾变 678 |

测量工具：解 PNG 像素，量「卡片 bbox + 三段文字带（标签行/日期行/逐时行）的墨迹量与 x 范围」；
逐秒变化的时钟数字不计入不变量比较。

---

## 4. 构建与验证命令

```powershell
# Android
cd android
$env:JAVA_HOME="D:\tools\jdk-21"
.\gradlew.bat testReleaseUnitTest assembleRelease --no-daemon   # 基线用例数见下

# 鸿蒙
cd harmony
$env:PATH = "C:\Program Files\Huawei\DevEco Studio\tools\node;" + $env:PATH
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
# 自检：tools 目录下 node verify-core.js / node parse-ets.js / python check-ets.py

# iOS 核心自检（Windows 上可跑，SwiftUI 不行）
swiftc -O ios/TrueSolarTime/Core/*.swift ios/Scripts/main.swift -o $env:TEMP\tst.exe; & $env:TEMP\tst.exe
```

用例基线（随改动增长，以最新为准）：Android 157 条、鸿蒙 229 checks、iOS 138 项。

---

## 5. 已确定的产品决策（避免反复讨论）

- 三端主/次版本号统一，修订号各自独立，不要求一致。
- 卡片显示锁定字号（`fontScale = 1f`），**设置页/页头/页脚保持跟随系统**。
- 卡片使用自带字体 Noto Sans SC 子集（`res/font/card_sans_*.ttf`），以免疫华为描粗；许可证见 `android/FONT-OFL.txt`。
- 顶部标签行四档退化：档 0 左右两半（地区贴右）→ 档 1 隐藏「真太阳时」（地区居中）→ 档 2 隐藏 UTC（地区贴左）→ 档 3 加省略号；`时辰` 永远贴最右。
- 竖分隔线**只在档 0** 上延到标签行、且顶端与文字上沿齐平；地区与线留 6dp。
- 地区名查不到时：预设城市回退显示城市名，手工/GPS 坐标显示半角 `-`；天气无数据显示 `-`。
- 「是不是中国境内」判定：**有国家码按国家码**（cn/hk/mo/tw），没有才退回 73–135°E / 18–54°N 包围盒。
- 报时：时辰交接 100ms、关键时间开始 500ms，峰值 42%，走通知音频通道。
