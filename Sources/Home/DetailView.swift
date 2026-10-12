import SwiftUI

struct DetailView: View {
    let item: MediaItem

    @EnvironmentObject private var store: SourceStore

    @State private var detail: MediaDetail?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var lineIndex = 0
    @State private var playLoading = false
    @State private var payload: PlayerPayload?

    struct PlayerPayload: Identifiable {
        let id = UUID()
        let info: PlayInfo
        let episodeIndex: Int
    }

    private var source: ScriptSource? { store.source(for: item.sourceKey) }
    private var lines: [PlayLine] { detail?.lines ?? [] }
    private var episodes: [Episode] {
        guard lines.indices.contains(lineIndex) else { return [] }
        return lines[lineIndex].episodes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    if lines.count > 1 { linePicker }

                    if episodes.isEmpty {
                        Text("该条目没有可播放资源")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        episodeGrid
                    }

                    if let desc = detail?.desc, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("简介").font(.headline)
                            Text(desc).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .overlay {
            if playLoading {
                ProgressView("正在解析播放地址…")
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .fullScreenCover(item: $payload) { current in
            PlayerView(urlString: current.info.url,
                       headers: current.info.headers,
                       title: "\(item.title) \(episodes[safe: current.episodeIndex]?.name ?? "")",
                       source: source,
                       danmakuId: current.info.danmakuId,
                       danmakuName: current.info.danmakuName ?? item.title,
                       episodes: episodes,
                       currentIndex: current.episodeIndex,
                       onSelectEpisode: { index in
                           guard episodes.indices.contains(index) else { return }
                           Task { await play(episode: episodes[index], index: index) }
                       })
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: item.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(uiColor: .secondarySystemBackground)
                        .overlay(Image(systemName: "film").foregroundStyle(.tertiary))
                }
            }
            .frame(width: 96, height: 136)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.headline)
                Text([item.year, item.type, item.remark].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("来源：\(source?.name ?? item.sourceKey)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if !episodes.isEmpty {
                    Button {
                        Task { await play(episode: episodes[0], index: 0) }
                    } label: {
                        Label("立即播放", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var linePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Button {
                        lineIndex = index
                    } label: {
                        Text(line.name)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(index == lineIndex ? Color.accentColor.opacity(0.25) : Color(uiColor: .secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var episodeGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选集").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(Array(episodes.enumerated()), id: \.element.uniqueKey) { index, episode in
                    Button {
                        Task { await play(episode: episode, index: index) }
                    } label: {
                        Text(episode.name)
                            .font(.footnote)
                            .lineLimit(1)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(payload?.episodeIndex == index
                                          ? Color.accentColor.opacity(0.22)
                                          : Color(uiColor: .secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        guard let source else {
            errorText = "找不到来源脚本：\(item.sourceKey)"
            isLoading = false
            return
        }
        isLoading = true
        errorText = nil
        do {
            let result = try await ScriptService.shared.detail(source, id: item.id)
            detail = result
            lineIndex = 0
            if result.lines.isEmpty { errorText = "详情没有解析到播放线路" }
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func play(episode: Episode, index: Int) async {
        guard let source else { return }
        playLoading = true
        defer { playLoading = false }
        do {
            let info = try await ScriptService.shared.play(source, flag: episode.flag, id: episode.id)
            payload = PlayerPayload(info: info, episodeIndex: index)
        } catch {
            errorText = "播放失败：\(error.localizedDescription)"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
