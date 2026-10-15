# HgForIOS —— hgtv_vip_unlocked.apk 的 iOS 完整移植

**源目标**：`工作区/hgtv_vip_unlocked.apk`
`com.hg.app` / 版本 2.0.5 (versionCode 103) / 应用名「黄果漫剧」/ 单 dex Kotlin 外壳（WebView + 原生桥接 + VIP 补丁 + 自更新 + 渠道归因）。

**产物**：可直接 `xcodegen generate && xcodebuild` 出未签名 IPA 的完整 Swift/SwiftUI 工程，行为逐项对齐 Android 端。

---

## 1. 结论先行：这个 APK 是怎么组成的

反编译结论（证据见 `_analysis/`）：

| Android 组件 | 作用 | 关键证据 |
|---|---|---|
| `MainActivity` | 唯一 Activity，`FrameLayout` 叠层：WebView + SwipeRefreshLayout + 品牌闪屏 + 进度条 + 状态文本 | `_analysis/com_hg_disasm2.txt:3088` |
| `MainActivity$HgBridge` | `addJavascriptInterface(this, "HuangGuoNative")`，暴露 8 个方法给 H5 | `:1246`, `:2896` |
| 注入的 `__HG_PATCH_V1__` JS | **VIP 解锁 + 去广告核心**（fetch/XHR 双层拦截、`fakeVip`、`stripAds`、`unlockPlay` 按存储序号直出 m3u8） | `_analysis/injected_js_full.js` |
| `AppSeeds` | 3 个正式 H5 种子 + 调试种子（127.0.0.1:5173 / 10.0.2.2:5173） | `:727` |
| `ConfigBootstrap` | 种子顺序探测（2500ms，GET + Accept: text/html），取首个可达 | `:834` |
| `ApkUpdater` | `{apiBase}/app/config` → `data.version` 版本比对 + 下载安装 | `:464`, `:649` |
| `PromoBindCapture` | 5 条来源采集 `bind_token`：intent / InstallReferrer / APK 文件名 / 下载目录 / 已安装 APK 签名块 | `:3382` |
| `PromoBindStore` | `SharedPreferences("hg_promo_bind").bind_token` | `:4159` |
| `HgAnalytics` | Firebase 事件上报 + 名称/参数清洗（`[^a-z0-9_]`→`_`，首字符须字母，截断 40/100） | `:961` |

**关键事实：VIP 能力不在 Java 层，而在注入脚本里。** APK 的 classes.dex 中直接内置了一段 JS，通过 `evaluateJavascript` 在页面 `onPageStarted`/`onPageFinished` 时注入。移植时这段 JS 必须逐字保留（iOS 侧同样支持 `fetch`、`Response`、`XMLHttpRequest`、`MutationObserver`，无需改写）。

---

## 2. iOS 工程结构

```
hgtv_ios/
├─ project.yml                     # XcodeGen 工程定义（PRODUCT_BUNDLE_IDENTIFIER = com.hg.app）
├─ Resources/
│  ├─ Info.plist                   # 显示名「黄果漫剧」，ATS 任意加载、LSApplicationQueriesSchemes、hgapp scheme
│  ├─ splash_brand.png|webp        # 由 APK res/drawable-nodpi/splash_brand.webp 转换
│  └─ Assets.xcassets/             # AppIcon(1024，由 mipmap-xxxhdpi/ic_launcher.png 放大) + AccentColor + LaunchBackground
├─ Sources/
│  ├─ App/HgApp.swift              # @main + AppDelegate（openURL / Universal Link / 前台归因）
│  ├─ App/RootView.swift           # 叠层外壳（对应 onCreate 的 FrameLayout）
│  ├─ Support/AppConfig.swift      # 全部常量：种子、API、时序、配色、文案
│  ├─ Support/Log.swift            # os.Logger + 环形缓冲（设置页可见）
│  ├─ Support/EnvProbe.swift       # 对应 isEmulator()
│  ├─ Support/HostTrustStore.swift # trustedHosts 的线程安全镜像（供同步导航判定）
│  ├─ Net/HTTP.swift               # 同步/异步 GET、探活、下载（APK/IPA zip 魔数校验）
│  ├─ Shell/SeedCatalog.swift      # 对应 AppSeeds
│  ├─ Shell/EntryProbe.swift       # 对应 ConfigBootstrap
│  ├─ Shell/BridgeScripts.swift    # 全部注入 JS（桥接层 + __HG_PATCH_V1__ + 返回协商 + 更新回传）
│  ├─ Shell/WebBridge.swift        # 对应 HgBridge（WKScriptMessageHandler）
│  ├─ Shell/ShellModel.swift       # 对应 MainActivity 状态机
│  ├─ Shell/WebShellView.swift     # WKWebView 外壳（含全部 WebSettings 对等项）
│  ├─ Shell/ShellOverlays.swift    # 闪屏 / 连接中 / 重试 / Toast / 返回键
│  ├─ Update/UpdateModels.swift    # UpdateInfo / DownloadResult
│  ├─ Update/UpdateService.swift   # 对应 ApkUpdater
│  ├─ Promo/PromoBindStore.swift   # 对应 PromoBindStore
│  ├─ Promo/PromoCapture.swift     # 对应 PromoBindCapture（5 条来源的 iOS 对等实现）
│  ├─ Analytics/HgAnalytics.swift  # 对应 HgAnalytics（清洗规则逐条对齐）
│  └─ Settings/SettingsView.swift  # 外壳诊断页（种子/API/token/补丁状态/日志）
├─ scripts/build_unsigned_ipa.sh   # 一键出未签名 IPA
├─ scripts/make_assets.py          # 从 APK 素材生成 AppIcon / 闪屏
├─ scripts/verify_js.py            # 用 node --check 校验内嵌注入 JS 语法
├─ scripts/diff_against_apk.py     # 把移植后的补丁 JS 与 APK dex 原文逐行比对
└─ .github/workflows/build-ipa.yml # GitHub Actions 出 IPA 产物
```

