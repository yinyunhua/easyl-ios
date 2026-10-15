import Foundation

/// 线程安全的可信域名快照。
///
/// `MainActivity.trustedHosts` 在 Android 里由主线程读写；iOS 侧导航回调（`decidePolicyFor`）
/// 需要**同步**判断域名是否可信，因此维护一份带锁的镜像，避免跨 actor 往返。
/// 数据源与 `ShellModel.trustedHosts` 保持同步。
final class HostTrustStore: @unchecked Sendable {

    static let shared = HostTrustStore()

    private let lock = NSLock()
    private var hosts: Set<String> = []

    private init() {}

    func replace(with list: [String]) {
        lock.lock()
        hosts = Set(list.map { $0.lowercased() })
        lock.unlock()
    }

    func add(_ host: String) {
        let value = host.lowercased()
        guard !value.isEmpty else { return }
        lock.lock()
        hosts.insert(value)
        lock.unlock()
    }

    func isTrusted(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return hosts.contains(host.lowercased())
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(hosts).sorted()
    }

    func clear() {
        lock.lock()
        hosts.removeAll()
        lock.unlock()
    }
}
