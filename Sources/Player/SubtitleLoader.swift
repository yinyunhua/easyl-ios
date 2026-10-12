import Foundation

struct SubtitleCue: Identifiable, Hashable {
    let id = UUID()
    var start: Double
    var end: Double
    var text: String
}

enum SubtitleLoader {
    static func load(urlString: String) async throws -> [SubtitleCue] {
        let text = try await HTTP.text(urlString)
        return parse(text)
    }

    static func load(fileURL: URL) throws -> [SubtitleCue] {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return parse(text)
    }

    /// 同时支持 SRT 与 WebVTT
    static func parse(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[timeLineIndex]

            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { continue }

            let contentLines = lines[(timeLineIndex + 1)...]
                .filter { !$0.lowercased().hasPrefix("note") }
            let content = contentLines.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: content))
        }

        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTimestamp(_ value: String) -> Double? {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spaceIndex = raw.firstIndex(of: " ") {
            raw = String(raw[..<spaceIndex])   // 去掉 VTT 的行内设置
        }
        raw = raw.replacingOccurrences(of: ",", with: ".")

        let parts = raw.components(separatedBy: ":")
        guard parts.count == 3 || parts.count == 2 else { return nil }

        let seconds: Double
        if parts.count == 3 {
            guard let hours = Double(parts[0]), let minutes = Double(parts[1]), let secs = Double(parts[2]) else { return nil }
            seconds = hours * 3600 + minutes * 60 + secs
        } else {
            guard let minutes = Double(parts[0]), let secs = Double(parts[1]) else { return nil }
            seconds = minutes * 60 + secs
        }
        return seconds
    }
}
