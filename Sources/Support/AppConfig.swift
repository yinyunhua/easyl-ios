import Foundation
import UIKit

/// 全局常量。数值与 Android 端 `com.hg.app` 一一对应（见 _analysis/com_hg_disasm2.txt）。
enum AppConfig {

    // MARK: - 版本 / 包信息（对应 AndroidManifest + BuildConfig）

    /// Android `package="com.hg.app"`，versionName 2.0.5，versionCode 103
    static let androidPackage = "com.hg.app"
    static let appVersion = "2.0.5"
    static let versionCode = 103
    static let displayName = "黄果漫剧"
    /// 原生外壳版本号（Android `getAppVersion()` 失败时的兜底值 "1.0.0"）
    static let fallbackAppVersion = "1.0.0"

    /// UA 后缀：Android 为 `<系统 UA> HuangGuoApp/<version> HGApp/<version>`
    static var userAgentSuffix: String {
        " HuangGuoApp/\(appVersion) HGApp/\(appVersion)"
    }

    // MARK: - H5 种子（对应 AppSeeds.releaseList / getDebugList / BuildConfig）

    /// 正式种子列表，顺序即探测顺序。
    static let releaseSeeds: [String] = [
        "https://google.huge1-7wnjsk.com/",
        "https://google.huge2-2hxu9.com/",
        "https://google.ihgtv-qa7pt2.com/",
    ]

    /// 调试种子：Android 内置 127.0.0.1:5173 与 10.0.2.2:5173（Vite dev server）。
    static let debugSeedHosts: [String] = ["127.0.0.1", "10.0.2.2"]
    static let debugSeedPort = 5173
    /// 对应 BuildConfig.DEBUG_HOST，默认空串。
    static let debugHost = ""

    /// API 基址种子（AppSeeds.apiBaseForAppEntry / MainActivity.runtimeApiBase）
    static let apiSeed = "https://hgxml.00api-agy5u.com/api"
    /// 备用 API 基址（MainActivity.runtimeApiBaseBackup）
    static let apiSeedBackup = "https://rules.googlexml.com/api"

    // MARK: - 时序（对应 MainActivity 字段默认值）

    /// minSplashMs：品牌闪屏最短展示 2000ms
    static let minSplashMs: UInt64 = 2_000
    /// maxWaitH5SplashMs：等待 H5 闪屏就绪的上限 14000ms
    static let maxWaitH5SplashMs: UInt64 = 14_000
    /// ConfigBootstrap 种子探测超时 2500ms
    static let seedProbeTimeoutMs = 2_500
    /// ApkUpdater 配置请求超时 2500ms
    static let configFetchTimeoutMs = 2_500
    /// 闪屏淡出时长 220ms
    static let splashFadeMs = 220

    // MARK: - 配色（applyAppChromeColors / SwipeRefreshLayout）

    static let chromeColorHex = "#22242A"
    static let accentColorHex = "#E0AE36"
    static let refreshBackgroundHex = "#2A2A30"

    static var chromeColor: UIColor { UIColor(hex: chromeColorHex) ?? .black }
    static var accentColor: UIColor { UIColor(hex: accentColorHex) ?? .orange }
    static var refreshBackgroundColor: UIColor { UIColor(hex: refreshBackgroundHex) ?? .darkGray }

    // MARK: - 文案（与 Android 端字符串逐条对齐）

    enum Text {
        static let connecting = "正在连接…"
        static let retryTitle = "无法连接APP，点此重试"
        static let downloading = "正在下载更新包…"
        static let fetchVersionFailed = "无法获取版本信息"
        static let noApkUrl = "后台未配置安装包地址"
        static let badApkUrl = "安装包地址无效"
        static let badApkFile = "安装包无效，请检查后台 APK 链接"
        static let downloadFailedNetwork = "下载失败，请检查网络或安装包地址"
        static let noSeed = "无可用 H5 种子"
        static let ipaMissing = "安装包不存在"
        static let installFailed = "安装失败"
    }

    // MARK: - 渠道绑定（PromoBindStore）

    static let promoPrefsName = "hg_promo_bind"
    static let promoTokenKey = "bind_token"
    /// 与 Android 端一致的 token 正则（去掉了 .apk 后缀要求，iOS 用于分享链接/剪贴板）
    static let promoTokenPattern = "(?i)hgtv[_-]([A-Za-z0-9]{16,64})(?:\\s*\\(\\d+\\))?(?:\\.apk)?"

    // MARK: - Bridge 名称（addJavascriptInterface 的注入名）

    static let bridgeName = "HuangGuoNative"
    static let messageHandlerName = "HuangGuoNative"

    // MARK: - 本地调试

    /// Debug 构建才启用 debug 种子（对应 BuildConfig.DEBUG）。Release 下用户可在设置页手动覆盖。
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
