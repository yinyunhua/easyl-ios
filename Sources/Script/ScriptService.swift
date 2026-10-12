import Foundation

/// 每个源一个 JSContext + 一条串行队列；带超时保护，脚本卡死不会拖住 UI
final class ScriptService {
    static let shared = ScriptService()

    private struct Entry {
        let queue: DispatchQueue
        let engine: ScriptEngine
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    private init() {}

    func dropCache(for id: String? = nil) {
        lock.lock()
        if let id {
            entries[id] = nil
        } else {
            entries.removeAll()
        }
        lock.unlock()
    }

    private func entry(for source: ScriptSource) throws -> Entry {
        lock.lock()
        defer { lock.unlock() }
        if let cached = entries[source.id] { return cached }
        let engine = try ScriptEngine(source: source)
        let queue = DispatchQueue(label: "easyl.script.\(AppPaths.safeName(source.id))", qos: .userInitiated)
        let entry = Entry(queue: queue, engine: engine)
        entries[source.id] = entry
        return entry
    }

    private func perform<T>(_ source: ScriptSource,
                            timeout: TimeInterval,
                            _ body: @escaping (ScriptEngine) throws -> T) async throws -> T {
        let entry = try entry(for: source)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let flag = OnceFlag()
            let finish: (Result<T, Error>) -> Void = { result in
                guard flag.consume() else { return }
                continuation.resume(with: result)
            }

            entry.queue.async {
                do {
                    finish(.success(try body(entry.engine)))
                } catch {
                    LogBus.shared.log("调用失败: \(error.localizedDescription)", source: source.id)
                    finish(.failure(error))
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.failure(ScriptError.timeout))
            }
        }
    }

    // MARK: - 业务入口

    func home(_ source: ScriptSource) async throws -> [HomeSection] {
        let json = try await perform(source, timeout: 30) { engine in
            try engine.call(functionNames: ["home", "homeContent", "getHome", "homeSections"], arguments: [])
        }
        guard let json else { throw ScriptError.emptyResult("home") }
        return Self.parseSections(json, source: source)
    }

    func category(_ source: ScriptSource, tid: String, page: Int) async throws -> [MediaItem] {
        let json = try await perform(source, timeout: 30) { engine in
            try engine.call(functionNames: ["category", "categoryContent", "getCategory"], arguments: [tid, page, [String: Any]()])
        }
        guard let json else { throw ScriptError.emptyResult("category") }
        return Self.parseItems(json, source: source)
    }

    func search(_ source: ScriptSource, keyword: String, page: Int = 1) async throws -> [MediaItem] {
        let json = try await perform(source, timeout: 30) { engine in
            try engine.call(functionNames: ["search", "searchContent", "getSearch"], arguments: [keyword, page, true])
        }
        guard let json else { throw ScriptError.emptyResult("search") }
        return Self.parseItems(json, source: source)
    }

    func detail(_ source: ScriptSource, id: String) async throws -> MediaDetail {
        let json = try await perform(source, timeout: 30) { engine in
            try engine.call(functionNames: ["detail", "detailContent", "getDetail"], arguments: [id])
        }
        guard let json else { throw ScriptError.emptyResult("detail") }
        return Self.parseDetail(json, source: source)
    }

    func play(_ source: ScriptSource, flag: String, id: String) async throws -> PlayInfo {
        let json = try await perform(source, timeout: 30) { engine in
            try engine.call(functionNames: ["play", "playerContent", "getPlay"], arguments: [flag, id])
        }
        guard let json, let info = Self.parsePlay(json) else { throw ScriptError.emptyResult("play") }
        return info
    }

    func danmaku(_ source: ScriptSource, id: String, name: String) async throws -> [DanmakuComment] {
        let json = try await perform(source, timeout: 20) { engine in
            try engine.call(functionNames: ["danmaku", "danmu", "getDanmaku"], arguments: [id, name])
        }
        guard let json else { return [] }
        return Self.parseDanmaku(json)
    }

    // MARK: - 结果解析（兼容自定义结构与 TVBox 风格字段）

    static func mediaItem(_ dict: JSONDict, source: ScriptSource) -> MediaItem {
        MediaItem(id: dict.strAny(["id", "vod_id", "vid", "link", "url"]) ?? UUID().uuidString,
                  tid: dict.strAny(["tid", "type_id", "category_id"]),
                  title: dict.strAny(["title", "name", "vod_name", "text"]) ?? "未命名",
                  poster: dict.strAny(["poster", "pic", "cover", "vod_pic", "img"]),
                  remark: dict.strAny(["remark", "note", "vod_remarks", "subTitle", "msg"]),
                  year: dict.strAny(["year", "vod_year"]),
                  type: dict.strAny(["type", "typeName", "category"]),
                  sourceKey: source.id)
    }

