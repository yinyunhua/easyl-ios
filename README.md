# EasylForIOS —— `yimu-v1.7.1.apk` 的 iOS 功能级移植

原包信息：`com.easyl.app`，versionName 1.7.1，versionCode 37，minSdk 26 / targetSdk 35。
技术栈：ExoPlayer(media3) + MPV 双内核、Anime4K GLSL 着色器、迅雷 SDK（磁力/离线/加速）、M3U 直播 + EPG、
弹幕（jsdanmu）、QuickJS 源脚本系统、豆瓣 rexxar 接口、后台下载服务（RoomHost / Download / Thunder）。

> **一句话结论**：APK 里的 `libmpv.so`、`libxl_thunder_sdk.so`、`libquickjs-android-wrapper.so` 都是 Android ABI 二进制，
> iOS 上不存在任何「APK → IPA」转换通道。真正的移植只能是 **用 Swift 重写同等功能**，本工程就是这套重写。

---

## 一、模块对照

| Android 原实现 | iOS 移植实现 | 状态 |
|---|---|---|
| ExoPlayer + MPV 双内核、MPV 兜底 | `AVPlayer` / `AVPlayerViewController`（HLS、MP4、HEVC、画中画、AirPlay） | 已移植 |
| QuickJS 源脚本（`SourceScriptRunner`） | `JavaScriptCore` + `ScriptEngine`（同一套 `req/cache/local/kits` API） | 已移植 |
| 弹幕（jsdanmu / danmuSources） | `DanmakuLayout` + `DanmakuOverlay`（滚动/顶部/底部轨道，30fps） | 已移植 |
| M3U 直播 + `EpgEntry` | `M3UParser` + `EPGClient`（JSON / XMLTV） | 已移植 |
| 豆瓣 frodo/rexxar 接口 | `DoubanClient`（URLSession 直连） | 已移植 |
| DownloadService / ThunderService 下载 | `DownloadManager`（URLSession 后台会话 + 断点续传） | 已移植（仅直链） |
| 全局 UA / Referer / Cookie 设置 | `SettingsView` + `AppSettings`（源级请求头可覆盖） | 已移植 |
| Anime4K 着色器 | 未移植（需 Metal 重写 mpv 渲染管线） | 未移植 |
| 迅雷 SDK：P2SP 加速、磁力、云盘离线 | 不可移植（闭源 Android/Windows 二进制） | 未移植 |
| CencProbe（DRM/CENC 探测） | 未移植 | 未移植 |
| RoomHostService（一起看房间） | 未移植 | 未移植 |
| 友盟统计、签到/金币等运营模块 | 未移植（自签包无需统计） | 未移植 |

---

## 二、目录结构

```
EasylForIOS/
├── project.yml                     # XcodeGen 工程描述（改 bundle id / 版本在这里）
├── Resources/
│   ├── Info.plist                  # 已放开 ATS(HTTP 源)、后台音频、文件共享
│   ├── demo.js                     # 内置演示源（同时是源协议参考实现）
│   ├── demo.m3u                    # 内置演示直播源
│   └── Assets.xcassets/            # 单尺寸 AppIcon + 主题色
├── Sources/
│   ├── App/                        # 入口 + Tab 结构
│   ├── Support/                    # HTTP、设置、加密工具、JSON、签名解析
│   ├── Script/                     # JS 引擎桥、调度服务、源存储、数据模型
│   ├── Home/                       # 首页 / 详情
│   ├── Search/                     # 多源聚合搜索 + 豆瓣
│   ├── Player/                     # 播放器、字幕
│   ├── Danmaku/                    # 弹幕布局与渲染
│   ├── Live/                       # M3U 直播 + EPG
│   ├── Download/                   # 后台下载
│   ├── Douban/                     # 豆瓣客户端
│   └── Settings/                   # 设置、源管理、签名状态
├── scripts/
│   ├── build_unsigned_ipa.sh       # Mac 本地一键出未签名 IPA
│   └── make_icon.py                # 纯标准库生成 1024 图标
└── .github/workflows/build-ipa.yml # 云端 macOS 构建未签名 IPA
```

---

## 三、构建出未签名 IPA

### 方式一：GitHub Actions（不需要 Mac）
1. 把整个 `EasylForIOS/` 推到 GitHub 仓库；
2. 仓库 **Actions → Build unsigned IPA → Run workflow**；
3. 跑完在 Artifacts 里下载 `EasylForIOS-unsigned-ipa`（解压得到 `.ipa`）。

