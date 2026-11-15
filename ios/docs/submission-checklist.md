# App Store 提交审核清单（iOS）

> 目标：先把**非中国区**上架跑通（中国区等 ICP 备案下来再加）。
> 更新：2025-11-15 · 对应构建 1.4.39 (build 53)

---

## 0. 提交前必须就绪的三样

| 项 | 值 | 怎么得到 |
|---|---|---|
| 构建 | TestFlight 里状态为「可测试」的最新构建 | CI → Actions → `iOS TestFlight` → Run workflow |
| 隐私政策 URL | `https://hanfuqishe.github.io/truesolartime/privacy.html` | 仓库 Settings → Pages → master / docs |
| 支持 URL | `https://github.com/hanfuqishe/truesolartime/issues` | 直接用仓库 issues |

验证隐私政策地址：浏览器打开应能看到**中英双语**页面（中文九节 + English 九节）。

---

## 1. App Store Connect 逐页填写

路径：appstoreconnect.apple.com → 我的 App → 真太阳时时钟

### 1.1 App 信息（App Information）

| 字段 | 填什么 |
|---|---|
| 名称（简体中文） | 真太阳时时钟 |
| 名称（繁體中文） | 真太陽時時鐘 |
| 名称（English） | NowSolar: True Solar Clock |
| 副标题 | 三语见 `ios/docs/app-store-metadata.md` |
| 主要类别 | 实用工具（Utilities） |
| 次要类别 | 天气（可选，也可留空） |
| 内容版权 | 不包含第三方内容 |
| 年龄分级 | 见第 3 节 |
| 隐私政策 URL | 上面那个 Pages 地址 |

### 1.2 价格与销售范围（Pricing and Availability）

| 项 | 设置 |
|---|---|
| 价格 | 免费 |
| 销售范围 | **取消勾选「中国大陆」**（等 ICP 备案下来再勾回来） |
| 分发方式 | 公开发布 |

### 1.3 版本信息（Version Information）

每个语言一个 tab（简体 / 繁體 / English），字段：

| 字段 | 来源 |
|---|---|
| 描述 | `ios/docs/app-store-metadata.md` → 对应语言代码块，整段复制 |
| 关键词 | 同上（英文 96/100 字符，接近上限，别再删改） |
| 推广文本 | 同上 |
| 支持 URL | `https://github.com/hanfuqishe/truesolartime/issues` |
| 版本号 | 1.4.39（与构建一致，不用改） |

### 1.4 截图

只需填 **iPhone 6.9 吋**（或 6.7 吋）这一栏，其他尺寸可留空。

| # | 画面 | 拍摄要点 |
|---|---|---|
| 1 | 首页大卡片 | 地址为短名（如「上海市黄浦区」）→ 四段齐全、竖线贯通标签行 |
| 2 | 太阳卡 + 地图卡 | 同屏，日出/上中天/日落可见 |
| 3 | 设置页 | 定位方式、底图、两个提醒开关；确认**看不到「诊断」** |
| 4 | 夜间模式首页 | 好看且能体现昼夜主题 |
| 5 | 关键时间段的首页（可选） | 时轴上有绿/红色段 |

拍摄：在已装 TestFlight 版的 iPhone 上，直接按侧键 + 音量上截屏，AirDrop 或云盘导到电脑。

### 1.5 App 审核信息（App Review Information）

| 字段 | 填什么 |
|---|---|
| 联系人 | 你的姓名 |
| 电话 | 你的手机号 |
| 邮箱 | 你的 Apple ID 邮箱 |
| 备注（中文） | 见下方「审核备注」 |
| 演示账号 | 不需要（无登录） |

**审核备注（中文）**

```
本应用无账号系统、无内购。

定位用途：用于计算「当地的」真太阳时（太阳经过当地子午线的时刻）与日出日落时间。
如果审核时不想授予定位权限，可在「设置 → 位置」里手动输入经纬度（例如 31.23 / 121.47，上海），
或直接从「常用城市」里选择（北京、上海、纽约、东京等 20 个城市）。两种方式功能完全等价。

真太阳时的说明：它等于标准时间加上「经度修正」与「均时差」，
因此与设备时钟通常相差几分钟到十几分钟，这是本应用的核心功能，不是显示错误。

第三方数据：天气来自 Open-Meteo（open-meteo.com），地名反查使用系统地理编码
（失败时备用 OpenStreetMap Nominatim），关键时间表读取自公开网页 duosuccess.com。
以上请求只携带坐标，不含任何用户身份信息。

「时辰提醒 / 关键时间报时」为可选通知，默认关闭，开启后会在整点播放短提示音。
```