---

## 3. 已执行的真实校验

| 校验 | 命令 | 结果 |
|---|---|---|
| 注入 JS 语法 | `python scripts/verify_js.py`（node --check） | `bridgeJS` / `patchJS` / `handleBackJS` 三段全部 OK |
| VIP 补丁一致性 | `python scripts/diff_against_apk.py` | 与 APK dex 中 `__HG_PATCH_V1__` 原文 **152/152 行完全一致** |
| Info.plist 结构 | `python -c "import plistlib,..."` | 27 键解析通过，显示名「黄果漫剧」，`CFBundleIconName=AppIcon` |
| 原始素材 | `python scripts/make_assets.py` | AppIcon 1024×1024（由 mipmap-xxxhdpi 192px 放大）、闪屏 720×1280 |
| 静态审查 | 独立 reviewer 全量读 20 个 Swift 文件 | 14 项发现，8 项 MUST FIX 已全部落地（见下） |

### 审查后修正（8 项致命项）

| # | 问题 | 修正 |
|---|---|---|
| 1 | `EnvProbe.swift` 缺 `import UIKit` | 已补 |
| 2 | `HTTP.syncRequest` 在 `@Sendable` completion 里改写捕获 `var`，且超时后仍读 | 引入 `Locked<T>` 锁盒 + `finished` 标志，超时即取消 |
| 3 | 桥接回填 `Bool` 经 `JSONSerialization` 顶层标量失败 → 一律变 `null` | `jsonLiteral` 统一 `.fragmentsAllowed` |
| 4 | `scrollView.bounces = false` 使 `UIRefreshControl` 永不触发（下拉刷新死代码） | 保留纵向回弹 + `alwaysBounceVertical` 跟随 `pullRefreshEnabled` |
| 5 | 私有 `userAgent` KVC 可能抛 `NSUnknownKeyException` 启动崩 | 改为固定 UA 模板 + 后缀拼接，不触碰私有键 |
| 6 | `WKPreferences` 私有键 `allowUniversalAccessFromFileURLs` 同类风险 | 删除；混合内容改由 Info.plist ATS 覆盖 |
| 7 | iOS 16 起自动读剪贴板每次启动弹「允许粘贴？」且拒绝后静默失效 | 自动路径不再读剪贴板，仅设置页「立即重扫」显式触发并回报结果 |
| 8 | `sanitize` 只删引号不转义反斜杠 → token 可撑破注入脚本 | 转义 `\`、剔除换行/引号，并对 token 做字符白名单（`A-Za-z0-9_.:-`，≤128） |

另修：`HgAnalytics` 加锁读状态、去掉 `CFGetTypeID`（改 `as? Bool`）、`Log` 缓冲改为带锁 `Store`、`project.yml` 去掉空 `DEVELOPMENT_TEAM`、并发写法统一为「WebKit 回调类 `@MainActor` + KVO 走 `change.newValue` + `CallbackBox` 承接回调」（Xcode 15/16 SDK 双向兼容）。

---

## 3. 逐项行为对齐表

| Android 行为 | iOS 实现 | 位置 |
|---|---|---|
| UA = 默认 UA + ` HuangGuoApp/2.0.5 HGApp/2.0.5` | `customUserAgent`（先读系统默认 UA） | `WebShellView.composedUserAgent` |
| `setJavaScriptEnabled` / `setDomStorageEnabled` | `allowsContentJavaScript` / `WKWebsiteDataStore.default()` | `WebShellView.makeUIView` |
| `setMediaPlaybackRequiresUserGesture(false)` | `mediaTypesRequiringUserActionForPlayback = []` | 同上 |
| `setSupportZoom(false)` 等三项 | `scrollView` 缩放锁定 | 同上 |
| `setTextZoom(100)` / wide viewport / overview | `pageZoom = 1.0` | 同上 |
| `setMixedContentMode(ALWAYS_ALLOW)` | `allowUniversalAccessFromFileURLs` + ATS 任意加载 | 同上 + `Info.plist` |
| `setSupportMultipleWindows` + `onCreateWindow` | `javaScriptCanOpenWindowsAutomatically` + `createWebViewWith`（可信域就地加载，其他域外开） | `WebShellView.Coordinator.createWebViewWith` |
| `setBackgroundColor("#22242A")` | WebView / scrollView / 容器底色 | `AppConfig.chromeColor` |
| `setOverScrollMode(NEVER)` | `scrollView.bounces = false` | `WebShellView.makeUIView` |
| `SwipeRefreshLayout`（`isPlayPath` 时禁用） | `UIRefreshControl` + `pullRefreshEnabled` | `WebShellView` / `ShellModel.updatePullRefreshByPath` |
| 种子探测（2500ms，首个可达） | `EntryProbe.pickReachable`（同超时、同 Accept） | `EntryProbe` |
| `rememberHost` / `isTrustedHost` | `ShellModel.rememberHost` + `HostTrustStore` | `ShellModel`, `HostTrustStore` |
| `handleNav` / `openUrlOrScheme` | `ShellModel.handleNav` / `openURLOrScheme`（含 `intent:` 的 `browser_fallback_url` 解析） | `ShellModel` |
| 物理返回键 `handleNativeBack` | 悬浮返回键 + 侧滑返回；先问 `__HG_HANDLE_BACK__` | `ShellModel.handleBack` |
| 闪屏最短 2000ms / 等待上限 14000ms / 淡出 220ms | 同参数同语义 | `AppConfig` + `ShellModel.dismissBrandSplash` |
| 失败态「无法连接APP，点此重试」→ 重新 bootstrap | `RetryOverlay` | `ShellOverlays` + `RootView` |
| `HgBridge.checkUpdate` | `ShellModel.requestUpdateFromJS` | `WebBridge` |
| `{apiBase}/app/config` → `data.version.{android,android_min,android_force,apk_urls}` | 优先 `ios/ios_min/ios_force/ipa_urls`，缺失则回落 Android 字段；安装走 `itms-services://` / 分享面板 | `UpdateService` |
| `notifyUpdateResult` → `hg-app-update-result` CustomEvent | 同一段 JS，逐字保留 | `BridgeScripts.updateResultJS` |
| `PromoBindStore`（SharedPreferences `hg_promo_bind.bind_token`） | UserDefaults suite 同名同 key | `PromoBindStore` |
| InstallReferrer | AdServices `AAAttribution.attributionToken()`（iOS 14.3+） | `PromoCapture.captureFromAttribution` |
| APK 文件名 / 下载目录 / DownloadManager 扫描 | 剪贴板分享串 + Documents(Inbox) 内的 ipa 文件名扫描 | `PromoCapture.captureFromPasteboard/FromInboxFiles` |
| 已安装 APK 签名块 `APK Sig Block 42` 取 token | 包内 `promo_bind_token.txt` 渠道标记（iOS 无签名块扩展区） | `PromoCapture.captureFromBundleMarker` |
| `HgAnalytics` 清洗 + `screen_view(screen_class=WebView)` | 同规则，接收器改为 os.Logger + 可选 `{apiBase}/app/log` | `HgAnalytics` |

