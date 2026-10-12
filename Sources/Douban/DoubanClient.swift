import Foundation

struct DoubanItem: Identifiable, Hashable {
    var id: String
    var title: String
    var year: String?
    var rating: String?
    var cover: String?
    var subtitle: String?

    var coverURL: URL? { cover.flatMap { URL(string: $0) } }
}

/// 豆瓣 rexxar 接口（沿用原版使用的 m.douban.com 接口，需带 Referer）
enum DoubanClient {
    static let referer = "https://m.douban.com/"

    static func search(_ keyword: String, start: Int = 0, count: Int = 20) async throws -> [DoubanItem] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let url = "https://m.douban.com/rexxar/api/v2/search?q=\(encoded)&type=movie&start=\(start)&count=\(count)"
        let text = try await HTTP.text(url, headers: ["Referer": referer, "Accept": "application/json"])

        guard let object = JSONValue.object(text) as? JSONDict else { return [] }
        return object.list("items").compactMap { entry in
            let target = entry.dict("target") ?? entry
            let id = target.strAny(["id", "douban_id"]) ?? ""
            let title = target.strAny(["title", "name"]) ?? ""
            guard !title.isEmpty else { return nil }
            return DoubanItem(id: id,
                              title: title,
                              year: target.strAny(["year"]),
                              rating: target.dict("rating")?.strAny(["value"]) ?? target.strAny(["rating"]),
                              cover: coverURL(from: target),
                              subtitle: target.strAny(["card_subtitle", "subtitle"]))
        }
    }

    static func detail(id: String) async throws -> DoubanItem? {
        let url = "https://m.douban.com/rexxar/api/v2/movie/\(id)"
        let text = try await HTTP.text(url, headers: ["Referer": referer, "Accept": "application/json"])
        guard let dict = JSONValue.object(text) as? JSONDict else { return nil }
        return DoubanItem(id: dict.strAny(["id"]) ?? id,
                          title: dict.strAny(["title", "name"]) ?? "",
                          year: dict.strAny(["year"]),
                          rating: dict.dict("rating")?.strAny(["value"]),
                          cover: coverURL(from: dict),
                          subtitle: dict.strAny(["card_subtitle", "intro"]))
    }

    private static func coverURL(from dict: JSONDict) -> String? {
        if let cover = dict.dict("cover"), let url = cover.strAny(["url"]) { return url }
        if let pic = dict.dict("pic"), let url = pic.strAny(["large", "normal"]) ?? pic.dict("large")?.strAny(["url"]) { return url }
        return dict.strAny(["cover_url", "pic_url", "cover"])
    }
}
