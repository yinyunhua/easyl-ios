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
| 注入 JS 语法 | `python scripts/verify_js.py`（node --check） | 5 段（bridge / v1 补丁 / v2 补丁 / handleBack / 开关）全部 OK |
| Swift 多行字符串缩进 | `python scripts/lint_swift_rawstrings.py` | 0 问题（run #15 的失败正是这条规则，现已本地拦住） |
| Swift 符号一致性 | `python scripts/lint_swift_symbols.py` | 0 问题；负向测试可复现（把定义改名 → 立刻报 `schedulePlayerLayout` 未定义） |
| 补丁行为测试 | `node scripts/test_ios_patch.js` | **25 项全过**（广告清空/内链不误清、seek 续播、隐藏导航、含 video 容器不隐藏、fixed 播放层不动、控件常显、选集条让位、速度键回传、居中不抖动、退出还原） |
| VIP 补丁一致性 | `python scripts/diff_against_apk.py` | 与 APK dex 中 `__HG_PATCH_V1__` 原文 **152/152 行完全一致** |
| Info.plist 结构 | `python -c "import plistlib,..."` | 键解析通过，显示名「黄果漫剧」，`CFBundleIconName=AppIcon` |
| 原始素材 | `python scripts/make_assets.py` | AppIcon 1024×1024（由 mipmap-xxxhdpi 192px 放大）、闪屏 720×1280 + 锚点 JSON |
| 出包内容 | `python scripts/verify_ipa.py` | 结构 / Info.plist / arm64 可执行体 / 25 个补丁标记 / 闪屏锚点 全部通过 |
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
| 成功运行 | run **#19**（#16/#17 连续 success；#15 因多行字符串缩进失败，已修并加本地 lint，macos-14 + Xcode 15.4） |
| Release（免登录下载） | `https://github.com/yinyunhua/easyl-ios/releases/tag/hgforios-ipa-19` |
| IPA | `https://github.com/yinyunhua/easyl-ios/releases/download/hgforios-ipa-19/HgForIOS-unsigned.ipa` |
| 本地副本 | `hgtv_ios/dist/HgForIOS-unsigned.ipa` |
| SHA256（run #17） | `F9F495EC7EC2629223A50C6BBD78A6E4F550C886357EB7AB70AB01ED8584C6D5` |
| 校验脚本 | `python scripts/verify_ipa.py` → 结构 / Info.plist / arm64 可执行体 / 28 个补丁标记 / 闪屏锚点 全部通过 |

### run #16 → #17：黑屏回归与防护（重要）

run #16 上真机后出现「只剩声音、没有画面」。定位到两个我自己引入的过度操作：

1. **误伤整页容器**：底部导航判定只看了「贴底 + 含 ≥3 个主 tab 关键词」，结果把**同时含 `<video>` 的外层容器**也加上了 `display:none` → 播放层整块消失（音频继续走）。
2. **强改播放层定位**：`.hg-player-box` 里写了 `position:relative + top:0`，把 H5 原本 `position:fixed` 的全屏播放层挪回文档流，落到视口外。

三重防护（run #17）：

| 防护 | 实现 |
|---|---|
| 不误伤 | `containsVideo(el)` 守卫：任何子树含 `<video>`（或自身是 video）的节点**永不隐藏**；判定同时收紧为「高度 ≤22%vh / 宽度 ≥70%vw / 贴底」等 |
| 不动定位 | 仅当播放容器是**文档流内**（`position: static/relative`）才给它加 `.hg-player-box` 撑高；`fixed/absolute/sticky` 的全屏播放层保持原位原尺寸 |
| 自检 + 回滚 | `videoVisible()` 检查视频 rect/computed display/visibility/opacity；隐藏导航或进入沉浸式后若视频不可见，**立即整体回滚**并记录 `HGApp.__lastRollback`；居中 nudge 也带 ±25%vh 幅度上限与失败回滚 |

原生侧再加一道看门狗：进入播放页/沉浸式 1.5s 后读 `HGApp.playerDiag()`（视频数、可见性、隐藏节点数、回滚标记），一旦判定不可见就自动 `setPlayerMode(false)+setImmersive(false)`、解锁方向并 toast「已回退播放页增强（避免黑屏）」——最坏结果是保留导航栏，而不是黑屏。

真机反馈第二轮 6 项（run #16 引入、run #17 保留并加固）：

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 竖屏左上角「第X集」压住 logo；右上角搜索、底部 4 个导航多余 | H5 自身顶栏/底部 tab 与剧集标签同一区块 | 播放页注入 `HGApp.setPlayerMode(true)`：按「底部出现 ≥3 个主 tab 关键词」「顶部含搜索框」两条判定，给顶栏与底部导航加 `.hg-immersive-hidden`（`display:none!important`），退出播放页原样还原 |
| 2 | 右下角横屏键压住播放时间/倍速 | 我把旋转键放在了右下 | 旋转键移到**右上角**（34pt、55% 透明度）；右下角只留隐形长按区 |
| 3 | 竖屏视频仍不居中 | 视频中心与屏幕中心存在固定偏移（容器上方有顶栏、下方有 tab/选集） | 隐藏导航后按「视频中心 → 屏幕中心」计算偏移并写回 `transform: translateY()`，偏移被夹在容器上下余量内（不会溢出、不动布局） |
| 4 | 横屏仍有一堆导航/logo/搜索，不是沉浸式 | 横屏时只是把 APP 转了向，H5 布局未变 | 横屏进入沉浸式：`html.hg-immersive`（黑底、禁滚动）+ 播放器盒 `.hg-player-box`（`height:100vh`）+ 视频 `.hg-fill-video`（`width:100%`、`object-fit:contain`）+ 隐藏导航；只留视频、进度条、旋转键 |
| 5 | 拖/点进度仍卡 | v2 清扫挂了 `MutationObserver` 且每 900ms 全量跑 `querySelectorAll` + `getBoundingClientRect`（强制回流），而播放页 DOM 每 ~100ms 更新一次 | 三重收口：① 清扫改为 220ms 防抖 + 最小间隔 1600ms；② **有视频正在播放时完全不做任何 DOM 扫描/改动**；③ `centerVideo` 只在模式切换/旋转/尺寸变化时执行 |
| 6 | 视频不清晰，横屏尤其明显 | 横屏没有把 video 元素放大到视口，H5 按小尺寸渲染后被拉伸 | 沉浸式强制 `.hg-fill-video`（满宽 + `object-fit:contain`），并优先 `webkitEnterFullscreen()` 走原生全屏播放器（按屏幕分辨率渲染）；旋转后派发 `resize`/`orientationchange` 让 H5 重排 |

