import Foundation
import Combine

struct DownloadItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var url: String
    var name: String
    var progress: Double = 0
    var finished: Bool = false
    var failed: Bool = false
    var filePath: String?
    var createdAt: Date = Date()

    var fileURL: URL? { filePath.map { URL(fileURLWithPath: $0) } }
}

/// 后台下载：URLSession 后台会话 + 断点数据持久化（替代原版迅雷/自研 DownloadService）
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []

    private var session: URLSession!
    private var taskMap: [Int: UUID] = [:]
    private var storeURL: URL { AppPaths.documents.appendingPathComponent("downloads.json") }

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.example.easyl.downloads")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        load()
        restore()
    }

    // MARK: - 列表操作

    func add(url urlString: String, name: String = "") {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }

        let fileName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (url.lastPathComponent.isEmpty ? "下载文件" : url.lastPathComponent)
            : name

        let item = DownloadItem(url: trimmed, name: fileName)
        items.insert(item, at: 0)
        save()

        let task = session.downloadTask(with: url)
        taskMap[task.taskIdentifier] = item.id
        task.resume()
    }

    func cancel(_ item: DownloadItem) {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            for task in tasks where self.taskMap[task.taskIdentifier] == item.id {
                task.cancel()
            }
        }
        update(item.id) { $0.failed = true }
    }

    func remove(_ item: DownloadItem) {
        cancel(item)
        if let path = item.filePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == item.id }
            self.save()
        }
    }

    func removeAll() {
        for item in items { remove(item) }
    }

    func update(_ id: UUID, _ change: @escaping (inout DownloadItem) -> Void) {
        DispatchQueue.main.async {
            guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            change(&self.items[index])
            self.save()
            self.objectWillChange.send()
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let list = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        items = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    /// App 重启后把后台会话里仍在跑的任务重新挂回列表
    private func restore() {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let downloads = tasks.compactMap { $0 as? URLSessionDownloadTask }
            DispatchQueue.main.async {
                for task in downloads {
                    guard let url = task.originalRequest?.url?.absoluteString else { continue }
                    if let item = self.items.first(where: { $0.url == url && !$0.finished }) {
                        self.taskMap[task.taskIdentifier] = item.id
                    }
                }
            }
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = taskMap[downloadTask.taskIdentifier], totalBytesExpectedToWrite > 0 else { return }
        update(id) { $0.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = taskMap[downloadTask.taskIdentifier],
              let item = items.first(where: { $0.id == id }) else { return }

        let ext = URL(string: item.url)?.pathExtension ?? "mp4"
        let base = AppPaths.safeName(item.name)
        let destination = AppPaths.downloads.appendingPathComponent(base.contains(".") ? base : "\(base).\(ext)")

        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            update(id) { $0.finished = true; $0.progress = 1; $0.failed = false; $0.filePath = destination.path }
        } catch {
            update(id) { $0.failed = true }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = taskMap[task.taskIdentifier] else { return }
        NSLog("[EasylDownload] failed: %@", error.localizedDescription)
        update(id) { $0.failed = true }
    }
}
