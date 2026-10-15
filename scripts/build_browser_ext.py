"""把 iOS 工程里已通过测试的注入 JS 组装成浏览器扩展（Chrome/Edge MV3）的 content.js。

用法：python scripts/build_browser_ext.py
产物：browser_ext/content.js（+ manifest.json / popup / README 由本脚本一并写出）
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSDIR = os.path.join(ROOT, "_analysis", "jscheck")
OUT = os.path.join(ROOT, "browser_ext")
os.makedirs(OUT, exist_ok=True)

bridge = open(os.path.join(JSDIR, "bridge.js"), encoding="utf-8").read()
patch = open(os.path.join(JSDIR, "patch.js"), encoding="utf-8").read()
ios_patch = open(os.path.join(JSDIR, "ios_patch.js"), encoding="utf-8").read()

# verify_js.py 抽脚本时会把拿不准的插值替换成 PLACEHOLDER；这里补成真实值，
# 否则浏览器里会 ReferenceError（一整段补丁都会被带崩）。
SUBS = [
    ("PLACEHOLDER", "''"),   # 兜底：window.__HG_API_SEED_BACKUP__=PLACEHOLDER; -> ''
]
for src, dst in SUBS:
    bridge = bridge.replace(src, dst)
    patch = patch.replace(src, dst)
    ios_patch = ios_patch.replace(src, dst)

HEADER = """// ============================================================================
// 黄果漫剧 Web 补丁（浏览器扩展 content script）
//
// 这份脚本与 iOS/Android 端注入的是同一份逻辑：
//   - patch.js      : 与 APK dex 中 __HG_PATCH_V1__ 原文逐行一致（VIP 解锁 + 去广告）
//   - ios_patch.js  : 额外广告兜底清理 / seek 续播（播放器沉浸式相关函数在浏览器里不触发）
//   - bridge.js     : HGApp / HuangGuoNative 兼容层（浏览器没有 webkit.messageHandlers，调用会安全失败）
//
// 由 scripts/build_browser_ext.py 自动生成，请勿手改；改逻辑请改 iOS 工程再重新生成。
// ============================================================================
(function () {
  'use strict';

  // ---- 默认开关（popup 可覆盖；chrome.storage 读取是异步的，先落默认值）----
  try {
    window.__HG_NATIVE_APP__ = 1;
    window.__HG_EXTRA_ADS__ = true;
    window.__HG_PLAYER_EXTRA__ = false;   // 浏览器不用外壳沉浸式
    window.__HG_PLAYER_TUNE__ = false;    // 也不用外壳播放器调优
    window.__HG_STRIP_HIDDEN__ = false;
    window.__HG_BRIDGE_CACHE__ = window.__HG_BRIDGE_CACHE__ || { promoBindToken: '' };
  } catch (e) {}

  // ---- 读取 popup 配置（可选）----
  try {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      chrome.storage.local.get({ extraAds: true, hideStrip: false, bindToken: '' }, function (cfg) {
        try {
          window.__HG_EXTRA_ADS__ = !!cfg.extraAds;
          window.__HG_STRIP_HIDDEN__ = !!cfg.hideStrip;
          window.__HG_BRIDGE_CACHE__ = window.__HG_BRIDGE_CACHE__ || {};
          window.__HG_BRIDGE_CACHE__.promoBindToken = cfg.bindToken || '';
        } catch (e) {}
      });
    }
  } catch (e) {}

"""

TAIL = """
})();
"""

content = HEADER
content += "\n// ---------------------------- 桥接兼容层 ----------------------------\n"
content += "try {\n" + bridge.strip() + "\n} catch (e) { console.warn('[hg-patch] bridge failed', e); }\n"
content += "\n// ------------------- VIP 解锁 + 去广告（APK 原文一致） -------------------\n"
content += "try {\n" + patch.strip() + "\n} catch (e) { console.warn('[hg-patch] v1 patch failed', e); }\n"
content += "\n// ------------------- 广告兜底清理 / seek 续播 -------------------\n"
content += "try {\n" + ios_patch.strip() + "\n} catch (e) { console.warn('[hg-patch] ios patch failed', e); }\n"
content += TAIL

open(os.path.join(OUT, "content.js"), "w", encoding="utf-8", newline="\n").write(content)

hosts = [
    "*://*.huge1-7wnjsk.com/*",
    "*://*.huge2-2hxu9.com/*",
    "*://*.ihgtv-qa7pt2.com/*",
    "*://*.00api-agy5u.com/*",
    "*://*.googlexml.com/*",
]
site_matches = hosts[:3]

manifest = {
    "manifest_version": 3,
    "name": "黄果漫剧 Web 去广告 / 解锁",
    "version": "1.0.0",
    "description": "在浏览器里对 H5 站点应用与 App 端一致的 VIP 解锁与去广告补丁（纯本地脚本，不上传任何数据）",
    "minimum_chrome_version": "102",
    "permissions": ["storage"],
    "host_permissions": hosts,
    "content_scripts": [
        {
            "matches": site_matches,
            "js": ["content.js"],
            "run_at": "document_start",
            "all_frames": True,
        }
    ],
    "action": {"default_popup": "popup.html", "default_title": "黄果漫剧补丁"},
}
with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

POPUP = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <style>
    body { width: 260px; margin: 0; padding: 14px 16px; font: 13px/1.6 -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif; background: #22242a; color: #eee; }
    h1 { font-size: 14px; margin: 0 0 10px; color: #e0ae36; }
    label { display: flex; align-items: center; justify-content: space-between; margin: 8px 0; }
    input[type=text] { width: 100%; box-sizing: border-box; padding: 6px 8px; border-radius: 6px; border: 1px solid #3a3d45; background: #2a2d34; color: #eee; }
    .hint { color: #9aa0aa; font-size: 12px; margin-top: 6px; }
    button { margin-top: 10px; width: 100%; padding: 7px; border: 0; border-radius: 6px; background: #e0ae36; color: #22242a; font-weight: 600; cursor: pointer; }
  </style>
</head>
<body>
  <h1>黄果漫剧补丁</h1>
  <label>额外去广告 <input type="checkbox" id="extraAds" /></label>
  <label>隐藏「选集」条 <input type="checkbox" id="hideStrip" /></label>
  <label for="bindToken">渠道 bind_token</label>
  <input type="text" id="bindToken" placeholder="可留空" />
  <button id="save">保存并刷新当前页</button>
  <div class="hint">改动即时生效；播放页拖动进度后会自动续播。</div>
  <script src="popup.js"></script>
</body>
</html>
"""
open(os.path.join(OUT, "popup.html"), "w", encoding="utf-8", newline="\n").write(POPUP)

POPUP_JS = """const $ = (id) => document.getElementById(id);
chrome.storage.local.get({ extraAds: true, hideStrip: false, bindToken: '' }, (cfg) => {
  $('extraAds').checked = !!cfg.extraAds;
  $('hideStrip').checked = !!cfg.hideStrip;
  $('bindToken').value = cfg.bindToken || '';
});
$('save').addEventListener('click', () => {
  chrome.storage.local.set({
    extraAds: $('extraAds').checked,
    hideStrip: $('hideStrip').checked,
    bindToken: $('bindToken').value.trim(),
  }, () => {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const id = tabs[0] && tabs[0].id;
      if (id) chrome.tabs.reload(id);
    });
    window.close();
  });
});
"""
open(os.path.join(OUT, "popup.js"), "w", encoding="utf-8", newline="\n").write(POPUP_JS)

readme = """# 黄果漫剧 Web 补丁（浏览器扩展）

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
"""
open(os.path.join(OUT, "README.md"), "w", encoding="utf-8", newline="\n").write(readme)

size = os.path.getsize(os.path.join(OUT, "content.js"))
print(f"browser_ext 生成完成：content.js {size} 字节；文件：{sorted(os.listdir(OUT))}")