**审核备注（English）**

```
The app has no accounts and no in-app purchases.

Location is used only to compute the *local* true solar time (the moment the sun crosses the local meridian)
and sunrise/sunset. If the reviewer prefers not to grant location access, tap Settings → Location and enter
coordinates manually (e.g. 31.23 / 121.47 for Shanghai) or pick one of the 20 built-in cities; all features
work identically.

About true solar time: it equals the device's standard time plus a longitude correction and the equation of
time, so it typically differs from the clock by several to tens of minutes. That is the core feature, not a bug.

Data sources: weather from Open-Meteo (open-meteo.com); reverse geocoding via the system geocoder
(OpenStreetMap Nominatim as fallback); the key-time schedule is read from the public page duosuccess.com.
All requests carry coordinates only, with no user identifiers.

Shichen remonter / key-time chime are optional notifications, off by default.
```

---

## 2. 出口合规（Export Compliance）

已在构建里声明：`ITSAppUsesNonExemptEncryption = NO`（只用系统 HTTPS，属豁免）。

- 如果仍然弹「App 加密文稿」：选 **「不属于上述的任意一种算法」**（第 4 项）→ 法国分发「是」→ 保存。
- 选错会变成「需要上传出口合规证明文稿」，那就要走 ANSSI 流程，**别选错**。

---

## 3. 年龄分级问卷（App 内容分级）

全部选「**无 / No**」：

| 项目 | 回答 |
|---|---|
| 卡通或幻想暴力 | 无 |
| 现实暴力 | 无 |
| 血腥或恐怖 | 无 |
| 成人/性暗示 | 无 |
| 裸露 | 无 |
| 粗俗或低俗幽默 | 无 |
| 酒精、烟草、毒品 | 无 |
| 赌博 | 无 |
| 恐怖/惊悚 | 无 |
| 医疗/健康信息 | 无 |
| **无限制网页访问** | **无**（App 内置浏览器只显示地图，不算网页浏览器） |
| 用户生成内容 | 无 |

结果应为 **4+**。

---

## 4. 提交

1. 版本信息页右上角 **「添加构建版本」** → 选 build 53
2. 确认「出口合规」已显示「已提供」
3. 点右上角 **「提交以供审核」**
4. 选择「**手动发布**」或「自动发布」（建议手动，审核通过后自己挑时间上）

审核时间通常 **24~48 小时**，首次提交可能更久。

---

## 5. 常见被拒原因与对策

| 苹果理由 | 我们的对策 |
|---|---|
| Guideline 4.2 最低功能要求 | 强调核心是「真太阳时计算 + 十二时辰 + 关键时段 + 报时 + 逐时天气」，并给出审核备注里的等价操作路径 |
| Guideline 5.1.1 定位权限说明不清 | `NSLocationWhenInUseUsageDescription` 三语已写明用途；备注里给了不授权也能用的替代方式 |
| Guideline 2.1 崩溃/无法使用 | 提交前在真机走一遍：切城市、切语言、开报时、切夜间 |
| 缺少隐私政策 | URL 已提供，中英双语 |
| 中国区缺 ICP 备案 | **先不勾中国区**，等备案号下来再加 |

---

## 6. 上架之后再加中国区

1. 备案号拿到后：App Store Connect → 价格与销售范围 → **勾选中国大陆**
2. 可能需要补充「互联网信息服务备案号」字段（在 App 信息 → 中国区专用信息）
3. 如果提示需要「网络文化经营许可证」之类，一般资讯类工具 App 不需要，按提示走即可

---

## 7. 每次发新版本的最小流程

```powershell
# 1) 改代码 → 提交推送
git add -A; git commit -m "..."; git push

# 2) 触发 TestFlight（build 号递增，避免 Redundant Binary Upload）
#    Actions → iOS TestFlight → Run workflow → build_number: 54

# 3) 验完 → App Store Connect 新建版本 → 选构建 → 提交审核
```

版本号（`MARKETING_VERSION`）用于商店展示，构建号（`CURRENT_PROJECT_VERSION`）用于区分上传；CI 里用 `build_number` 输入覆盖后者。
