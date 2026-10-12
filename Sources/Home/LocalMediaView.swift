import SwiftUI
import UniformTypeIdentifiers

/// 本地视频：从「文件」导入，或扫描沙盒里的视频文件，点击即播
struct LocalMediaView: View {
    struct Target: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
    }

    @State private var files: [URL] = []
    @State private var playing: Target?
    @State private var importing = false
    @State private var message: String?

    private static let mediaExtensions: Set<String> = [
        "mp4", "mov", "mkv", "avi", "ts", "m4v", "flv", "webm", "rmvb", "wmv",
        "mp3", "m4a", "aac", "flac", "wav"
    ]

    var body: some View {
        List {
            Section {
                Button {
                    importing = true
                } label: {
                    Label("从「文件」App 导入视频", systemImage: "folder.badge.plus")
                }
                Text("也可以直接把视频拖进「文件」App → 我的 iPhone → EasylForIOS → Downloads，然后回来下拉刷新。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("本地文件（\(files.count)）") {
                if files.isEmpty {
                    Text("暂无本地视频")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(files, id: \.path) { url in
                    Button {
                        playing = Target(url: url, title: url.lastPathComponent)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "film").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent).font(.subheadline).lineLimit(1)
                                Text(Self.sizeText(url)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet where files.indices.contains(index) {
                        try? FileManager.default.removeItem(at: files[index])
                    }
                    reload()
                }
            }

            if let message {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("本地视频")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .onAppear { reload() }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.movie, .video, .audio, .data],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .fullScreenCover(item: $playing) { target in
            PlayerView(urlString: target.url.absoluteString, title: target.title, source: nil, danmakuId: nil)
        }
    }

    private func reload() {
        let manager = FileManager.default
        let roots = [AppPaths.documents, AppPaths.downloads, AppPaths.documents.appendingPathComponent("Local", isDirectory: true)]
        var seen = Set<String>()
        var found: [URL] = []

        for root in roots {
            guard let enumerator = manager.enumerator(at: root,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                guard !url.hasDirectoryPath else { continue }
                guard Self.mediaExtensions.contains(url.pathExtension.lowercased()) else { continue }
                guard seen.insert(url.path).inserted else { continue }
                found.append(url)
            }
        }

        files = found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let target = AppPaths.ensure(AppPaths.documents.appendingPathComponent("Local", isDirectory: true))
            var imported = 0
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let destination = target.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: destination)
                if (try? FileManager.default.copyItem(at: url, to: destination)) != nil {
                    imported += 1
                }
            }
            message = "已导入 \(imported) 个文件"
            LogBus.shared.log("本地导入 \(imported) 个文件", source: "local")
            reload()
        case .failure(let error):
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    private static func sizeText(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return "" }
        return Format.bytes(size.int64Value)
    }
}