### 方式二：Mac 本地
```bash
brew install xcodegen
cd EasylForIOS
bash scripts/build_unsigned_ipa.sh
# 产物：EasylForIOS-unsigned.ipa
```

改包名/显示名：`project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER`，显示名在 `Resources/Info.plist` 的 `CFBundleDisplayName`。

---

## 四、自签安装（你走这条）

两种典型用法都行：

- **导入证书 + IPA 在手机上签**（ESign / 轻松签 / Feather）：
  证书 = `p12 + 密码`，描述文件必须含本机 UDID（开发/Ad Hoc 类型），企业证书则走 `ProvisionsAllDevices`；
  工具里选择「签名 → 安装」，扩展/组件要全签（本工程没有扩展，不会踩坑）。
- **电脑端签**（Sideloadly / AltStore）：登录 Apple ID，拖入 IPA，直接装。

限制备忘：
- 免费 Apple ID：**7 天**、同时最多 3 个 App；
- 付费开发者账号：1 年，Ad Hoc 描述文件每年最多 100 台 UDID；
- 企业证书：随时可能被批量吊销，掉签后**不要先卸载**，用同一 Bundle ID 覆盖安装，数据保留；
- iOS 16+ 用免费/开发证书签的包，需要开「设置 → 隐私与安全性 → 开发者模式」；
- 装完到「设置 → 通用 → VPN与设备管理」信任证书。

App 内「设置 → 签名状态」会解析 `embedded.mobileprovision`，直接显示**到期时间和剩余天数**，用来盯 7 天很省事。

---

## 五、源脚本协议

脚本在 `JavaScriptCore` 里执行（替代原版 QuickJS），每个源独立 `JSContext` + 独立串行队列，30 秒超时保护。

### 入口函数（按顺序取第一个存在的）

| 入口 | 别名 | 参数 | 期望返回 |
|---|---|---|---|
| `home()` | `homeContent` / `getHome` / `homeSections` | — | `{sections:[{title, items:[item]}]}` |
| `category(tid,page)` | `categoryContent` / `getCategory` | 分类 id、页码 | `{items:[item]}` |
| `search(keyword,page)` | `searchContent` / `getSearch` | 关键词、页码 | `{items:[item]}` |
| `detail(id)` | `detailContent` / `getDetail` | 条目 id | `{title, poster, desc, year, lines:[{name, episodes:[{name,id,flag}]}]}` |
| `play(flag,id)` | `playerContent` / `getPlay` | 线路名、剧集 id | `{url, type, headers:{}, danmakuId}` |
| `danmaku(id,name)` | `danmu` / `getDanmaku` | 剧集 id、名称 | `{comments:[{text,time,mode,color}]}` |

`item` 字段兼容：`id/vod_id`、`title/name/vod_name`、`poster/pic/cover`、`remark/vod_remarks`。
`detail` 同时兼容 TVBox 风格 `playFrom` + `playList` 二维数组。

### 运行时 API

```javascript
req(url, { method, headers, body, timeout, encode: 'base64' })   // 返回文本；encode=base64 返回二进制
post(url, body, options)
console.log(...) / warn / error
cache.get(k) cache.set(k, v) cache.del(k)      // UserDefaults，按源隔离
local.get(n) local.set(n, text) local.del(n)   // 沙盒文件，按源隔离
kits.md5 / sha1 / sha256 / hex / base64Encode / base64Decode
kits.urlEncode / urlDecode / aesEncrypt / aesDecrypt / now / random / timestamp / timeAgo
app.sourceId / app.sourceName / app.platform / app.appVersion
```

示例见 `Resources/demo.js`。导入方式：App 内「设置 → 源管理 → +」，填远程 JS 地址或直接粘贴脚本正文。

---

## 六、已知差异 / 注意事项

1. **迅雷链路**：P2SP 加速、磁力解析、云盘离线需要迅雷官方 SDK，iOS 无对应二进制；HTTP 层的直链播放不受影响。
2. **Anime4K**：原来跑在 mpv 的 GLSL 管线里，iOS 走 VideoToolbox 硬解；要做画质增强需要写 Metal shader（未实现）。
3. **HLS 下载**：只能在线播，`m3u8` 分片不做离线合并。
4. **HTTP 源**：`Info.plist` 已开 `NSAllowsArbitraryLoads`，否则大量国内源直接请求失败。
5. **脚本卡死**：JS 无法安全强杀死循环线程，超时后该源会返回「脚本执行超时」，重启 App 可恢复。
6. 本工程**不含任何第三方 App 的代码或资源**，全部为按功能重新实现的 Swift 代码 + 自带演示数据。
