import Foundation

/// 对应 `com.hg.app.AppSeeds`：种子列表 + API 基址推导。
struct SeedCatalog {

    enum Keys {
        static let devHost = "hg.seed.devHost"
        static let apiBaseOverride = "hg.seed.apiBaseOverride"
        static let useDebugSeeds = "hg.seed.useDebugSeeds"
    }

    /// 对应 `AppSeeds.list(debug)`。
    static func list(debug: Bool) -> [String] {
        debug ? debugList() : releaseList()
    }

    /// 对应 `AppSeeds.getReleaseList()`。
    static func releaseList() -> [String] { AppConfig.releaseSeeds }

    /// 对应 `AppSeeds.getDebugList()`：127.0.0.1:5173、10.0.2.2:5173，再叠加 DEBUG_HOST。
    static func debugList() -> [String] {
        var set: [String] = AppConfig.debugSeedHosts.map { "http://\($0):\(AppConfig.debugSeedPort)/" }
        var host = UserDefaults.standard.string(forKey: Keys.devHost) ?? AppConfig.debugHost
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty, host != "127.0.0.1", host != "10.0.2.2" {
            set.append("http://\(host):\(AppConfig.debugSeedPort)/")
        }
        return set
    }

    /// 用户是否强制使用调试种子（设置页开关）。
    static var usesDebugSeeds: Bool {
        UserDefaults.standard.bool(forKey: Keys.useDebugSeeds) || AppConfig.isDebugBuild
    }

    /// 实际参与探测的种子列表（调试优先，与 Android `list(debug)` 语义一致）。
    static func activeSeeds() -> [String] {
        let list = list(debug: usesDebugSeeds)
        return list.isEmpty ? releaseList() : list
    }

    /// 对应 `AppSeeds.apiBaseForAppEntry(entryUrl)`：Android 端恒返回 API 种子（去掉尾部 `/`）。
    static func apiBase(forAppEntry entry: String) -> String {
        if let override = UserDefaults.standard.string(forKey: Keys.apiBaseOverride) {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimSlash(trimmed) }
        }
        return trimSlash(AppConfig.apiSeed)
    }

    /// 对应 `MainActivity.runtimeApiBaseBackup` 初始化。
    static func apiBaseBackup() -> String { trimSlash(AppConfig.apiSeedBackup) }

    static func trimSlash(_ value: String) -> String {
        var s = value
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
