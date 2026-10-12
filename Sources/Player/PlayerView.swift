import SwiftUI
import AVKit

struct PlayerView: View {
    let urlString: String
    var headers: [String: String] = [:]
    var title: String = ""
    var source: ScriptSource?
    var danmakuId: String?
    var danmakuName: String?
    var episodes: [Episode] = []
    var currentIndex: Int?
    var onSelectEpisode: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerModel()

    @State private var danmakuOn = AppSettings.defaultDanmakuOn
    @State private var subtitles: [SubtitleCue] = []
    @State private var showSubtitleInput = false
    @State private var subtitleURL = ""
    @State private var showEpisodes = false
    @State private var tip: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoContainer(player: model.player)
                .ignoresSafeArea()

            SubtitleOverlay(cues: subtitles, currentTime: model.currentTime)
                .allowsHitTesting(false)

            if danmakuOn {
                DanmakuOverlay(comments: model.comments,
                               currentTime: model.currentTime,
                               isPlaying: model.isPlaying,
                               fontSize: CGFloat(AppSettings.danmakuFontSize),
                               opacity: AppSettings.danmakuOpacity,
                               scrollDuration: AppSettings.danmakuSpeed)
                    .padding(.top, 56)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let tip {
                    Text(tip)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 90)
                }
                if let error = model.errorText {
                    Text(error)
                        .font(.footnote)
                        .padding(10)
                        .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .padding(.bottom, 90)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { start() }
        .onDisappear { model.pause() }
        .alert("加载外挂字幕", isPresented: $showSubtitleInput) {
            TextField("https://example.com/demo.srt 或 .vtt", text: $subtitleURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("加载") { loadSubtitle() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showEpisodes) { episodeSheet }
    }

    // MARK: - 界面

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
            }

            Text(title.isEmpty ? model.title : title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 4)

            if model.isLoadingDanmaku {
                ProgressView().tint(.white).scaleEffect(0.8)
            }

            Button { danmakuOn.toggle() } label: {
                Image(systemName: danmakuOn ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
            }

            speedMenu
            subtitleMenu

            if !episodes.isEmpty {
                Button { showEpisodes = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { value in
                Button(String(format: "%.2fx", value) + (abs(model.speed - value) < 0.01 ? " ✓" : "")) {
                    model.apply(speed: value)
                }
            }
        } label: {
            Text(String(format: "%.2fx", model.speed)).font(.footnote.weight(.semibold))
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button("从链接加载字幕…") { showSubtitleInput = true }
            if !subtitles.isEmpty {
                Button("关闭字幕", role: .destructive) { subtitles = [] }
            }
        } label: {
            Image(systemName: "captions.bubble").font(.system(size: 15, weight: .semibold))
        }
    }

    private var episodeSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(episodes.enumerated()), id: \.offset) { index, episode in
                    Button {
                        showEpisodes = false
                        onSelectEpisode?(index)
                    } label: {
                        HStack {
                            Text(episode.name)
                            Spacer()
                            if index == currentIndex {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showEpisodes = false }
                }
            }
        }
    }

    // MARK: - 逻辑

    private func start() {
        model.onFinished = { [episodes, currentIndex, onSelectEpisode] in
            guard AppSettings.autoPlayNext, let currentIndex, currentIndex + 1 < episodes.count else { return }
            onSelectEpisode?(currentIndex + 1)
        }
        model.speed = AppSettings.defaultSpeed
        model.load(urlString: urlString, headers: headers, title: title)
        model.loadDanmaku(source: source, danmakuId: danmakuId, name: danmakuName ?? title)
    }

    private func loadSubtitle() {
        let target = subtitleURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        Task {
            do {
                let cues = try await SubtitleLoader.load(urlString: target)
                await MainActor.run {
                    subtitles = cues
                    tip = cues.isEmpty ? "字幕为空或格式不支持" : "字幕已加载：\(cues.count) 条"
                }
            } catch {
                await MainActor.run { tip = "字幕加载失败：\(error.localizedDescription)" }
            }
        }
    }
}

/// AVPlayerViewController 封装：原生控件自带画中画 / AirPlay / 手势
struct VideoContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

/// 外挂字幕渲染（SRT / VTT 解析后按播放时间轴叠加）
struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    let currentTime: Double

    var body: some View {
        VStack {
            Spacer()
            if let cue = activeCue {
                Text(cue.text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 70)
            }
        }
    }

    private var activeCue: SubtitleCue? {
        cues.first { currentTime >= $0.start && currentTime <= $0.end }
    }
}