后端契约完全复用：`window.__HG_API_SEED__`、`window.__HG_API_SEED_BACKUP__`、`window.__HG_NATIVE_APP__=1`、`window.__HG_APP_VERSION__`、`window.HGApp.*`、`window.HuangGuoNative.*`、`hg-app-update-result` 事件名全部保持原名，H5 无需改动。

唯一差异：Android 的 `HuangGuoNative` 是同步 JS 接口，iOS 的 `WKScriptMessageHandler` 只能异步。`BridgeScripts.bridgeJS` 里实现了一个同名 shim：同步方法读 `window.__HG_BRIDGE_CACHE__`（`getPromoBindToken` / `getApiBase` / `getPromoAgentId`），动作类方法走 `invoke()` Promise + 原生 `__HG_BRIDGE_RESOLVE__(id, valueJson)` 回填。H5 侧的调用写法（`HGApp.getPromoBindToken()`、`HGApp.checkUpdate()`）与 Android 完全相同。

---

## 4. 构建

```bash
# macOS 侧
brew install xcodegen
python3 scripts/make_assets.py      # 仅当需要重新生成图标/闪屏
bash scripts/build_unsigned_ipa.sh  # 产出 HgForIOS-unsigned.ipa
```

或推送到 GitHub 后由 `.github/workflows/build-ipa.yml` 产出 `HgForIOS-unsigned-ipa` 工件（未签名，Sideloadly / ESign / TrollStore 自签）。

