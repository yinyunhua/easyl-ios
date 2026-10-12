import Foundation

/// 轻量日志总线：脚本 console.log、引擎异常、源导入结果都汇总到这里，App 内「设置 → 自检」可查看
final class LogBus: ObservableObject {
    static let shared = LogBus()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let source: String
        let text: String
    }

    @Published private(set) var entries: [Entry] = []

    private let limit = 300

    func log(_ text: String, source: String = "app") {
        NSLog("[Easyl:%@] %@", source, text)
        DispatchQueue.main.async {
            self.entries.append(Entry(date: Date(), source: source, text: text))
            if self.entries.count > self.limit {
                self.entries.removeFirst(self.entries.count - self.limit)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }

    var dump: String {
        entries.map { "[\(Self.formatter.string(from: $0.date))][\($0.source)] \($0.text)" }
            .joined(separator: "\n")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
