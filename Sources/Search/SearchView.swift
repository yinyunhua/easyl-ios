import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: SourceStore

    @State private var keyword = ""
    @State private var mode = 0
    @State private var results: [MediaItem] = []
    @State private var douban: [DoubanItem] = []
    @State private var isSearching = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $mode) {
                    Text("源搜索").tag(0)
                    Text("豆瓣").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("搜索中…").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.secondary)
                }

                if mode == 0 {
                    ForEach(results, id: \.uniqueKey) { item in
                        NavigationLink(value: item) {
                            MediaRow(item: item)
                        }
                    }
                } else {
                    ForEach(douban) { item in
                        Button {
                            keyword = item.title
                            mode = 0
                            results = []
                            Task { await search() }
                        } label: {
                            DoubanRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("搜索")
            .searchable(text: $keyword, prompt: mode == 0 ? "搜索资源（多源聚合）" : "搜索豆瓣条目")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        }
    }

    private func search() async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSearching else { return }

        isSearching = true
        errorText = nil

        if mode == 0 {
            results = []
            var collected: [MediaItem] = []
            for source in store.enabledSources {
                if let items = try? await ScriptService.shared.search(source, keyword: text) {
                    collected.append(contentsOf: items)
                }
            }
            results = collected
            if collected.isEmpty { errorText = "没有结果：检查源是否可用，或换个关键词" }
        } else {
            do {
                douban = try await DoubanClient.search(text)
                if douban.isEmpty { errorText = "豆瓣没有结果（接口可能需要 Referer 或网络受限）" }
            } catch {
                errorText = "豆瓣搜索失败：\(error.localizedDescription)"
            }
        }

        isSearching = false
    }
}

struct MediaRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.posterURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(uiColor: .secondarySystemBackground)
                }
            }
            .frame(width: 62, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.subheadline).lineLimit(2)
                Text([item.year, item.remark].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("源：\(item.sourceKey)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DoubanRow: View {
    let item: DoubanItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.coverURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(uiColor: .secondarySystemBackground)
                }
            }
            .frame(width: 62, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.subheadline).lineLimit(2)
                if let rating = item.rating {
                    Label(rating, systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
