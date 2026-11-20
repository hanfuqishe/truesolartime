# 商店与「支持本项目」的放置规则（三端通用）

这份文档只回答一件事：**赞助入口能放在哪、不能放在哪。**
具体商店文案在 `ios/docs/app-store-metadata.md`（App Store 三语）与本文件的「可粘贴段」里。

---

## 1. 结论速查

| 位置 | 能放赞助链接吗 | 原因 |
|---|---|---|
| **App 内（iOS）** | ❌ 不要 | Apple 3.1.1：不得用按钮/链接引导到 IAP 以外的支付；打赏属数字内容 |
| **App 内（Android / 鸿蒙）** | ⚠️ 可以但没必要 | 无同类硬规则，但三端不一致、且国内商店也可能要求走 IAP |
| **App Store 元数据**（描述 / 推广文本 / 关键词） | ❌ 不要 | 3.1.1 原文是「Apps **and their metadata** may not include...」，元数据同样受约束 |
| **App Store「支持网址 / 营销网址」** | ✅ 可以 | 那是网站，不是应用元数据；用户点进去看到官网 |
| **华为应用市场「应用介绍」** | ⚠️ 不建议写收款 | 华为对第三方支付有自己规范；写「开源、欢迎反馈」是安全的 |
| **GitHub 仓库（FUNDING.yml / README / Pages）** | ✅ 推荐 | 完全不受商店规则约束 |

**当前实现**：只有 GitHub 侧有入口（`FUNDING.yml` → 赞助页），App 与商店元数据里一个字都没有。

---

## 2. 可直接粘贴的字段

### App Store Connect

| 字段 | 填什么 |
|---|---|
| 隐私政策 URL | `https://hanfuqishe.github.io/truesolartime/privacy.html` |
| 支持网址 | `https://hanfuqishe.github.io/truesolartime/` |
| 营销网址（可选） | 同上 |
| 描述 / 推广文本 / 关键词 | **保持原样，不要加赞助字样** |

### 华为应用市场（AppGallery）

「应用介绍」末尾可加这一句（不含任何收款信息）：

```
本应用为开源项目，源码与问题反馈见 GitHub：
https://github.com/hanfuqishe/truesolartime
```

---

## 3. 赞助页文案的三条约束（已写进 `docs/sponsor.html`）

1. **完全自愿**——不赞助也能用全部功能；
2. **不换取任何东西**——不解锁功能/内容/会员，否则按 3.1.1 必须走 IAP；
3. **不收集支付信息**——只外链微信支付，页面不记录任何收款数据。

这三条正是「个人赠与」与「数字商品」的分界线（Apple 3.2.1(vii)）。

---

## 4. 更换收款方式时

改两处即可，App 与商店字段都不用动：

1. `docs/assets/sponsor/` 里的收款码图片；
2. `docs/sponsor.html` 里的说明文字（例如换成支付宝）。

**不要**把收款码或链接加进：
- `ios/docs/app-store-metadata.md` 的描述段；
- 任何一端的 App 内页面（尤其 iOS）。
