import Foundation

struct LiveChannel: Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var group: String
    var logo: String?
}

/// 标准 EXTM3U 播放列表解析（对应原版的 M3U 直播源）
enum M3UParser {
    static func parse(_ text: String, fallbackGroup: String = "未分组") -> [LiveChannel] {
        var channels: [LiveChannel] = []
        var pending: (name: String, group: String, logo: String?)?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("#EXTINF") {
                let name = line.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? "未命名"
                let attrs = attributes(line)
                pending = (name.isEmpty ? "未命名" : name,
                           attrs["group-title"] ?? fallbackGroup,
                           attrs["tvg-logo"])
            } else if line.hasPrefix("#") {
                continue
            } else if let channel = pending {
                channels.append(LiveChannel(id: "\(channel.name)|\(line)",
                                            name: channel.name,
                                            url: line,
                                            group: channel.group,
                                            logo: channel.logo))
                pending = nil
            }
        }

        // 没有 #EXTINF 的纯链接列表也支持
        if channels.isEmpty {
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#"), line.contains("://") else { continue }
                channels.append(LiveChannel(id: line, name: line, url: line, group: fallbackGroup, logo: nil))
            }
        }

        return channels
    }

    private static func attributes(_ line: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z0-9-]+)=\"([^\"]*)\"") else { return result }
        let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
        for match in matches where match.numberOfRanges > 2 {
            if let keyRange = Range(match.range(at: 1), in: line),
               let valueRange = Range(match.range(at: 2), in: line) {
                result[String(line[keyRange])] = String(line[valueRange])
            }
        }
        return result
    }
}

struct EPGProgramme: Identifiable, Hashable {
    var id: String { "\(start)|\(title)" }
    var start: String
    var end: String
    var title: String
}

/// 节目单：兼容 jdbus 的 JSON 接口与 XMLTV
enum EPGClient {
    static func programmes(channel: String) async throws -> [EPGProgramme] {
        let encoded = channel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channel
        let url = "https://www.jdbus.net/epg/?ch=\(encoded)"
        let text = try await HTTP.text(url)
        return parse(text)
    }

    static func parse(_ text: String) -> [EPGProgramme] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            return parseJSON(text)
        }
        return parseXMLTV(text)
    }

    private static func parseJSON(_ text: String) -> [EPGProgramme] {
        guard let array = JSONValue.object(text) as? [Any] else { return [] }
        return JSONValue.dicts(array).compactMap { dict in
            guard let title = dict.strAny(["title", "name", "program"]) else { return nil }
            return EPGProgramme(start: dict.strAny(["start", "start_time", "begin"]) ?? "",
                                end: dict.strAny(["end", "end_time", "stop"]) ?? "",
                                title: title)
        }
    }

    private static func parseXMLTV(_ text: String) -> [EPGProgramme] {
        var result: [EPGProgramme] = []
        let pattern = "<programme[^>]*start=\"([^\"]+)\"[^>]*stop=\"([^\"]+)\"[^>]*>(.*?)</programme>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches where match.numberOfRanges > 3 {
            guard let startRange = Range(match.range(at: 1), in: text),
                  let stopRange = Range(match.range(at: 2), in: text),
                  let bodyRange = Range(match.range(at: 3), in: text) else { continue }

            let body = String(text[bodyRange])
            var title = body
            if let titleRegex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.dotMatchesLineSeparators]),
               let titleMatch = titleRegex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               titleMatch.numberOfRanges > 1,
               let range = Range(titleMatch.range(at: 1), in: body) {
                title = String(body[range])
            }

            result.append(EPGProgramme(start: String(text[startRange]),
                                       end: String(text[stopRange]),
                                       title: title.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return result
    }
}
