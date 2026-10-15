import Foundation

/// 对应 `com.hg.app.HgAnalytics`。
///
/// Android 端底层是 FirebaseAnalytics（反射调用）；iOS 端改为可插拔接收器：
///  - 默认落本地日志缓冲（`HGLog`），设置页可见；
///  - 可选上报开关打开后，把同名/同参数的事件 POST 到 `{apiBase}/app/log`（字段与 Android 端一致）。
///
/// 参数清洗规则与 Android 完全一致：
///  - name/key：trim -> lowercase -> `[^a-z0-9_]` 替换为 `_` -> 空或首字符非字母则丢弃 -> 截断 40 字符
///  - 字符串值截断 100 字符；布尔值转 "1"/"0"；数值按 Double 上报
final class HgAnalytics {

    static let shared = HgAnalytics()

    private let queue = DispatchQueue(label: "com.hg.app.analytics")
    private(set) var isEnabled = false
    private var appContextReady = false
    private var remoteBase: String?

    /// 事件缓冲，设置页诊断用。
    private(set) var recentEvents: [Event] = []

    struct Event: Identifiable {
        let id = UUID()
        let date: Date
        let name: String
        let params: [String: Any]
    }

    private init() {}

    // MARK: - init(context)

    /// 对应 `HgAnalytics.init(context)`：初始化底层 SDK 并上报 `app_open`（只在上报一次）。
    func start(remoteBase: String?) {
        let firstStart: Bool = queue.sync {
            self.remoteBase = remoteBase
            let first = !appContextReady
            appContextReady = true
            isEnabled = true
            return first
        }
        guard firstStart else { return }
        HGLog.i("HgAnalytics", "analytics ready (remote=\(remoteBase ?? "off"))")
        logEvent("app_open", propsJSON: "")
    }

    /// 对应 `HgAnalytics` 在 FirebaseApp 缺失时打印的 "Firebase init skipped"。
    func markSkipped(_ reason: String) {
        HGLog.w("HgAnalytics", "Firebase init skipped: \(reason)")
    }

    // MARK: - 上报入口（HGApp.logEvent / HGApp.logScreen 落到这里）

    func logEvent(_ name: String, propsJSON: String) {
        guard queue.sync(execute: { isEnabled }) else { return }
        guard let safeName = sanitizeEventName(name) else { return }
        var params: [String: Any] = [:]
        if !propsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let data = propsJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = object as? [String: Any] {
            for (key, value) in dict {
                guard let safeKey = sanitizeParamKey(key) else { continue }
                if value is NSNull { continue }
                if let flag = value as? Bool {
                    params[safeKey] = flag ? "1" : "0"
                } else if let number = value as? NSNumber {
                    params[safeKey] = number.doubleValue
                } else {
                    params[safeKey] = String(String(describing: value).prefix(100))
                }
            }
        }
        record(name: safeName, params: params, raw: propsJSON)
    }

    func logScreen(_ path: String) {
        guard queue.sync(execute: { isEnabled }) else { return }
        let screen = String(path.prefix(100))
        record(name: "screen_view", params: ["screen_name": screen, "screen_class": "WebView"], raw: "{\"screen_name\":\"\(screen)\"}")
    }

    private func record(name: String, params: [String: Any], raw: String) {
        queue.async {
            self.recentEvents.append(Event(date: Date(), name: name, params: params))
            if self.recentEvents.count > 200 { self.recentEvents.removeFirst(self.recentEvents.count - 200) }
        }
        HGLog.d("HgAnalytics", "logEvent name=\(name) params=\(raw.prefix(200))")
        reportRemote(name: name, params: params)
    }

    /// 可选远端上报：`POST {base}/app/log`，body 与 Android 端事件字段对齐。
    private func reportRemote(name: String, params: [String: Any]) {
        let base = queue.sync { remoteBase ?? "" }
        guard !base.isEmpty else { return }
        let endpoint = base.hasSuffix("/") ? base + "app/log" : base + "/app/log"
        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HGHTTP.userAgent(nil), forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "platform": "ios",
            "app_version": AppConfig.appVersion,
            "version_code": AppConfig.versionCode,
            "name": name,
            "params": params,
            "ts": Int(Date().timeIntervalSince1970),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error { HGLog.d("HgAnalytics", "remote log failed: \(error.localizedDescription)") }
        }.resume()
    }

    // MARK: - 清洗（与 Android 逐行对齐）

    /// 对应 `sanitizeEventName`。
    func sanitizeEventName(_ name: String) -> String? {
        sanitize(name)
    }

    /// 对应 `sanitizeParamKey`。
    func sanitizeParamKey(_ key: String) -> String? {
        sanitize(key)
    }

    private func sanitize(_ raw: String) -> String? {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let replaced = lowered.replacingOccurrences(of: "[^a-z0-9_]", with: "_", options: .regularExpression)
        guard let first = replaced.first, first.isLetter else { return nil }
        return String(replaced.prefix(40))
    }

    func setRemoteBase(_ base: String?) {
        queue.sync { remoteBase = base }
    }

    func reset() {
        queue.sync {
            recentEvents.removeAll()
        }
    }
}
