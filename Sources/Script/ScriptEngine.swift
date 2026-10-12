import Foundation
import JavaScriptCore

enum ScriptError: LocalizedError {
    case initFailed
    case evaluate(String)
    case noEntryPoint(String)
    case emptyResult(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .initFailed:
            return "脚本引擎初始化失败"
        case .evaluate(let message):
            return "脚本错误：\(message)"
        case .noEntryPoint(let names):
            return "脚本缺少入口函数：\(names)"
        case .emptyResult(let name):
            return "\(name) 没有返回数据"
        case .timeout:
            return "脚本执行超时"
        }
    }
}

/// 用系统自带的 JavaScriptCore 替代原版的 QuickJS 内核，
/// 对外暴露同一套脚本 API：req / post / console / cache / local / kits / app
final class ScriptEngine {
    let source: ScriptSource

    private let context: JSContext
    private var lastException: String?

    init(source: ScriptSource) throws {
        guard let context = JSContext() else { throw ScriptError.initFailed }
        self.source = source
        self.context = context

        context.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception?.toString() ?? "未知异常"
        }

        installBridge()

        _ = context.evaluateScript(Self.prelude)
        if let exception = context.exception {
            context.exception = nil
            throw ScriptError.evaluate(exception.toString() ?? "预置脚本错误")
        }

