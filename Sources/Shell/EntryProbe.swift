import Foundation

/// 对应 `com.hg.app.ConfigBootstrap`：种子归一化 + 可达性探测。
enum EntryProbe {

    enum ProbeError: LocalizedError {
        case noSeed
        case unreachable(String)

        var errorDescription: String? {
            switch self {
            case .noSeed: return AppConfig.Text.noSeed
            case .unreachable(let s): return s
            }
        }
    }

    /// 对应 `ConfigBootstrap.normalizeAppEntry`：trim，空 -> 空串，非 `/` 结尾则补 `/`。
    static func normalize(_ seed: String) -> String {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    }

    /// 对应 `ConfigBootstrap.probe`：GET + 跟随重定向，非 2xx 抛错。
    static func probe(_ entry: String, timeoutMs: Int = AppConfig.seedProbeTimeoutMs) throws {
        try HGHTTP.probe(entry, timeoutMs: timeoutMs)
    }

    /// 对应 `ConfigBootstrap.pickReachableAppEntry`：顺序探测，返回首个可达种子。
    static func pickReachable(from seeds: [String], timeoutMs: Int = AppConfig.seedProbeTimeoutMs) throws -> String {
        var lastError: String?
        for seed in seeds {
            let entry = normalize(seed)
            if entry.isEmpty { continue }
            do {
                try probe(entry, timeoutMs: timeoutMs)
                return entry
            } catch {
                lastError = error.localizedDescription
                HGLog.w("ConfigBootstrap", "seed unreachable \(entry): \(error.localizedDescription)")
            }
        }
        throw lastError == nil ? ProbeError.noSeed : ProbeError.unreachable(lastError!)
    }

    /// 主线程安全的异步封装（Android 侧跑在单线程 Executor 上）。
    static func pickReachableAsync(from seeds: [String], timeoutMs: Int = AppConfig.seedProbeTimeoutMs) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try pickReachable(from: seeds, timeoutMs: timeoutMs)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}
