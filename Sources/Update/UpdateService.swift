import Foundation
import UIKit

/// 对应 `com.hg.app.ApkUpdater`。
///
/// 语义对齐：
///  - `fetchUpdateInfo(apiBase)`：GET `{apiBase}/app/config`，读 `data.version`
///  - `isNewer(remote, local)`：按 `.` 分段数值比较
///  - `downloadApk`：下载到 cache，校验 zip 魔数，出错返回文案
///  - `installApk`：Android 走 FileProvider + ACTION_VIEW；iOS 走 `itms-services://` / 分享面板
///  - `openExternal`：仅 http/https 才外开
final class UpdateService {

    static let shared = UpdateService()

    private let cacheDirName = "apk"          // 与 Android 缓存目录同名，便于对照
    private let fileName = "update.ipa"       // 对应 update.apk
    private let downloadTimeoutMs = 15_000

    private init() {}

    // MARK: - 配置拉取

    /// 对应 `fetchUpdateInfo`。
    func fetchUpdateInfo(apiBase: String, timeoutMs: Int = AppConfig.configFetchTimeoutMs) throws -> UpdateInfo? {
        let base = apiBase.hasSuffix("/") ? String(apiBase.dropLast()) : apiBase
        let endpoint = base + "/app/config"
        do {
            let json = try HGHTTP.getJSON(endpoint, timeoutMs: timeoutMs)
            let version = (json["data"] as? [String: Any])?["version"] as? [String: Any] ?? json["version"] as? [String: Any]
            guard let version else { return nil }

            var urls: [String] = []
            for key in ["ipa_urls", "apk_urls"] {
                if let list = version[key] as? [Any] {
                    for item in list {
                        let s = (item as? String) ?? String(describing: item)
                        if s.hasPrefix("http") || s.hasPrefix("itms-services://") { urls.append(s) }
                    }
                }
            }
            if urls.isEmpty, let single = version["ipa_url"] as? String, single.hasPrefix("http") {
                urls.append(single)
            }

            let latest = (version["ios"] as? String) ?? (version["android"] as? String) ?? AppConfig.fallbackAppVersion
            let min = (version["ios_min"] as? String) ?? (version["android_min"] as? String) ?? AppConfig.fallbackAppVersion
            let force = (version["ios_force"] as? Bool) ?? (version["android_force"] as? Bool) ?? false

            return UpdateInfo(latest: latest, min: min, force: force, packageURLs: urls)
        } catch {
            HGLog.w("UpdateService", "fetch config failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchUpdateInfoAsync(apiBase: String) async -> UpdateInfo? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: try? self.fetchUpdateInfo(apiBase: apiBase))
            }
        }
    }

    // MARK: - 版本比较

    /// 对应 `isNewer$parts`：按 `.` 切分，非数字段取 0。
    static func parts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
    }

    /// 对应 `isNewer(remote, local)`。
    static func isNewer(_ remote: String, _ local: String) -> Bool {
        let r = parts(remote)
        let l = parts(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    /// 是否强制升级（对应 `force || isNewer(min, current)`）。
    static func isForced(_ info: UpdateInfo, current: String = AppConfig.appVersion) -> Bool {
        info.force || isNewer(info.min, current)
    }

    static func needsUpdate(_ info: UpdateInfo, current: String = AppConfig.appVersion) -> Bool {
        isNewer(info.latest, current)
    }

    // MARK: - 下载 / 安装

    private func cacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(cacheDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 对应 `downloadApk(context, apkUrl)`。
    func downloadPackage(_ urlString: String, progress: @escaping (Double) -> Void) async -> DownloadResult {
        guard urlString.hasPrefix("http://") || urlString.hasPrefix("https://") else {
            return .failure(AppConfig.Text.badApkUrl)
        }
        do {
            let dir = try cacheDirectory()
            let dest = dir.appendingPathComponent(fileName)
            _ = try await HGHTTP.download(urlString, to: dest, progress: progress)
            return .success(dest.path)
        } catch {
            let message = error.localizedDescription
            HGLog.e("UpdateService", "download failed: \(message)")
            return .failure(message.isEmpty ? AppConfig.Text.downloadFailedNetwork : message)
        }
    }

    /// 对应 `installApk(context, apkPath)`：交给系统安装。
    @MainActor
    func installPackage(at path: String) -> DownloadResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(AppConfig.Text.ipaMissing)
        }
        let url = URL(fileURLWithPath: path)
        guard let presenter = Self.topViewController() else {
            return .failure(AppConfig.Text.installFailed)
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = presenter.view
        activity.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        presenter.present(activity, animated: true)
        return .success("请在分享面板中选择安装方式")
    }

    /// 对应 `openExternal(context, url)`：仅 http/https 外开。
    @MainActor
    @discardableResult
    func openExternal(_ urlString: String) -> Bool {
        guard urlString.hasPrefix("http://") || urlString.hasPrefix("https://"),
              let url = URL(string: urlString) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    /// OTA 清单 / itms-services 直接打开（Android 无此分支，iOS 安装渠道）。
    @MainActor
    @discardableResult
    func openItmsServices(_ urlString: String) -> Bool {
        guard urlString.hasPrefix("itms-services://"), let url = URL(string: urlString) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
