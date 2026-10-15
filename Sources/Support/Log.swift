import Foundation
import os

/// 对应 Android 端 `Log.d/e/w(TAG, ...)`，统一落到 os.Logger + 内存环形缓冲，供设置页诊断查看。
enum HGLog {

    enum Level: String {
        case debug = "D"
        case info = "I"
        case warn = "W"
        case error = "E"
    }

    struct Line: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let tag: String
        let message: String

        var display: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return "\(f.string(from: date)) \(level.rawValue)/\(tag): \(message)"
        }
    }

    private static let logger = Logger(subsystem: "com.hg.app", category: "hg")
    private static let queue = DispatchQueue(label: "com.hg.app.log")
    private static let capacity = 400
    private static let store = Store()

    static var onChange: (() -> Void)?

    /// 带锁缓冲，避免把可变 static 状态直接暴露给并发队列。
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [Line] = []

        func append(_ line: Line) {
            lock.lock()
            lines.append(line)
            if lines.count > HGLog.capacity { lines.removeFirst(lines.count - HGLog.capacity) }
            lock.unlock()
        }

        func snapshot() -> [Line] {
            lock.lock()
            defer { lock.unlock() }
            return lines
        }

        func removeAll() {
            lock.lock()
            lines.removeAll()
            lock.unlock()
        }
    }

    static func log(_ level: Level, _ tag: String, _ message: String) {
        logger.log(level: level == .error ? .error : .default, "[\(tag, privacy: .public)] \(message, privacy: .public)")
        let line = Line(date: Date(), level: level, tag: tag, message: message)
        queue.async {
            store.append(line)
            DispatchQueue.main.async { onChange?() }
        }
    }

    static func d(_ tag: String, _ message: String) { log(.debug, tag, message) }
    static func i(_ tag: String, _ message: String) { log(.info, tag, message) }
    static func w(_ tag: String, _ message: String) { log(.warn, tag, message) }
    static func e(_ tag: String, _ message: String) { log(.error, tag, message) }

    static func snapshot() -> [Line] { store.snapshot() }

    static func clear() {
        queue.async {
            store.removeAll()
            DispatchQueue.main.async { onChange?() }
        }
    }
}
