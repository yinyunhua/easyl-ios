import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager

    @State private var showAdd = false
    @State private var inputURL = ""
    @State private var inputName = ""
    @State private var playing: DownloadItem?

    var body: some View {
        NavigationStack {
            List {
                if downloads.items.isEmpty {
                    Text("暂无下载。\n支持直链 MP4 / TS 文件；HLS（m3u8）请在播放页在线观看，iOS 无法离线合并分片。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(downloads.items) { item in
                    Button {
                        if item.finished { playing = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).font(.subheadline).lineLimit(1)
                            ProgressView(value: item.progress)
                            HStack(spacing: 8) {
                                Text(item.finished ? "已完成" : (item.failed ? "已取消 / 失败" : Format.percent(item.progress)))
                                Spacer()
                                if let path = item.filePath, let size = Self.fileSize(path) {
                                    Text(size)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            downloads.remove(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { LocalMediaView() } label: { Image(systemName: "folder") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("新建下载", isPresented: $showAdd) {
                TextField("https://example.com/movie.mp4", text: $inputURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("文件名（可选）", text: $inputName)
                Button("开始下载") {
                    downloads.add(url: inputURL, name: inputName)
                    inputURL = ""
                    inputName = ""
                }
                Button("取消", role: .cancel) {}
            }
            .fullScreenCover(item: $playing) { item in
                if let url = item.fileURL {
                    PlayerView(urlString: url.absoluteString, title: item.name, source: nil, danmakuId: nil)
                }
            }
        }
    }

    private static func fileSize(_ path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return Format.bytes(size.int64Value)
    }
}
