import Foundation
import WebKit

/// 对应 `MainActivity$HgBridge`（Android `addJavascriptInterface(this, "HuangGuoNative")`）。
///
/// Android 侧方法是同步调用；iOS 的 `WKScriptMessageHandler` 只能异步，因此 JS 层
/// `HuangGuoNative` 被实现为「同步返回缓存值 + 异步 Promise」的 shim（见 `BridgeScripts.bridgeJS`），
/// 原生侧执行完方法后用 `window.__HG_BRIDGE_RESOLVE__(id, valueJson)` 回填。
///
/// 并发写法：整个类 `@MainActor`。
/// WebKit 的 delegate / message-handler 回调都在主线程投递；Xcode 16（iOS 18 SDK）起
/// `WKScriptMessageHandler` 等协议自带 `@MainActor` 标注，非隔离实现会报错，因此这里统一按主 actor 隔离。
@MainActor
final class WebBridge: NSObject, WKScriptMessageHandler {

    /// 调用描述。跨任务传递时只含字符串/布尔等 Sendable 值。
    struct Call: Sendable {
        var id: String?
        var method: String
        var s0: String?
        var s1: String?
        var b0: Bool?
    }

    private weak var model: ShellModel?
    private weak var webView: WKWebView?

    /// 诊断用键（`Sources/Shell/WebBridge.swift` 单元自测可读）。
    private var handledCalls = 0
    var handledCount: Int { handledCalls }

    init(model: ShellModel, webView: WKWebView) {
        self.model = model
        self.webView = webView
        super.init()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let call = Self.decode(message.body) else { return }
        handledCalls += 1
        dispatch(call)
    }

    private func dispatch(_ call: Call) {
        guard let model else {
            resolve(id: call.id, value: nil)
            return
        }

        switch call.method {
        case "checkUpdate":
            model.requestUpdateFromJS()
            resolve(id: call.id, value: true)

        case "onRouteChange":
            model.routeChanged(call.s0 ?? "")
            resolve(id: call.id, value: true)

        case "onH5SplashReady":
            model.h5SplashReadySignalled()
            resolve(id: call.id, value: true)

        case "logEvent":
            HgAnalytics.shared.logEvent(call.s0 ?? "", propsJSON: call.s1 ?? "")
            resolve(id: call.id, value: true)

        case "logScreen":
            let path = (call.s0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            HgAnalytics.shared.logScreen(path.isEmpty ? "/" : path)
            resolve(id: call.id, value: true)

        case "getPromoBindToken":
            resolve(id: call.id, value: PromoBindStore.token())

        case "getApiBase":
            resolve(id: call.id, value: model.runtimeAPIBase)

        case "getPromoAgentId":
            resolve(id: call.id, value: "")

        case "setPullRefreshEnabled":
            model.setPullRefreshEnabled(call.b0 ?? true)
            resolve(id: call.id, value: true)

        case "openUrl":
            let raw = (call.s0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let url = URL(string: raw) else {
                resolve(id: call.id, value: false)
                return
            }
            model.openURLOrScheme(url)
            resolve(id: call.id, value: true)

        default:
            HGLog.w("HgBridge", "unknown bridge method: \(call.method)")
            resolve(id: call.id, value: nil)
        }
    }

    // MARK: - 回填

    private func resolve(id: String?, value: Any?) {
        guard let id, !id.isEmpty else { return }
        let json = Self.jsonLiteral(value)
        let js = "try{window.__HG_BRIDGE_RESOLVE__&&window.__HG_BRIDGE_RESOLVE__('\(id)', \(json));}catch(e){}"
        (webView ?? model?.webView)?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 把返回值转成 JS 字面量。
    /// 注意：`JSONSerialization` 默认不接受顶层标量，Bool/Number/String 必须带 `.fragmentsAllowed`，
    /// 否则桥接回填会静默变成 `null`（H5 侧 `.then(v => ...)` 拿到 null）。
    nonisolated static func jsonLiteral(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "null" }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        if let text = value as? String {
            return "\"\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return "null"
    }

    // MARK: - 解析

    nonisolated static func decode(_ body: Any) -> Call? {
        var dict: [String: Any]?
        if let text = body as? String, let data = text.data(using: .utf8) {
            dict = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        } else if let asDict = body as? [String: Any] {
            dict = asDict
        }
        guard let dict, let method = dict["method"] as? String else { return nil }
        let args = dict["args"] as? [Any] ?? []
        return Call(
            id: dict["id"] as? String,
            method: method,
            s0: Self.string(args, 0),
            s1: Self.string(args, 1),
            b0: Self.bool(args, 0)
        )
    }

    nonisolated private static func string(_ args: [Any], _ index: Int) -> String? {
        guard index < args.count else { return nil }
        if let s = args[index] as? String { return s }
        if let b = args[index] as? Bool { return b ? "1" : "0" }
        if let n = args[index] as? NSNumber { return n.stringValue }
        return nil
    }

    nonisolated private static func bool(_ args: [Any], _ index: Int) -> Bool? {
        guard index < args.count else { return nil }
        if let b = args[index] as? Bool { return b }
        if let n = args[index] as? NSNumber { return n.boolValue }
        if let s = args[index] as? String { return (s as NSString).boolValue }
        return nil
    }
}

/// 把任意回调塞进 Sendable 盒子，便于在 `Task { @MainActor in ... }` 中安全捕获。
final class CallbackBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
