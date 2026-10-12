import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: SourceStore

    @State private var currentKey: String?
    @State private var sections: [HomeSection] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var source: ScriptSource? {
        if let currentKey, let found = store.source(for: currentKey), found.enabled {
            return found
        }
        return store.enabledSources.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.enabledSources.isEmpty {
                    emptyView
                } else if isLoading && sections.isEmpty {
                    ProgressView("加载中…")
                } else if let errorText, sections.isEmpty {
                    errorView(errorText)
                } else {
                    content
                }
            }
            .navigationTitle("首页")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sourceMenu }
            }
            .refreshable { await load() }
            .task(id: source?.id) { await load() }
            .navigationDestination(for: MediaItem.self) { item in
                DetailView(item: item)
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let source {
                    Text(source.name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(section.items, id: \.uniqueKey) { item in
                                    NavigationLink(value: item) {
                                        PosterCard(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(store.enabledSources) { item in
                Button {
                    currentKey = item.id
                    sections = []
                } label: {
                    Text(item.id == source?.id ? "\(item.name) ✓" : item.name)
                }
            }
        } label: {
            Label("切换源", systemImage: "rectangle.stack")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有可用的源").font(.headline)
            Text("到「设置 → 源管理」导入 JS 源脚本，或使用内置演示源。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func errorView(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(text).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Button("重试") { Task { await load() } }
                .buttonStyle(.bordered)
        }
    }

    private func load() async {
        guard let source, !isLoading else { return }
        isLoading = true
        errorText = nil
        do {
            let result = try await ScriptService.shared.home(source)
            sections = result
            if result.isEmpty { errorText = "该源首页没有返回内容" }
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

/// 海报卡片，首页/搜索共用
struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 108

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: item.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    placeholder.overlay(ProgressView().scaleEffect(0.6))
                }
            }
            .frame(width: width, height: width * 1.42)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                if let remark = item.remark, !remark.isEmpty {
                    Text(remark)
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
            }

            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)

            Text(item.year ?? item.type ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .frame(width: width)
    }

    private var placeholder: some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay(Image(systemName: "film").foregroundStyle(.tertiary))
    }
}
