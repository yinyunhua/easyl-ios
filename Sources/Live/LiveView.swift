import SwiftUI

struct LiveView: View {
    @State private var channels: [LiveChannel] = []
    @State private var group: String?
    @State private var keyword = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var playing: LiveChannel?
    @State private var epgChannel: LiveChannel?
    @State private var epg: [EPGProgramme] = []
    @State private var showAdd = false
    @State private var inputURL = ""

    private var groups: [String] {
        Array(Set(channels.map(\.group))).sorted()
    }

    private var filtered: [LiveChannel] {
        channels.filter { channel in
            (group == nil || channel.group == group)
            && (keyword.isEmpty || channel.name.localizedCaseInsensitiveContains(keyword))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack(spacing: 8) { ProgressView(); Text("加载频道…").font(.footnote) }
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.secondary)
                }

                if channels.isEmpty && !isLoading {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("还没有直播源").font(.headline)
                        Text("支持标准 EXTM3U：右上角 + 添加 m3u 地址，或用「设置 → 直播源」管理。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                ForEach(filtered) { channel in
                    Button {
                        playing = channel
                    } label: {
                        HStack(spacing: 10) {
                            RemoteLogo(url: channel.logo)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(channel.name).font(.subheadline).lineLimit(1)
                                Text(channel.group).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("查看节目单") {
                            epgChannel = channel
                            epg = []
                            Task { await loadEPG(channel) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("直播")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("全部频道" + (group == nil ? " ✓" : "")) { group = nil }
                        ForEach(groups, id: \.self) { name in
                            Button(name + (group == name ? " ✓" : "")) { group = name }
                        }
                    } label: {
                        Label(group ?? "分组", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .searchable(text: $keyword, prompt: "搜索频道")
            .task { await reload() }
            .alert("添加 M3U 直播源", isPresented: $showAdd) {
                TextField("https://example.com/live.m3u", text: $inputURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("添加") { addSource() }
                Button("取消", role: .cancel) {}
            }
            .fullScreenCover(item: $playing) { channel in
                PlayerView(urlString: channel.url, title: channel.name, source: nil, danmakuId: nil)
            }
            .sheet(item: $epgChannel) { channel in
                EPGSheet(channel: channel, programmes: epg)
            }
        }
    }

    private func addSource() {
        let text = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var list = AppSettings.liveSources
        if !list.contains(text) { list.append(text) }
        AppSettings.liveSources = list
        inputURL = ""
        Task { await reload() }
    }

    private func reload() async {
        isLoading = true
        errorText = nil
        var collected: [LiveChannel] = []

        // 内置演示源
        if let url = Bundle.main.url(forResource: "demo", withExtension: "m3u"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            collected.append(contentsOf: M3UParser.parse(text, fallbackGroup: "演示"))
        }

        for location in AppSettings.liveSources {
            do {
                let text = try await HTTP.text(location)
                collected.append(contentsOf: M3UParser.parse(text))
            } catch {
                errorText = "部分源加载失败：\(location)（\(error.localizedDescription)）"
            }
        }

        var seen = Set<String>()
        channels = collected.filter { seen.insert($0.id).inserted }
        isLoading = false
    }

    private func loadEPG(_ channel: LiveChannel) async {
        epg = (try? await EPGClient.programmes(channel: channel.name)) ?? []
    }
}

struct EPGSheet: View {
    let channel: LiveChannel
    let programmes: [EPGProgramme]

    var body: some View {
        NavigationStack {
            List {
                if programmes.isEmpty {
                    Text("没有获取到节目单（接口可能不可用）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(programmes) { programme in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(programme.title).font(.subheadline)
                        Text("\(programme.start) — \(programme.end)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

struct RemoteLogo: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .overlay(Image(systemName: "tv").font(.caption).foregroundStyle(.secondary))
            }
        }
        .frame(width: 38, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