        _ = context.evaluateScript(source.code)
        if let exception = context.exception {
            context.exception = nil
            throw ScriptError.evaluate(exception.toString() ?? "脚本语法错误")
        }
    }

    // MARK: - 原生桥

    private func installBridge() {
        let sourceId = source.id
        let sourceName = source.name
        let sourceHeaders = source.headers

        let log: @convention(block) (String) -> Void = { message in
            NSLog("[EasylScript] %@", message)
        }

        let request: @convention(block) (String, String, String, String, Double) -> String = { method, url, headersJson, body, seconds in
            Self.performRequest(method: method,
                                url: url,
                                headersJson: headersJson,
                                body: body,
                                timeout: seconds,
                                baseHeaders: sourceHeaders)
        }

        let cacheGet: @convention(block) (String) -> String? = { key in
            UserDefaults.standard.string(forKey: "easyl.cache.\(sourceId).\(key)")
        }
        let cacheSet: @convention(block) (String, String) -> Void = { key, value in
            UserDefaults.standard.set(value, forKey: "easyl.cache.\(sourceId).\(key)")
        }
        let cacheDel: @convention(block) (String) -> Void = { key in
            UserDefaults.standard.removeObject(forKey: "easyl.cache.\(sourceId).\(key)")
        }

        let localGet: @convention(block) (String) -> String? = { name in
            let url = AppPaths.sourceDir(sourceId).appendingPathComponent(AppPaths.safeName(name))
            return try? String(contentsOf: url, encoding: .utf8)
        }
        let localSet: @convention(block) (String, String) -> Void = { name, content in
            let url = AppPaths.sourceDir(sourceId).appendingPathComponent(AppPaths.safeName(name))
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        let localDel: @convention(block) (String) -> Void = { name in
            let url = AppPaths.sourceDir(sourceId).appendingPathComponent(AppPaths.safeName(name))
            try? FileManager.default.removeItem(at: url)
        }

        let md5: @convention(block) (String) -> String = { Crypto.md5($0) }
        let sha1: @convention(block) (String) -> String = { Crypto.sha1($0) }
        let sha256: @convention(block) (String) -> String = { Crypto.sha256($0) }
        let hex: @convention(block) (String) -> String = { Crypto.hex($0) }
        let b64enc: @convention(block) (String) -> String = { Crypto.base64Encode($0) }
        let b64dec: @convention(block) (String) -> String = { Crypto.base64Decode($0) }
        let aes: @convention(block) (Bool, String, String, String) -> String = { encrypt, data, key, iv in
            Crypto.aes(encrypt: encrypt, data: data, key: key, iv: iv)
        }

        let appInfo: @convention(block) () -> String = {
            let payload: [String: Any] = [
                "sourceId": sourceId,
                "sourceName": sourceName,
                "platform": "ios",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: data, encoding: .utf8) else { return "{}" }
            return text
        }

        context.setObject(log, forKeyedSubscript: "__log" as NSString)
        context.setObject(request, forKeyedSubscript: "__req" as NSString)
        context.setObject(cacheGet, forKeyedSubscript: "__cacheGet" as NSString)
        context.setObject(cacheSet, forKeyedSubscript: "__cacheSet" as NSString)
        context.setObject(cacheDel, forKeyedSubscript: "__cacheDel" as NSString)
        context.setObject(localGet, forKeyedSubscript: "__localGet" as NSString)
        context.setObject(localSet, forKeyedSubscript: "__localSet" as NSString)
        context.setObject(localDel, forKeyedSubscript: "__localDel" as NSString)
        context.setObject(md5, forKeyedSubscript: "__md5" as NSString)
        context.setObject(sha1, forKeyedSubscript: "__sha1" as NSString)
        context.setObject(sha256, forKeyedSubscript: "__sha256" as NSString)
        context.setObject(hex, forKeyedSubscript: "__hex" as NSString)
        context.setObject(b64enc, forKeyedSubscript: "__b64enc" as NSString)
        context.setObject(b64dec, forKeyedSubscript: "__b64dec" as NSString)
        context.setObject(aes, forKeyedSubscript: "__aes" as NSString)
        context.setObject(appInfo, forKeyedSubscript: "__appInfo" as NSString)
    }

    private static func performRequest(method: String,
                                       url: String,
                                       headersJson: String,
                                       body: String,
                                       timeout: Double,
                                       baseHeaders: [String: String]) -> String {
        var headers = baseHeaders
        if let data = headersJson.data(using: .utf8),
           let extra = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in extra {
                if let text = JSONValue.string(value) { headers[key] = text }
            }
        }

        let bodyData = body.isEmpty ? nil : Data(body.utf8)
        let result = HTTP.sync(url,
                               method: method.isEmpty ? "GET" : method,
                               headers: headers,
                               body: bodyData,
                               timeout: timeout > 0 ? timeout : 15)

        var payload: [String: Any] = [
            "code": result.status,
            "error": result.error,
            "text": String(data: result.data, encoding: .utf8) ?? "",
            "base64": result.data.base64EncodedString()
        ]
        if payload["text"] as? String == "" , !result.data.isEmpty {
            payload["text"] = String(data: result.data, encoding: .isoLatin1) ?? ""
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"code\":0,\"error\":\"encode-failed\",\"text\":\"\",\"base64\":\"\"}"
        }
        return text
    }

    // MARK: - 调用入口

    /// 按顺序查找第一个存在的入口函数并调用，返回值统一转成 JSON 字符串
    func call(functionNames: [String], arguments: [Any]) throws -> String? {
        guard let function = findFunction(functionNames) else {
            throw ScriptError.noEntryPoint(functionNames.joined(separator: " / "))
        }

        let values: [JSValue] = arguments.compactMap { JSValue(object: $0, in: context) }
        let result = function.call(withArguments: values)

        if let exception = context.exception {
            context.exception = nil
            throw ScriptError.evaluate(exception.toString() ?? "脚本运行时异常")
        }

        guard let result, !result.isNull, !result.isUndefined else { return nil }
        if result.isString { return result.toString() }
        return stringify(result)
    }

    private func findFunction(_ names: [String]) -> JSValue? {
        for name in names {
            if let value = context.objectForKeyedSubscript(name), !value.isUndefined, value.isObject {
                return value
            }
        }
        return nil
    }

    private func stringify(_ value: JSValue) -> String? {
        guard let json = context.objectForKeyedSubscript("JSON") else { return nil }
        let function = json.objectForKeyedSubscript("stringify")
        let result = function?.call(withArguments: [value])
        return result?.toString()
    }

    // MARK: - JS 预置（脚本可见的运行时）

    private static let prelude: String = #"""
    var console = {
        log: function () { __log(Array.prototype.map.call(arguments, __fmt).join(' ')); },
        info: function () { __log(Array.prototype.map.call(arguments, __fmt).join(' ')); },
        warn: function () { __log('[warn] ' + Array.prototype.map.call(arguments, __fmt).join(' ')); },
        error: function () { __log('[error] ' + Array.prototype.map.call(arguments, __fmt).join(' ')); }
    };

    function __fmt(v) {
        if (typeof v === 'object') { try { return JSON.stringify(v); } catch (e) { return String(v); } }
        return String(v);
    }

    function __parse(res) {
        var r;
        try { r = JSON.parse(res); } catch (e) { throw new Error('网络层返回异常: ' + res); }
        if (r.error) { var err = new Error(r.error); err.code = r.code; err.body = r.text; throw err; }
        return r;
    }

    function req(url, options) {
        options = options || {};
        var headers = options.headers || {};
        var body = options.body;
        if (body === undefined || body === null) { body = options.data || ''; }
        if (typeof body === 'object') {
            body = JSON.stringify(body);
            if (!headers['Content-Type']) { headers['Content-Type'] = 'application/json'; }
        }
        var method = String(options.method || 'GET').toUpperCase();
        var r = __parse(__req(method, String(url), JSON.stringify(headers), String(body), Number(options.timeout || 15)));
        if (options.encode === 'base64') { return r.base64; }
        return r.text;
    }

    function post(url, body, options) {
        options = options || {};
        options.method = 'POST';
        if (body !== undefined) { options.body = body; }
        return req(url, options);
    }

    var cache = {
        get: function (k) { var v = __cacheGet(String(k)); return (v === null || v === undefined) ? null : v; },
        set: function (k, v) { __cacheSet(String(k), v === undefined ? '' : String(v)); },
        del: function (k) { __cacheDel(String(k)); }
    };

    var local = {
        get: function (n) { var v = __localGet(String(n)); return (v === null || v === undefined) ? '' : v; },
        set: function (n, c) { __localSet(String(n), String(c)); },
        del: function (n) { __localDel(String(n)); }
    };

    var kits = {
        md5: function (s) { return __md5(String(s)); },
        sha1: function (s) { return __sha1(String(s)); },
        sha256: function (s) { return __sha256(String(s)); },
        hex: function (s) { return __hex(String(s)); },
        base64Encode: function (s) { return __b64enc(String(s)); },
        base64Decode: function (s) { return __b64dec(String(s)); },
        urlEncode: function (s) { return encodeURIComponent(String(s)); },
        urlDecode: function (s) { try { return decodeURIComponent(String(s)); } catch (e) { return String(s); } },
        aesEncrypt: function (data, key, iv) { return __aes(true, String(data), String(key), String(iv || '')); },
        aesDecrypt: function (data, key, iv) { return __aes(false, String(data), String(key), String(iv || '')); },
        now: function () { return Date.now(); },
        random: function (n) { return Math.floor(Math.random() * (n || 1000000)); },
        timestamp: function (t) { return Math.floor(new Date(String(t).replace(/-/g, '/')).getTime() / 1000); },
        timeAgo: function (t) {
            var diff = Math.floor(Date.now() / 1000) - Number(t);
            if (diff < 60) { return '刚刚'; }
            if (diff < 3600) { return Math.floor(diff / 60) + ' 分钟前'; }
            if (diff < 86400) { return Math.floor(diff / 3600) + ' 小时前'; }
            if (diff < 2592000) { return Math.floor(diff / 86400) + ' 天前'; }
            return new Date(Number(t) * 1000).toISOString().slice(0, 10);
        }
    };

    var app = JSON.parse(__appInfo());
    """#
}
