# App Store 元数据（1.4.39）

App Store 上已有一个叫「真太阳时」的 App，为了区分，本项目在苹果商店改用以下名称。
**主名称 / 副标题只能填在 App Store Connect，不在安装包里**；安装包里的只有「显示名称」。

| 位置 | 采用 | 字符数 | 填在哪 |
| --- | --- | --- | --- |
| 中文主名称 | **此刻真太阳时** | 6 | App Store Connect → 应用信息 → 名称（简体中文） |
| 英文主名称 | **NowSolar: True Solar Time** | 25 | App Store Connect → 应用信息 → 名称（English） |
| 显示名称（图标下） | **实时真太阳时** | 6 | 代码：`ios/project.yml` → `INFOPLIST_KEY_CFBundleDisplayName` |
| 中文副标题 | **实时定位显示当前真太阳时** | 11 | App Store Connect → 版本信息 → 副标题（简体中文，≤30 字符） |
| 英文副标题 | **Live solar time by location** | 27 | App Store Connect → 版本信息 → 副标题（English，≤30 字符） |

## 说明

- 主名称用「此刻真太阳时」强调**实时**，与商店里既有那个「输入出生时间计算」的 App 区分开。
- 英文主名称用 `NowSolar` 作品牌词，避免与 `True Solar Time` 完全同名（Apple 不允许重名）。
- **副标题上限 30 字符**，英文那条 27 字符，安全。
- 显示名称是图标下方的文字，iOS 主屏一般能显示 4~6 个汉字，6 字在部分机型可能显示为
  「实时真太阳…」（系统自动截断），属正常表现；如果更在意完整显示，可考虑 5 字方案
  （例如「实时真太阳」「此刻真太阳时」）。
- 应用内页头标题（`ContentView` 里的「真太阳时」）暂不改，它是界面标题而不是商店名称。

## 上架时还要准备（与本表无关）

- 隐私政策 URL：仓库 `docs/privacy.html`（可用 GitHub Pages 托管）
- 截图：6.9"/6.7" 竖屏各 3 张起（模拟器出图即可）
- `PrivacyInfo.xcprivacy`（iOS 17+ 隐私清单）与 `ITSAppUsesNonExemptEncryption = NO`
- 中国大陆区上架需要工信部 **App 备案号**；没有的话只能上架非中国区
