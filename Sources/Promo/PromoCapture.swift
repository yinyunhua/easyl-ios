import Foundation
import UIKit
#if canImport(AdServices)
import AdServices
#endif

/// 对应 `com.hg.app.PromoBindCapture`：多渠道采集渠道绑定 token。
///
/// Android 侧 5 条来源 → iOS 对等实现：
///  1. captureFromIntent        → `capture(from: URL)`：openURL / Universal Link 的 `bind_token`
///  2. captureFromInstallReferrer → AdServices `AAAttribution.attributionToken()`（iOS 14.3+）
///  3. captureFromApkFilename   → `captureFromPasteboard()`：剪贴板里的分享文本/文件名
///  4. scanDownloadDirectories / captureFromDownloadManager → `captureFromInboxFiles()`：Documents/Inbox 内的 ipa 文件名
///  5. captureFromInstalledApk  → `captureFromBundleMarker()`：包内 `promo_bind_token.txt`（预置渠道包）
enum PromoCapture {

    /// 与 Android `APK_TOKEN_REGEX` 同源。
    static let tokenRegex = AppConfig.promoTokenPattern

    /// token 白名单：只允许常见 token 字符，长度 1~128。
    /// 作用是把写进 UserDefaults、再注入 H5（`window.__HG_BRIDGE_CACHE__.promoBindToken`）
    /// 的值限制在安全字符集内，避免引号/反斜杠破坏注入脚本。
    private static let tokenAllowlist = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.:-")

