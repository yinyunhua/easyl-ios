import Foundation
import UIKit

/// 同步 HTTP 工具，行为对齐 Android 端 `HttpURLConnection` 用法：
/// - `probe` 对应 `ConfigBootstrap.probe`：GET、跟随 30x、Accept: text/html,*/*，非 2xx 抛 `HTTP <code>`。
/// - `getJSONObject` 对应 `ApkUpdater.fetchUpdateInfo`：GET、Accept: application/json、超时 2500ms。
enum HGHTTP {

    enum Failure: LocalizedError {
        case badURL(String)
        case status(String)
        case transport(String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let s): return "非法地址：\(s)"
            case .status(let s): return s
            case .transport(let s): return "网络错误：\(s)"
            case .decode(let s): return "解析失败：\(s)"
            }
        }
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    static func userAgent(_ webViewUA: String?) -> String {
        let base = webViewUA ?? defaultUserAgent()
        return base + AppConfig.userAgentSuffix
    }

    /// 默认 UA（不依赖 UIDevice，可在后台线程安全调用）。
    static func defaultUserAgent() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion)_\(os.minorVersion)"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(version) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    }

    /// 线程安全的值盒：`URLSession` 的 completion 在新 SDK 里是 @Sendable 闭包，
    /// 直接改写捕获的 `var` 会触发并发写检查，这里统一用锁盒收发结果。
    private final class Locked<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: T

        init(_ value: T) { storage = value }

        var value: T {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func set(_ newValue: T) {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    /// 同步请求，返回 (statusCode, data)。调用方应保证不在主线程调用。
    static func syncRequest(
        _ urlString: String,
        method: String = "GET",
        accept: String = "application/json",
        timeoutMs: Int = AppConfig.configFetchTimeoutMs,
        userAgent: String? = nil
    ) throws -> (Int, Data) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Failure.badURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Double(timeoutMs) / 1000.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent ?? Self.userAgent(nil), forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        let box = Locked<Result<(Int, Data), Error>>(.failure(Failure.transport("请求超时")))
        let finished = Locked<Bool>(false)

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                box.set(.failure(Failure.transport(error.localizedDescription)))
            } else if let http = response as? HTTPURLResponse {
                box.set(.success((http.statusCode, data ?? Data())))
            } else {
                box.set(.failure(Failure.transport("无 HTTP 响应")))
            }
            finished.set(true)
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + Double(timeoutMs) / 1000.0 + 5)
        if !finished.value { task.cancel() }

        switch box.value {
        case .success(let pair): return pair
        case .failure(let err): throw err
        }
    }

    /// 对应 ConfigBootstrap.probe：仅校验可达性，非 2xx 抛错。
    static func probe(_ urlString: String, timeoutMs: Int = AppConfig.seedProbeTimeoutMs) throws {
        let (code, _) = try syncRequest(urlString, accept: "text/html,*/*", timeoutMs: timeoutMs)
        guard (100..<300).contains(code) else {
            throw Failure.status("HTTP \(code)")
        }
    }

    /// 对应 ApkUpdater.fetchUpdateInfo：GET JSON。
    static func getJSON(_ urlString: String, timeoutMs: Int = AppConfig.configFetchTimeoutMs) throws -> [String: Any] {
        let (code, data) = try syncRequest(urlString, accept: "application/json", timeoutMs: timeoutMs)
        guard (200..<300).contains(code) else {
            throw Failure.status("HTTP \(code)")
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = obj as? [String: Any] else { throw Failure.decode("非 JSON 对象") }
            return dict
        } catch let err as Failure {
            throw err
        } catch {
            throw Failure.decode(error.localizedDescription)
        }
    }

    /// 异步 JSON（主流程用，避免阻塞 UI）。
    static func getJSONAsync(_ urlString: String, timeoutMs: Int = AppConfig.configFetchTimeoutMs) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do { cont.resume(returning: try getJSON(urlString, timeoutMs: timeoutMs)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// 对应 ApkUpdater.downloadApk：流式下载并回报进度。
    static func download(
        _ urlString: String,
        to destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            throw Failure.badURL(urlString)
        }
        guard scheme == "http" || scheme == "https" else {
            throw Failure.badURL(AppConfig.Text.badApkUrl)
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent(nil), forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.status("下载失败（HTTP \(http.statusCode)）")
        }
        let expected = Double(response.expectedContentLength)
        var data = Data()
        data.reserveCapacity(expected > 0 ? Int(expected) : 1 << 20)
        var lastTick = 0.0

        for try await byte in bytes {
            data.append(byte)
            if expected > 0 {
                let ratio = Double(data.count) / expected
                if ratio - lastTick > 0.01 {
                    lastTick = ratio
                    progress(ratio)
                }
            }
        }
        guard !data.isEmpty else { throw Failure.status(AppConfig.Text.badApkFile) }
        // 校验：APK/IPA 均为 zip 容器，PK\x03\x04 开头（对应 isLikelyApk 的魔数判定）
        let magic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        if data.count >= 4, Array(data.prefix(4)) != magic {
            throw Failure.status(AppConfig.Text.badApkFile)
        }
        try data.write(to: destination, options: .atomic)
        progress(1.0)
        return destination
    }
}
