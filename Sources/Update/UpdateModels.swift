import Foundation

/// 对应 `com.hg.app.ApkUpdater$UpdateInfo` / `$DownloadResult`。
struct UpdateInfo: Equatable {
    /// 对应 `latest`（Android 读 `data.version.android`，iOS 优先 `ios`）
    var latest: String
    /// 对应 `min`
    var min: String
    /// 对应 `force`（`android_force` / `ios_force`）
    var force: Bool
    /// 对应 `apkUrls`（iOS 端还可含 `ipa_urls` / `itms-services` 清单地址）
    var packageURLs: [String]

    var firstURL: String? { packageURLs.first }
}

struct DownloadResult: Equatable {
    /// 对应 `ok`
    var ok: Bool
    /// 对应 `message`
    var message: String

    static func failure(_ message: String) -> DownloadResult { DownloadResult(ok: false, message: message) }
    static func success(_ message: String) -> DownloadResult { DownloadResult(ok: true, message: message) }
}

/// 对应 `MainActivity.notifyUpdateResult` 的 H5 回传载荷。
struct UpdateOutcome: Equatable {
    var ok: Bool
    var message: String
}
