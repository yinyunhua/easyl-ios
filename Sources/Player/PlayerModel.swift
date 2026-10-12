import Foundation
import Combine
import AVFoundation

/// 播放内核：AVPlayer 替代原版 ExoPlayer + MPV 双内核
final class PlayerModel: ObservableObject {
    let player = AVPlayer()

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isBuffering = false
    @Published var speed: Double = AppSettings.defaultSpeed
    @Published var errorText: String?
    @Published var title: String = ""
    @Published var comments: [DanmakuComment] = []
    @Published var isLoadingDanmaku = false

    var onFinished: (() -> Void)?

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init() {
        activateAudioSession()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? session.setActive(true)
    }

    func load(urlString: String, headers: [String: String], title: String) {
        guard let url = URL(string: urlString) else {
            errorText = "无效播放地址"
            return
        }
        self.title = title
        errorText = nil

        // 自定义请求头（Referer/Cookie/UA 等），沿用私有的 AVURLAssetHTTPHeaderFieldsKey
        let options: [String: Any]? = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 10

        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = true
        installObservers(for: item)
        play()
    }

    private func installObservers(for item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .failed:
                    self?.errorText = item.error?.localizedDescription ?? "播放失败"
                    self?.isPlaying = false
                default:
                    break
                }
            }
        }

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item,
                                                             queue: .main) { [weak self] _ in
            self?.onFinished?()
        }

        if timeObserver == nil {
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self else { return }
                if time.seconds.isFinite { self.currentTime = time.seconds }
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite {
                    self.duration = itemDuration
                }
                self.isPlaying = self.player.rate > 0
            }
        }
    }

    func play() {
        player.play()
        player.rate = Float(speed)
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
    }

    func skip(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    func apply(speed value: Double) {
        speed = value
        AppSettings.defaultSpeed = value
        if isPlaying { player.rate = Float(value) }
    }

    func loadDanmaku(source: ScriptSource?, danmakuId: String?, name: String) {
        guard let source, let danmakuId, !danmakuId.isEmpty else { return }
        isLoadingDanmaku = true

        // 单层 @MainActor 闭包：class 用 [weak self] 会产生"可变捕获"，
        // 再放进嵌套的并发闭包(MainActor.run)里引用会触发编译错误
        Task { @MainActor in
            let list = (try? await ScriptService.shared.danmaku(source, id: danmakuId, name: name)) ?? []
            self.comments = list
            self.isLoadingDanmaku = false
        }
    }
}