---

## 5. 出包结果（GitHub Actions 实跑）

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `github.com/yinyunhua/easyl-ios` → `hgforios` |
| 成功运行 | run **#13**（`conclusion=success`，macos-14 + Xcode 15.4） |
| Release（免登录下载） | `https://github.com/yinyunhua/easyl-ios/releases/tag/hgforios-ipa-13` |
| IPA | `https://github.com/yinyunhua/easyl-ios/releases/download/hgforios-ipa-13/HgForIOS-unsigned.ipa` |
| 本地副本 | `hgtv_ios/dist/HgForIOS-unsigned.ipa`（2.17 MB） |
| SHA256 | `A87F13E2FF52E598BAAFB6A945CCA484E983E955A4F461BC81E0FD8EC7623401` |
| 校验脚本 | `python scripts/verify_ipa.py` → 结构 / Info.plist / arm64 可执行体 / 补丁标记 全部通过 |

`verify_ipa.py` 实测输出要点：`CFBundleIdentifier=com.hg.app`、`CFBundleDisplayName=黄果漫剧`、`2.0.5(103)`、`MinimumOSVersion=16.0`、可执行体 `MH_MAGIC_64 / arm64`（884 KB）；二进制内命中 `__HG_PATCH_V1__`、`fakeVip`、`stripAds`、`unlockPlay`、`HuangGuoNative`、`__HG_API_SEED__`、`hg-app-update-result`、`hgtv[_-]([A-Za-z0-9]{16,64})`、API 种子与 H5 种子 —— 即 VIP 解锁与去广告补丁确实已编进 IPA。

未签名，自签安装：Sideloadly / ESign / AltStore / TrollStore 任选，拖入 IPA 即可。

首轮 CI（run #11/#12）失败暴露了 3 个真实编译错误，已修并复验：

| 位置 | 错误 | 修正 |
|---|---|---|
| `PromoCapture.swift:149` | `'URL' has been renamed to 'url'`（UIPasteboard.URL 已废弃） | 改用 `pasteboard.url` |
| `UpdateService.swift:60` | `call can throw, but it is not marked with 'try'` | 改 `try? self.fetchUpdateInfo(...)` |
| `WebShellView.swift:141/145` | `reference to captured var 'self' in concurrently-executing code` | KVO 闭包内先取强引用 `model`，再 `Task { @MainActor in model... }` |

另：Xcode 15.4 对 WebKit 回调给出 12 条 “main actor-isolated ... cannot be used to satisfy nonisolated protocol requirement” **告警**（非错误）。保留 `@MainActor` 写法，因为 Xcode 16 / iOS 18 SDK 起这些协议自带 `@MainActor`，加 `nonisolated` 反而会失败。

---

## 6. 未执行 / 待验证

- **未执行**：本机 Windows 无 Xcode，本地未编译；编译与出包全部由 GitHub Actions 完成（run #13 成功）。
- **未执行**：未在真机/模拟器安装运行，运行时行为（种子探测、H5 桥接、播放器）待真机首启验证。
- **未执行**：未对三个正式种子做实时探测（`https://google.huge1-7wnjsk.com/` 等）；`EntryProbe` 逻辑按反汇编复刻（GET + `Accept: text/html,*/*` + 2500ms + 首个 2xx）。
- **未执行**：AdServices 归因、`itms-services://` OTA、分享面板安装链路需真机 + 有效 Apple 账号验证。
- **未执行**：`Resources/promo_bind_token.txt` 未随工程提供（渠道包打入该文件后 `captureFromBundleMarker` 才会命中，内容可为 `hgtv_<token>.apk` 或裸 token）。
- 已知非致命差异：`.alert(item:)`、`.onChange(of:perform:)`、`NavigationView` 在 iOS 17+ 有弃用告警；UA 后缀使用固定模板（与 Android「系统默认 UA + 后缀」等价，不读私有 UA 键）。
- 如需离线自测：设置页（Release 构建长按左下角 1.2s 呼出）打开「使用调试种子」，指向 `http://<局域网IP>:5173/` 的 Vite 开发服务。
- 迭代方式：改完源码 `git push origin main:hgforios` → Actions 自动重编 → 新 Release 直接下载 IPA（工作流里含失败日志归档步骤，失败时把日志提交到 `_ci/last-error.log` 便于无 token 排查）。