    /// 统一落库入口：先校验字符集与长度，再写 `PromoBindStore`。
    @discardableResult
    static func store(_ raw: String, source: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ tokenAllowlist.contains($0) }) else {
            HGLog.w("PromoBindCapture", "token rejected by allowlist (source=\(source), len=\(trimmed.count))")
            return nil
        }
        if PromoBindStore.save(trimmed) {
            HGLog.i("PromoBindCapture", "token captured from \(source)")
        }
        return trimmed
    }

    // MARK: - 入口：对应 MainActivity.onCreate / onResume / onNewIntent 的调用点

    /// 对应 `captureAll(context, intent)`。
    /// 注意：iOS 16 起直接读系统剪贴板会弹「允许粘贴？」授权框，因此自动路径默认**不读剪贴板**，
    /// 只保留 intent/归因/包内标记等无弹框来源；剪贴板扫描需显式调用 `captureFromPasteboard()`。
    static func captureAll(launchURL: URL?, includePasteboard: Bool = false) {
        if let launchURL { capture(from: launchURL) }
        captureFromBundleMarker()
        if includePasteboard { captureFromPasteboard() }
        captureFromInboxFiles()
        captureFromAttribution()
    }

    // MARK: - 1. URL / Scheme / Universal Link

    /// 对应 `captureFromIntent` + `extractBindToken(Uri)`。
    @discardableResult
    static func capture(from url: URL) -> String? {
        if let token = extractBindToken(from: url) {
            return store(token, source: "url")
        }
        return nil
    }

    /// 对应 `extractBindToken`：先取 `bind_token` 查询参数，再退回「末段文件名/文本」正则提取。
    static func extractBindToken(from url: URL) -> String? {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let value = comps.queryItems?.first(where: { $0.name.lowercased() == "bind_token" })?.value {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        let last = url.lastPathComponent
        return extractTokenFromName(last)
    }

    /// 对应 `parseReferrerQuery(String)`：`k=v&k=v` 形式，key 不区分大小写，值 URI 解码。
    static func parseReferrerQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for pair in trimmed.split(separator: "&") {
            let parts = pair.split(separator: "=", omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            if key.lowercased() == "bind_token" {
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { return clean }
            }
        }
        return extractTokenFromName(trimmed)
    }

    /// 对应 `extractTokenFromApkName`：正则捕获组取 token。
    static func extractTokenFromName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: tokenRegex, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range), match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: trimmed) else { return nil }
        let token = String(trimmed[captured]).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - 2. 安装来源（对应 InstallReferrer）

    /// 对应 `captureFromInstallReferrer`：iOS 侧用 AdServices 归因 token。
    /// 需要 iOS 14.3+ 与已链接 AdServices framework；不可用时静默跳过（与 Android 端 catch 后继续一致）。
    static func captureFromAttribution() {
        if #available(iOS 14.3, *) {
            #if canImport(AdServices)
            DispatchQueue.global(qos: .utility).async {
                do {
                    let token = try AAAttribution.attributionToken()
                    guard !token.isEmpty else { return }
                    let key = "aa_attribution_token"
                    let store = UserDefaults(suiteName: PromoBindStore.prefsName) ?? .standard
                    if store.string(forKey: key) != token {
                        store.set(token, forKey: key)
                        store.synchronize()
                        HGLog.i("PromoBindCapture", "attribution token captured (\(token.count) chars)")
                    }
                } catch {
                    HGLog.d("PromoBindCapture", "install referrer unavailable: \(error.localizedDescription)")
                }
            }
            #else
            HGLog.d("PromoBindCapture", "install referrer unavailable: AdServices not linked")
            #endif
        } else {
            HGLog.d("PromoBindCapture", "install referrer unavailable: iOS < 14.3")
        }
    }

    // MARK: - 3. 剪贴板（对应安装包文件名扫描）

    /// 对应 `captureFromApkFilename` + `scanDownloadDirectories` 的文本侧：扫描剪贴板里的分享串。
    ///
    /// iOS 16 起读剪贴板会弹「允许粘贴？」授权框，因此只在用户显式触发（设置页「立即重扫」）时才调用。
    @discardableResult
    static func captureFromPasteboard() -> String? {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else {
            HGLog.d("PromoBindCapture", "pasteboard scan skipped: no string content")
            return nil
        }
        var candidates: [String] = []
        if let text = pasteboard.string, !text.isEmpty { candidates.append(text) }
        if let url = pasteboard.url?.absoluteString, !url.isEmpty { candidates.append(url) }
        candidates.append(contentsOf: pasteboard.strings ?? [])
        if candidates.isEmpty {
            HGLog.d("PromoBindCapture", "pasteboard scan denied or empty")
            return nil
        }

        for raw in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.lowercased().hasPrefix("http") {
                if let url = URL(string: trimmed), let token = extractBindToken(from: url) {
                    return store(token, source: "pasteboard.url")
                }
                if let comps = URLComponents(string: trimmed),
                   let query = comps.percentEncodedQuery,
                   let token = parseReferrerQuery(query.replacingOccurrences(of: "%26", with: "&")) {
                    return store(token, source: "pasteboard.query")
                }
            } else if trimmed.contains("bind_token"), let token = parseReferrerQuery(trimmed) {
                return store(token, source: "pasteboard.referrer")
            } else if let token = extractTokenFromName(trimmed) {
                return store(token, source: "pasteboard.name")
            }
        }
        return nil
    }

    // MARK: - 4. Inbox 文件名扫描（对应扫描下载目录 / DownloadManager）

    /// 对应 `scanDownloadDirectories` + `captureFromDownloadManager`：扫描收到的 ipa/apk 文件名。
    static func captureFromInboxFiles() {
        let fm = FileManager.default
        var dirs: [URL] = []
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            dirs.append(docs)
            dirs.append(docs.appendingPathComponent("Inbox", isDirectory: true))
        }
        guard let regex = try? NSRegularExpression(pattern: "\\.(ipa|apk)$", options: [.caseInsensitive]) else { return }
        for dir in dirs {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            let sorted = children.sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            for file in sorted {
                let name = file.lastPathComponent
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                guard regex.firstMatch(in: name, options: [], range: range) != nil else { continue }
                if let token = extractTokenFromName(name), store(token, source: "inbox:\(name)") != nil {
                    return
                }
            }
        }
    }

    // MARK: - 5. 包内渠道标记（对应从已安装 APK 读取 token）

    /// 对应 `captureFromInstalledApk` + `extractTokenFromSigningBlock`：
    /// iOS 没有签名块扩展区，渠道包改为在 bundle 内埋 `promo_bind_token.txt`（内容为 `hgtv_<token>.apk` 或裸 token）。
    /// 默认工程不含该文件，渠道包打进该文件后此通道即生效。
    static func captureFromBundleMarker() {
        guard let url = Bundle.main.url(forResource: "promo_bind_token", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let token = extractTokenFromName(trimmed) ?? trimmed
        store(token, source: "bundle-marker")
    }
}
