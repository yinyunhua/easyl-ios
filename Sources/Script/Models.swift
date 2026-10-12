import Foundation

/// 一个「源」= 一个 JS 脚本 + 独立请求头（对应原版 Easyl 的源管理）
struct ScriptSource: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var location: String        // 脚本地址；本地导入为 "local"
    var code: String            // 脚本正文
    var enabled: Bool = true
    var userAgent: String?
    var referer: String?
    var cookie: String?

    var isRemote: Bool { location.hasPrefix("http") }

    var headers: [String: String] {
        var result: [String: String] = [:]
        if let userAgent, !userAgent.isEmpty { result["User-Agent"] = userAgent }
        if let referer, !referer.isEmpty { result["Referer"] = referer }
        if let cookie, !cookie.isEmpty { result["Cookie"] = cookie }
        return result
    }
}

struct MediaItem: Hashable {
    var id: String
    var tid: String?
    var title: String
    var poster: String?
    var remark: String?
    var year: String?
    var type: String?
    var sourceKey: String

    var uniqueKey: String { "\(sourceKey)|\(id)|\(title)" }
    var posterURL: URL? { poster.flatMap { URL(string: $0) } }
}

struct HomeSection: Hashable {
    var title: String
    var items: [MediaItem]
}

struct Episode: Hashable {
    var name: String
    var id: String
    var flag: String

    var uniqueKey: String { "\(flag)|\(id)|\(name)" }
}

struct PlayLine: Hashable {
    var name: String
    var episodes: [Episode]
}

struct MediaDetail {
    var title: String
    var poster: String?
    var desc: String?
    var year: String?
    var lines: [PlayLine]
}

struct PlayInfo {
    var url: String
    var type: String?
    var headers: [String: String]
    var danmakuId: String?
    var danmakuName: String?
}