    static func parseItems(_ json: String, source: ScriptSource) -> [MediaItem] {
        guard let object = JSONValue.object(json) else { return [] }
        if let dict = object as? JSONDict {
            for key in ["items", "list", "data"] {
                if let list = dict[key] as? [Any] {
                    return JSONValue.dicts(list).map { mediaItem($0, source: source) }
                }
            }
            return []
        }
        if let array = object as? [Any] {
            return JSONValue.dicts(array).map { mediaItem($0, source: source) }
        }
        return []
    }

    static func parseSections(_ json: String, source: ScriptSource) -> [HomeSection] {
        guard let object = JSONValue.object(json) else { return [] }
        if let dict = object as? JSONDict, let sections = dict["sections"] as? [Any] {
            return JSONValue.dicts(sections).map { section in
                HomeSection(title: section.strAny(["title", "name"]) ?? "推荐",
                            items: JSONValue.dicts(section["items"]).map { mediaItem($0, source: source) })
            }.filter { !$0.items.isEmpty }
        }
        let items = parseItems(json, source: source)
        return items.isEmpty ? [] : [HomeSection(title: "推荐", items: items)]
    }

    static func parseDetail(_ json: String, source: ScriptSource) -> MediaDetail {
        guard let dict = JSONValue.object(json) as? JSONDict else {
            return MediaDetail(title: "详情", poster: nil, desc: nil, year: nil, lines: [])
        }

        var lines: [PlayLine] = []

        if let rawLines = dict["lines"] as? [Any] {
            lines = JSONValue.dicts(rawLines).map { line in
                let name = line.strAny(["name", "title", "flag"]) ?? "线路"
                return PlayLine(name: name,
                                episodes: JSONValue.dicts(line["episodes"]).map { episode($0, fallbackFlag: name) })
            }
        } else if let from = dict["playFrom"] as? [Any], let playList = dict["playList"] as? [Any] {
            let names = from.compactMap { JSONValue.string($0) }
            for (index, raw) in playList.enumerated() {
                let name = index < names.count ? names[index] : "线路\(index + 1)"
                let list = JSONValue.dicts(raw).map { episode($0, fallbackFlag: name) }
                guard !list.isEmpty else { continue }
                lines.append(PlayLine(name: name, episodes: list))
            }
        }

        return MediaDetail(title: dict.strAny(["title", "name", "vod_name"]) ?? "详情",
                           poster: dict.strAny(["poster", "pic", "cover", "vod_pic"]),
                           desc: dict.strAny(["desc", "content", "vod_content", "intro"]),
                           year: dict.strAny(["year", "vod_year"]),
                           lines: lines.filter { !$0.episodes.isEmpty })
    }

    static func episode(_ dict: JSONDict, fallbackFlag: String) -> Episode {
        Episode(name: dict.strAny(["name", "title", "episode"]) ?? "播放",
                id: dict.strAny(["id", "link", "url", "playId"]) ?? "",
                flag: dict.strAny(["flag", "line", "from"]) ?? fallbackFlag)
    }

    static func parsePlay(_ json: String) -> PlayInfo? {
        guard let dict = JSONValue.object(json) as? JSONDict,
              let url = dict.strAny(["url", "playUrl", "link", "src"]) else { return nil }

        var headers: [String: String] = [:]
        if let raw = dict["headers"] as? [String: Any] {
            for (key, value) in raw {
                if let text = JSONValue.string(value) { headers[key] = text }
            }
        }

        return PlayInfo(url: url,
                        type: dict.strAny(["type", "format"]),
                        headers: headers,
                        danmakuId: dict.strAny(["danmakuId", "danmuId", "danmaku"]),
                        danmakuName: dict.strAny(["danmakuName", "danmuName"]))
    }

    static func parseDanmaku(_ json: String) -> [DanmakuComment] {
        guard let object = JSONValue.object(json) else { return [] }

        let list: [JSONDict]
        if let array = object as? [Any] {
            list = JSONValue.dicts(array)
        } else if let dict = object as? JSONDict {
            let comments = dict.list("comments")
            list = comments.isEmpty ? dict.list("items") : comments
        } else {
            list = []
        }

        return list.compactMap { dict in
            guard let text = dict.strAny(["text", "content", "title"]) else { return nil }
            return DanmakuComment(text: text,
                                  time: dict.val("time") ?? 0,
                                  mode: DanmakuMode.parse(dict.str("mode")),
                                  colorHex: dict.strAny(["color", "colour"]) ?? "#FFFFFF")
        }
    }
}

/// 保证回调只生效一次（脚本返回 / 超时 二选一）
final class OnceFlag {
    private let lock = NSLock()
    private var used = false

    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
