import Foundation

enum HTTPError: LocalizedError {
    case badURL
    case status(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "无效地址"
        case .status(let code): return "HTTP \(code)"
        case .empty: return "无返回数据"
        }
    }
}

/// 统一网络层：全局 UA / Referer / Cookie 自动附加
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppSettings.timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func mergedHeaders(_ headers: [String: String]) -> [String: String] {
        var merged = headers
        if merged["User-Agent"] == nil { merged["User-Agent"] = AppSettings.userAgent }
        let referer = AppSettings.referer
        if !referer.isEmpty, merged["Referer"] == nil { merged["Referer"] = referer }
        let cookie = AppSettings.cookie
        if !cookie.isEmpty, merged["Cookie"] == nil { merged["Cookie"] = cookie }
        return merged
    }

    @discardableResult
    static func request(_ urlString: String,
                        method: String = "GET",
                        headers: [String: String] = [:],
                        body: Data? = nil,
                        timeout: TimeInterval? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw HTTPError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout ?? AppSettings.timeout
        for (key, value) in mergedHeaders(headers) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...399).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }

    static func text(_ urlString: String,
                     headers: [String: String] = [:],
                     timeout: TimeInterval? = nil) async throws -> String {
        let data = try await request(urlString, headers: headers, timeout: timeout)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw HTTPError.empty
        }
        return text
    }

    /// 同步请求，供 JavaScriptCore 桥使用（脚本在工作线程执行，允许阻塞）
    static func sync(_ urlString: String,
                     method: String = "GET",
                     headers: [String: String] = [:],
                     body: Data? = nil,
                     timeout: TimeInterval = 15) -> (data: Data, status: Int, error: String) {
        guard let url = URL(string: urlString) else { return (Data(), 0, "无效地址") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        for (key, value) in mergedHeaders(headers) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let task = session.dataTask(with: request) { data, response, error in
            box.data = data ?? Data()
            box.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            box.error = error?.localizedDescription ?? ""
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout + 5) == .timedOut {
            task.cancel()
            return (Data(), 0, "请求超时")
        }
        return (box.data, box.status, box.error)
    }
}

private final class ResultBox: @unchecked Sendable {
    var data = Data()
    var status = 0
    var error = ""
}
