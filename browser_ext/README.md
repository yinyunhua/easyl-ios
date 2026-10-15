# 黄果漫剧 Web 补丁（浏览器扩展）

把 App 端同一套逻辑搬到浏览器里：**VIP 解锁 + 去广告**。脚本完全本地运行，不上传任何数据。

## 与 App 的关系
- `content.js` 由 `scripts/build_browser_ext.py` 从 iOS 工程里**已通过测试**的注入脚本生成：
  - `patch.js` 与 APK dex 中 `__HG_PATCH_V1__` 原文逐行一致（152/152 行）
  - `ios_patch.js` 提供广告兜底清理与 seek 续播
  - `bridge.js` 提供 `HGApp / HuangGuoNative` 兼容层
- 结论：这套能力本质是网页层逻辑（改写后台返回的 `is_vip / need_vip / play_url`），浏览器里效果一致。

## 安装（Chrome / Edge，桌面）
1. 打开 `chrome://extensions`（Edge 为 `edge://extensions`），右上角开启「开发者模式」。
2. 点「加载已解压的扩展程序」，选择本目录（`browser_ext/`）。
3. 打开站点（例如 `https://google.huge1-7wnjsk.com/`）即可生效；插件图标可开关「额外去广告」与填 `bind_token`。

## Firefox
`about:debugging#/runtime/this-firefox` → 「临时载入附加组件」→ 选择 `manifest.json`。

## iOS / iPadOS Safari（可选，需要 Xcode 构建）
Safari 网页扩展必须在 App 里内嵌一个扩展 target（`com.apple.Safari.web-extension`），把 `content.js` 作为资源、`manifest.json` 声明匹配域；构建后在 设置 → Safari → 扩展 里启用。
这条路在 iOS 上其实**更顺**：Safari 原生支持 HLS，可直接用系统播放器，且没有 WebView 的各种布局坑。

## 已知限制
- **桌面 Chrome 不能直接播 HLS**：如果站点给桌面浏览器下发的是 `index.m3u8` 而没有自带 `hls.js`，画面会不出来（音频/网络都正常）。解决方式是在 `content.js` 末尾追加注入 `hls.js` 并把 `video.src` 交给它。Safari / iOS 无此问题。
- 站点更新接口字段名时，`SAFE_KEYS` 与推广数组启发式可能需要同步调整（改 iOS 工程里的 `BridgeScripts.iosPatchJS` 后重新运行生成脚本）。
- 插件不提供 App 端的外壳能力（闪屏、自更新、渠道归因上报、原生全屏/横竖屏控制）。