全部改动都放在 iOS 增强补丁 v2 里（`__HG_PATCH_V2__`），APK 原始补丁 v1 保持逐字一致（152/152 行）。设置页可实时开关「额外去广告」「播放页沉浸式」，另有「用 H5 优先返回键 / 锁横屏 + 原生全屏 / 通知 H5 重排 / 重跑居中」按钮。

`verify_ipa.py` 实测输出要点：`CFBundleIdentifier=com.hg.app`、`CFBundleDisplayName=黄果漫剧`、`2.0.5(103)`、`MinimumOSVersion=16.0`、可执行体 `MH_MAGIC_64 / arm64`；包内 `splash_anchor.json` = `{contentCenterY: 0.4702, contentCenterX: 0.4778}`；二进制命中 `__HG_PATCH_V1__`、`fakeVip`、`stripAds`、`unlockPlay`、`HuangGuoNative`、`__HG_API_SEED__`、`hg-app-update-result`、`hgtv[_-]([A-Za-z0-9]{16,64})`、`__HG_PATCH_V2__`、`sweepAds`、`fixVideoLayout`、`webkitEnterFullscreen`、`orientationchange`、`requestGeometryUpdate`。

未签名，自签安装：Sideloadly / ESign / AltStore / TrollStore 任选，拖入 IPA 即可。

### 真机反馈的 4 个问题与修法（run #14）

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 首页顶部仍有 2×5 共 10 个外链广告图标 | v1 补丁只清 `icons/banners/strip/slots`，且 `isAppApi` 路由白名单过窄；注入发生在 `didStart`，首页首个数据请求可能抢先 | ① 桥接 + v1 + v2 补丁全部改到 `atDocumentStart` 注入（早于页面脚本）；② v2 补丁四层清理：更宽路由（`/api/`、`/app/`、种子域名）→ 流量清洗 → SAFE_KEYS 字段清空 → 「≥4 项且 ≥50% 为外链图标」数组启发式 + DOM 外链图标栅格兜底 |
| 2 | 左上角 `〈` 与 H5 头部 logo 重合（每页都有） | 悬浮返回键压在 H5 头部区域 | 去掉悬浮按钮，改**屏幕左缘右滑**返回；沿用 Android 语义：先问 `__HG_HANDLE_BACK__`，返回 `handled` 即停手，否则 `goBack` |
| 3 | 播放页拖进度条后不自动播放 | WebKit 在 seek 时会把 `<video>` 置暂停（Android 无此行为） | v2 补丁加 seek 续播：`pause/seeking/seeked/waiting` 联动，仅当「seek 前 1.5s 内发生过 pause」或「seek 后仍在播放态」才自动 `play()` 重试；用户主动暂停不会被误恢复 |
| 4 | 启动闪屏 logo 不居中 | 素材是满屏渐变图，logo 簇本身位于 **47.0% 高度 / 47.8% 宽度**，铺满后看起来偏上偏左 | `scripts/make_assets.py` 量测锚点写入 `Resources/splash_anchor.json`；`SplashOverlay` 按锚点平移 + 轻微放大腾余量（平移量夹在余量内，任何屏幕比例都不露边） |

### 播放页横屏 / 全屏（新增，对应“没有横屏选项”）

iOS 不支持 `screen.orientation.lock()`，Android 的「播放页全屏横屏」在 iOS 必须由外壳提供：

- 播放页（`play.php` / `/play`）右侧中部出现**旋转键**：点一下 = 锁横屏 + 对页面上最大的 `<video>` 调 `webkitEnterFullscreen()`（原生全屏播放器，自动横屏）；再点恢复竖屏。
- 原生实现：`AppOrientation` 用 `UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))` + `application(_:supportedInterfaceOrientationsFor:)`；离开播放页自动恢复竖屏。
- H5 亦可主动调用：`HGApp.setOrientation('landscape'|'portrait'|'auto')`、`HGApp.enterFullscreen()`、`HGApp.exitFullscreen()`（并在 `HuangGuoNative.*` 上补了同名方法）。
- 播放器居中兜底：v2 的 `fixVideoLayout()` 只在 `<video>` **真的溢出视口**或**水平偏心 > 8px** 时才纠正（`max-width/object-fit/margin:auto` + 父容器居中）；每次旋转后派发 `resize` / `orientationchange` 让 H5 重排（否则播放器仍按旧视口居中，看起来偏心）。

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
