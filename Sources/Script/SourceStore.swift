import Foundation
import Combine

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var scripts: [ScriptSource] = []
    @Published var isImporting = false
    @Published var message: String?

    private var storeURL: URL { AppPaths.scripts.appendingPathComponent("sources.json") }

    init() {
        load()
        installDemoIfNeeded()
    }

    var enabledSources: [ScriptSource] { scripts.filter { $0.enabled } }

    func source(for key: String) -> ScriptSource? {
        scripts.first { $0.id == key }
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let list = try? JSONDecoder().decode([ScriptSource].self, from: data) else { return }
        scripts = list
    }

    func save() {
        guard let data = try? JSONEncoder().encode(scripts) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func upsert(_ source: ScriptSource) {
        if let index = scripts.firstIndex(where: { $0.id == source.id }) {
            scripts[index] = source
        } else {
            scripts.append(source)
        }
        ScriptService.shared.dropCache(for: source.id)
        save()
    }

    func remove(_ source: ScriptSource) {
        scripts.removeAll { $0.id == source.id }
        ScriptService.shared.dropCache(for: source.id)
        save()
    }

    func toggle(_ source: ScriptSource) {
        guard let index = scripts.firstIndex(where: { $0.id == source.id }) else { return }
        scripts[index].enabled.toggle()
        save()
    }

    /// 支持：远程 URL / 本地文件路径 / 直接粘贴脚本正文
    func importScript(from location: String) async -> ScriptSource? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "内容为空"
            return nil
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let code: String
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                code = try await HTTP.text(trimmed)
            } else if let url = URL(string: trimmed), url.isFileURL,
                      let text = try? String(contentsOf: url, encoding: .utf8) {
                code = text
            } else {
                code = trimmed
            }

            guard code.count > 10 else {
                message = "脚本内容过短，导入失败"
                return nil
            }

            let id = String(Crypto.md5(trimmed.prefix(80).description).prefix(12))
            let source = ScriptSource(id: id,
                                      name: Self.scriptName(code: code, location: trimmed),
                                      location: trimmed.hasPrefix("http") ? trimmed : "local",
                                      code: code)
            upsert(source)
            message = "已导入：\(source.name)"
            return source
        } catch {
            message = "导入失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 从脚本里找 appName / name 之类的元信息做显示名
    static func scriptName(code: String, location: String) -> String {
        for key in ["appName", "name", "title", "sourceName"] {
            let pattern = "\(key)\\s*[:=]\\s*[\"']([^\"']{2,30})[\"']"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: code) {
                return String(code[range])
            }
        }
        if let host = URL(string: location)?.host { return host }
        return "本地脚本"
    }

    private func installDemoIfNeeded() {
        guard scripts.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "js"),
              let code = try? String(contentsOf: url, encoding: .utf8) else { return }
        scripts = [ScriptSource(id: "demo", name: "演示源（内置）", location: "local", code: code)]
        save()
    }
}
