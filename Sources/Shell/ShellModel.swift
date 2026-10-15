import Foundation
import SwiftUI
import UIKit
import WebKit

/// iOS 侧外壳状态机，逐项对应 `com.hg.app.MainActivity` 的字段与生命周期方法。
///
/// 字段映射：
///  - entryUrl            → entryURL
///  - runtimeApiBase      → runtimeAPIBase
///  - runtimeApiBaseBackup→ apiBaseBackup
///  - trustedHosts        → trustedHosts
///  - pageFinishedOnce    → pageFinishedOnce
///  - h5SplashReady       → h5SplashReady
///  - splashShownAt       → splashShownAt
///  - minSplashMs / maxWaitH5SplashMs → AppConfig 常量
@MainActor
final class ShellModel: ObservableObject {

    enum Phase: Equatable {
        case booting          // 正在连接…（status + loading 可见）
        case loaded           // 页面已加载
        case failed(String)   // 无法连接APP，点此重试
    }

    // MARK: - 已发布状态

    @Published private(set) var phase: Phase = .booting
    @Published private(set) var entryURL: URL?
    @Published private(set) var runtimeAPIBase: String = SeedCatalog.apiBase(forAppEntry: "")
    @Published private(set) var apiBaseBackup: String = SeedCatalog.apiBaseBackup()
    var trustedHosts: [String] = []
    @Published private(set) var splashVisible = true
    @Published private(set) var splashAlpha: Double = 1
    @Published private(set) var pullRefreshEnabled = true
    /// 当前是否在播放页（play.php / /play），决定是否显示横屏键、是否禁下拉刷新
    @Published private(set) var isPlayerPage = false
    /// 是否已锁定横屏（播放态）
    @Published private(set) var isLandscapeForced = false
    /// H5 播放器「速度键」的坐标（点）：原生全屏键据此贴到它右侧同一行
    @Published private(set) var playerControlsFrame: CGRect?
    /// 系统全屏播放器是否正在展示（由 H5 的 webkitbegin/endfullscreen 上报）
    @Published private(set) var systemFullscreenActive = false
    /// 当前视频是否为横向（用于进全屏后自动切横竖屏）；nil = 未知
    @Published private(set) var videoIsLandscape: Bool?
    @Published private(set) var canGoBack = false
    @Published private(set) var loadProgress: Double = 0
    @Published var showSettings = false
    @Published var updatePrompt: UpdatePrompt?

    struct UpdatePrompt: Identifiable, Equatable {
        let id = UUID()
        var latest: String
        var forced: Bool
        var message: String
    }

    // MARK: - 内部状态（对应 MainActivity 私有字段）

    private(set) var pageFinishedOnce = false
    private(set) var h5SplashReady = false
    private(set) var splashShownAt = Date()
    private var dismissed = false
    private var bootstrapToken = UUID()

    private var splashDismissWork: DispatchWorkItem?
    private var splashFallbackWork: DispatchWorkItem?

    weak var webView: WKWebView?

    /// 诊断信息（设置页展示）。
    var diagnostics: [String] {
        [
            "entryUrl: \(entryURL?.absoluteString ?? "-")",
            "runtimeApiBase: \(runtimeAPIBase)",
            "apiBaseBackup: \(apiBaseBackup)",
            "trustedHosts: \(trustedHosts.sorted().joined(separator: ", "))",
            "pageFinishedOnce: \(pageFinishedOnce)",
            "h5SplashReady: \(h5SplashReady)",
            "pullRefreshEnabled: \(pullRefreshEnabled)",
            "isPlayerPage: \(isPlayerPage)",
            "landscapeForced: \(isLandscapeForced)",
            "seeds(debug=\(SeedCatalog.usesDebugSeeds)): \(SeedCatalog.activeSeeds().joined(separator: " "))",
            "promoBindToken: \(PromoBindStore.token().isEmpty ? "-" : PromoBindStore.token())",
            "simulator: \(EnvProbe.isSimulator)",
            "device: \(EnvProbe.deviceFingerprint)",
            "version: \(AppConfig.appVersion)(\(AppConfig.versionCode))",
        ]
    }

    // MARK: - bootstrap（对应 MainActivity.bootstrap）

    func bootstrap() {
        let token = UUID()
        bootstrapToken = token
        dismissed = false
        pageFinishedOnce = false
        h5SplashReady = false
        splashVisible = true
        splashAlpha = 1
        splashShownAt = Date()
        phase = .booting
        loadProgress = 0
        cancelSplashTimers()

        var hosts = Set<String>()
        for seed in SeedCatalog.list(debug: false) { hosts.formUnion(hostsOf(seed)) }
        hosts.formUnion(hostsOf(AppConfig.apiSeed))
        if !apiBaseBackup.isEmpty { hosts.formUnion(hostsOf(apiBaseBackup)) }
        trustedHosts = Array(hosts)
        HostTrustStore.shared.replace(with: Array(hosts))

        HGLog.i("MainActivity", "bootstrap start, seeds=\(SeedCatalog.activeSeeds())")

        Task { [weak self] in
            guard let self else { return }
            let seeds = SeedCatalog.activeSeeds()
            do {
                let entry = try await EntryProbe.pickReachableAsync(from: seeds)
                guard self.bootstrapToken == token else { return }
                self.entryURL = URL(string: entry)
                self.runtimeAPIBase = SeedCatalog.apiBase(forAppEntry: entry)
                self.rememberHost(entry)
                self.rememberHost(self.runtimeAPIBase)
                HGLog.i("MainActivity", "entry picked: \(entry)")
                self.analyticsStart()
                self.loadEntry(entry)
            } catch {
                guard self.bootstrapToken == token else { return }
                HGLog.e("MainActivity", "bootstrap failed: \(error.localizedDescription)")
                self.failBootstrap()
            }
        }
    }

    private func analyticsStart() {
        HgAnalytics.shared.start(remoteBase: nil)
    }

    /// 对应 `bootstrap$lambda$23$lambda$21`：加载 H5 + 启动兜底定时 + 静默查更新。
    private func loadEntry(_ entry: String) {
        guard let url = URL(string: entry) else { failBootstrap(); return }
        webView?.load(URLRequest(url: url))
        scheduleSplashFallback()
        maybeCheckUpdate()
    }

    /// 对应 `maybeCheckUpdate()`：Android 端为空实现，iOS 保持同样语义（不自动弹窗）。
    func maybeCheckUpdate() {
        // no-op by design（与 APK 行为一致）
    }

    /// 对应 `bootstrap$lambda$23$lambda$22`：失败态 UI（status 文案 + 重试点击）。
    private func failBootstrap() {
        splashVisible = false
        cancelSplashTimers()
        phase = .failed(AppConfig.Text.retryTitle)
    }

    // MARK: - 页面生命周期（对应 setupWebView$3）

    func onPageStarted(_ url: String) {
        rememberHost(url)
        updatePullRefreshEnabled(url)
        injectBridge()
        loadProgress = 0
    }

    func onPageProgress(_ value: Double) {
        guard phase == .booting else { return }
        loadProgress = max(loadProgress, min(max(value, 0), 1))
    }

    func onPageFinished(_ url: String) {
        rememberHost(url)
        updatePullRefreshEnabled(url)
        injectBridge()
        pageFinishedOnce = true
        tryDismissBrandSplash()
        phase = .loaded
    }

    func onPageFailed(_ url: String, error: String) {
        HGLog.e("MainActivity", "page failed \(url): \(error)")
        if phase == .booting {
            phase = .failed(AppConfig.Text.retryTitle)
        }
    }

    func onNavigationUpdate(canGoBack: Bool) {
        self.canGoBack = canGoBack
    }

    // MARK: - 闪屏（对应 splashDismissRunnable / splashFallbackRunnable / tryDismissBrandSplash）

    /// 对应 `tryDismissBrandSplash`。
    func tryDismissBrandSplash() {
        guard pageFinishedOnce, h5SplashReady else { return }
        dismissBrandSplash()
    }

    /// 对应 `dismissBrandSplash`：补足最短展示时长后再排队淡出。
    func dismissBrandSplash() {
        guard !dismissed else { return }
        let elapsedMs = UInt64(Date().timeIntervalSince(splashShownAt) * 1000)
        let remaining = AppConfig.minSplashMs > elapsedMs ? AppConfig.minSplashMs - elapsedMs : 0
        cancelSplashTimers()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.fadeOutSplash() }
        }
        splashDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(remaining)), execute: work)
    }

    /// 对应 `splashDismissRunnable$lambda$1`：220ms 淡出后隐藏。
    private func fadeOutSplash() {
        guard !dismissed else { return }
        dismissed = true
        withAnimationTiming { self.splashAlpha = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(AppConfig.splashFadeMs))) { [weak self] in
            self?.splashVisible = false
            self?.splashAlpha = 1
        }
    }

    private func withAnimationTiming(_ body: @escaping () -> Void) {
        // 对应 Android 的 220ms alpha 动画
        withAnimation(.linear(duration: Double(AppConfig.splashFadeMs) / 1000.0)) { body() }
    }

    /// 对应 `splashFallbackRunnable$lambda$2`：等待上限到达后强制就绪。
    private func scheduleSplashFallback() {
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.h5SplashReady = true
                self.tryDismissBrandSplash()
            }
        }
        splashFallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(AppConfig.maxWaitH5SplashMs)), execute: work)
    }

    private func cancelSplashTimers() {
        splashDismissWork?.cancel()
        splashFallbackWork?.cancel()
        splashDismissWork = nil
        splashFallbackWork = nil
    }

    // MARK: - Bridge 回调

    /// 对应 `HgBridge.onH5SplashReady`。
    func h5SplashReadySignalled() {
        h5SplashReady = true
        tryDismissBrandSplash()
    }

    /// 对应 `HgBridge.onRouteChange` → `updatePullRefreshByPath`。
    func routeChanged(_ path: String) {
        updatePullRefreshByPath(path)
    }

    /// 对应 `HgBridge.setPullRefreshEnabled`。
    func setPullRefreshEnabled(_ enabled: Bool) {
        pullRefreshEnabled = enabled
    }

    func reportNavigation(path: String) {
        updatePullRefreshByPath(path)
    }

    // MARK: - 下拉刷新可用性（对应 updatePullRefreshByPath / isPlayPath）

    func updatePullRefreshEnabled(_ url: String) {
        let path = URL(string: url)?.path ?? ""
        updatePullRefreshByPath(path)
    }

    func updatePullRefreshByPath(_ rawPath: String) {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if trimmed.isEmpty {
            path = webView?.url?.path ?? ""
        } else {
            path = trimmed
        }
        let play = Self.isPlayPath(path)
        let wasPlayer = isPlayerPage
        isPlayerPage = play
        pullRefreshEnabled = !play
        if play != wasPlayer {
            setPlayerModeJS(play)
            if play {
                verifyPlayerEnhancement()
                schedulePlayerLayout()
                refreshVideoOrientation()
                applyStripPolicy()
            } else {
                playerControlsFrame = nil
            }
        }
        // 离开播放页时自动恢复竖屏，避免误锁横屏
        if !play, isLandscapeForced {
            exitPlayerFullscreen()
        }
    }

    // MARK: - 播放页增强（隐藏 H5 导航 / 沉浸式铺满 / 视频居中）

    private func setPlayerModeJS(_ on: Bool) {
        let js = "try{window.HGApp&&window.HGApp.setPlayerMode&&window.HGApp.setPlayerMode(\(on ? "true" : "false"));}catch(e){}"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func setImmersiveJS(_ on: Bool) {
        let js = "try{window.HGApp&&window.HGApp.setImmersive&&window.HGApp.setImmersive(\(on ? "true" : "false"));}catch(e){}"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func centerVideoJS() {
        webView?.evaluateJavaScript("try{window.HGApp&&window.HGApp.centerVideo&&window.HGApp.centerVideo();}catch(e){}", completionHandler: nil)
    }

    /// 播放器调优布局（控件常显 / 选集条让位 / 速度键左移 / 满宽渲染 / 稳定居中）。
    func layoutPlayerJS(force: Bool) {
        guard isPlayerPage else { return }
        let flag = force ? "true" : "false"
        let js = "try{window.HGApp&&window.HGApp.layoutPlayer&&window.HGApp.layoutPlayer(" + flag + ");}catch(e){}"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 播放页渲染完成后分几次重排（H5 控件/选集条是异步出现的）。
    func schedulePlayerLayout() {
        for delay in [0.5, 1.4, 2.6, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.layoutPlayerJS(force: true)
            }
        }
    }

    /// 页面回传速度键坐标（CSS px → 点：按视口宽度换算）。
    func updatePlayerControlsFrame(x: Double, y: Double, width: Double, height: Double, viewportWidth: Double) {
        guard viewportWidth > 1, let webView, webView.frame.width > 1 else { return }
        let scale = webView.frame.width / CGFloat(viewportWidth)
        guard scale.isFinite, scale > 0 else { return }
        let frame = CGRect(x: CGFloat(x) * scale,
                           y: CGFloat(y) * scale,
                           width: CGFloat(width) * scale,
                           height: CGFloat(height) * scale)
        if let current = playerControlsFrame,
           abs(current.midY - frame.midY) < 1, abs(current.maxX - frame.maxX) < 1 {
            return
        }
        playerControlsFrame = frame
    }

    /// H5 上报系统全屏状态：按视频比例自动切横竖屏（横视频转横屏、竖视频保持竖屏）。
    func handleFullscreenState(active: Bool, width: Double, height: Double) {
        systemFullscreenActive = active
        if width > 0, height > 0 {
            videoIsLandscape = width >= height
            HGLog.i("Fullscreen", "video \(Int(width))x\(Int(height)) active=\(active)")
        }
        guard active else {
            AppOrientation.shared.unlock()
            return
        }
        if let landscape = videoIsLandscape {
            if landscape {
                AppOrientation.shared.lockLandscape()
            } else {
                AppOrientation.shared.lockPortrait()
            }
        }
    }

    /// 主动问一次视频比例（进播放页时调用，供按下全屏键时同步决定方向）。
    func refreshVideoOrientation() {
        guard isPlayerPage, let webView else { return }
        webView.evaluateJavaScript("try{window.HGApp&&window.HGApp.videoInfo?window.HGApp.videoInfo():''}catch(e){''}") { result, _ in
            guard let text = result as? String, let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
            let w = (obj["w"] as? Double) ?? Double((obj["w"] as? Int) ?? 0)
            let h = (obj["h"] as? Double) ?? Double((obj["h"] as? Int) ?? 0)
            guard w > 0, h > 0, obj["fallback"] == nil else { return }
            Task { @MainActor in
                self.videoIsLandscape = w >= h
                HGLog.i("Fullscreen", "video aspect cached \(Int(w))x\(Int(h))")
            }
        }
    }

    /// 选集条隐藏策略（默认隐藏，避免压画面）。
    func applyStripPolicy() {
        guard isPlayerPage, let webView else { return }
        let hide = AppConfig.hidePlayerStrip ? "true" : "false"
        webView.evaluateJavaScript("try{window.HGApp&&window.HGApp.setStripHidden&&window.HGApp.setStripHidden(\(hide));}catch(e){}", completionHandler: nil)
    }

    /// 调优开关即时生效。
    func applyPlayerTuning() {
        guard let webView else { return }
        let on = AppConfig.playerTuneEnabled ? "true" : "false"
        let js = BridgeScripts.playerTuneFlagJS(AppConfig.playerTuneEnabled)
            + "try{window.HGApp&&window.HGApp.setPlayerTuning&&window.HGApp.setPlayerTuning(" + on + ");}catch(e){}"
        webView.evaluateJavaScript(js, completionHandler: nil)
        layoutPlayerJS(force: true)
    }

    /// 看门狗：进入播放页/沉浸式后读一次 JS 诊断，若视频不可见（或 JS 侧已回滚）就整体回退，
    /// 宁可留导航也不能黑屏只剩声音。
    private func verifyPlayerEnhancement() {
        guard let webView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            webView.evaluateJavaScript("try{window.HGApp&&window.HGApp.playerDiag?window.HGApp.playerDiag():''}catch(e){''}") { result, _ in
                guard let text = result as? String, !text.isEmpty else { return }
                HGLog.i("Player", "diag: \(text)")
                guard let data = text.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
                let videos = (object["videos"] as? Int) ?? 0
                let visible = (object["visible"] as? Bool) ?? true
                let rollback = (object["rollback"] as? String) ?? ""
                guard videos > 0, !visible || !rollback.isEmpty else { return }
                Task { @MainActor in
                    guard let self else { return }
                    HGLog.w("Player", "视频不可见（rollback=\(rollback)），回退播放页增强避免黑屏")
                    self.setImmersiveJS(false)
                    self.setPlayerModeJS(false)
                    if self.isLandscapeForced {
                        self.isLandscapeForced = false
                        AppOrientation.shared.unlock()
                    }
                    self.centerVideoJS()
                    self.showToast("已回退播放页增强（避免黑屏）")
                }
            }
        }
    }

    // MARK: - 播放页横屏 / 全屏（iOS 无 orientation.lock，由外壳提供）

    /// 进播放态：隐藏 H5 导航 + 锁横屏 + 沉浸式铺满 + 优先进原生全屏播放。
    func enterPlayerFullscreen() {
        // 先按视频比例定方向（横视频转横屏、竖视频保持竖屏），再进系统全屏，避免横视频竖着显示
        if let landscape = videoIsLandscape {
            if landscape { AppOrientation.shared.lockLandscape() } else { AppOrientation.shared.lockPortrait() }
        } else {
            AppOrientation.shared.unlock()
        }
        refreshVideoOrientation()
        isLandscapeForced = true
        setImmersiveJS(true)
        webView?.evaluateJavaScript(BridgeScripts.enterNativeFullscreenJS) { result, _ in
            if let text = result as? String, text != "native", text != "std" {
                HGLog.w("Orientation", "no fullscreen-capable video element (result=\(text))；退化为横屏铺满")
            }
        }
        scheduleResizeDispatch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.centerVideoJS() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.centerVideoJS() }
        verifyPlayerEnhancement()
    }

    /// 退出播放态：退出全屏 + 取消沉浸式 + 恢复竖屏。
    func exitPlayerFullscreen() {
        AppOrientation.shared.unlock()
        isLandscapeForced = false
        setImmersiveJS(false)
        webView?.evaluateJavaScript(BridgeScripts.exitNativeFullscreenJS, completionHandler: nil)
        scheduleResizeDispatch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.centerVideoJS() }
    }

    func togglePlayerFullscreen() {
        if systemFullscreenActive {
            webView?.evaluateJavaScript(BridgeScripts.exitNativeFullscreenJS, completionHandler: nil)
            systemFullscreenActive = false
            AppOrientation.shared.unlock()
            isLandscapeForced = false
            return
        }
        isLandscapeForced ? exitPlayerFullscreen() : enterPlayerFullscreen()
    }

    /// 对应 H5 的 `HGApp.setOrientation('landscape'|'portrait'|'auto')`。
    func setOrientation(_ mode: String) {
        switch mode.lowercased() {
        case "landscape", "land", "horizontal":
            enterPlayerFullscreen()
        case "portrait", "port", "vertical":
            exitPlayerFullscreen()
        default:
            AppOrientation.shared.unlock()
            isLandscapeForced = false
            scheduleResizeDispatch()
        }
    }

    /// 旋转/几何变化后通知 H5 重排，否则播放器仍按旧视口居中而看起来偏心。
    func scheduleResizeDispatch() {
        for delay in [0.35, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.webView?.evaluateJavaScript(BridgeScripts.resizeDispatchJS, completionHandler: nil)
            }
        }
    }

    /// 对应 `isPlayPath`：命中 play.php 或 `/play` `/play/` 前缀时关闭下拉刷新。
    static func isPlayPath(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("play.php") { return true }
        guard let cut = lower.split(separator: "#").first else { return false }
        let head = cut.split(separator: "?").first.map(String.init) ?? ""
        return head == "/play" || head.hasPrefix("/play/")
    }

    // MARK: - 域名白名单（对应 rememberHost / isTrustedHost）

    func rememberHost(_ urlString: String) {
        guard let host = hostsOf(urlString).first else { return }
        HostTrustStore.shared.add(host)
        var set = Set(trustedHosts)
        if set.insert(host).inserted {
            trustedHosts = Array(set).sorted()
        }
    }

    private func hostsOf(_ urlString: String) -> [String] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let host = URL(string: trimmed)?.host?.lowercased(), !host.isEmpty else { return [] }
        return [host]
    }

    func isTrustedHost(_ host: String?) -> Bool {
        guard let host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return trustedHosts.contains(host.lowercased())
    }

    // MARK: - 导航拦截（对应 handleNav / openUrlOrScheme）

    /// 返回 true 表示外壳已接管（WebView 不再加载）。
    @discardableResult
    func handleNav(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            if isTrustedHost(url.host) { return false }
            openURLOrScheme(url)
            return true
        }
        openURLOrScheme(url)
        return true
    }

    /// 对应 `openUrlOrScheme`：http/https 外开；intent: 解析；其余 scheme 直接尝试，失败回退 browser_fallback_url。
    func openURLOrScheme(_ url: URL) {
        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !absolute.isEmpty else { return }
        let scheme = url.scheme?.lowercased() ?? ""

        if scheme == "http" || scheme == "https" || scheme == "itms-services" {
            UIApplication.shared.open(url, options: [:]) { ok in
                if !ok { HGLog.w("MainActivity", "openUrlOrScheme failed: \(absolute)") }
            }
            return
        }

        if scheme == "intent" {
            handleAndroidIntent(url)
            return
        }

        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in
                guard let self else { return }
                HGLog.w("MainActivity", "scheme not handled: \(absolute)")
                if let fallback = self.intentFallbackURL(absolute), let target = URL(string: fallback) {
                    UIApplication.shared.open(target)
                }
            }
        }
    }

    /// Android `intent://...#Intent;scheme=x;S.browser_fallback_url=y;end` 的 iOS 对等解析。
    private func handleAndroidIntent(_ url: URL) {
        let absolute = url.absoluteString
        if let fallback = intentFallbackURL(absolute), let target = URL(string: fallback) {
            UIApplication.shared.open(target)
            return
        }
        if let scheme = intentSchemeValue(absolute), let target = URL(string: scheme) {
            UIApplication.shared.open(target)
            return
        }
        HGLog.w("MainActivity", "unresolvable intent: \(absolute)")
    }

    private func intentFallbackURL(_ absolute: String) -> String? {
        guard let range = absolute.range(of: "S.browser_fallback_url=") else { return nil }
        let tail = absolute[range.upperBound...]
        let value = tail.split(separator: ";").first.map(String.init) ?? ""
        let decoded = value.removingPercentEncoding ?? value
        return decoded.hasPrefix("intent:") || decoded.isEmpty ? nil : decoded
    }

    private func intentSchemeValue(_ absolute: String) -> String? {
        let parts = absolute.split(separator: ";")
        for part in parts {
            let text = String(part)
            if text.hasPrefix("scheme=") {
                let value = String(text.dropFirst("scheme=".count))
                return value.isEmpty ? nil : "\(value)://"
            }
        }
        return nil
    }

    // MARK: - 返回（对应 handleNativeBack）

    /// 对应 `handleNativeBack`：**先问 H5**（`__HG_HANDLE_BACK__`），返回 `handled` 就停手；
    /// 否则能后退就后退。iOS 用屏幕左缘手势触发（不再放悬浮按钮，避免压住 H5 头部图标）。
    func handleBack() {
        guard let webView else { return }
        webView.evaluateJavaScript(BridgeScripts.handleBackJS) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let text = (result as? String) ?? ""
                if text.lowercased().contains("handled") {
                    HGLog.d("MainActivity", "back handled by H5")
                    return
                }
                if webView.canGoBack {
                    webView.goBack()
                } else {
                    self.canGoBack = false
                }
            }
        }
    }

    // MARK: - 更新流程（对应 requestUpdateFromJs / notifyUpdateResult）

    func requestUpdateFromJS() {
        let base = runtimeAPIBase
        showToast(AppConfig.Text.downloading)
        Task { [weak self] in
            guard let self else { return }
            let info = await UpdateService.shared.fetchUpdateInfoAsync(apiBase: base)
            guard let info, UpdateService.needsUpdate(info) else {
                if info == nil {
                    self.showToast(AppConfig.Text.fetchVersionFailed)
                    self.notifyUpdateResult(ok: false, message: AppConfig.Text.fetchVersionFailed)
                } else {
                    self.notifyUpdateResult(ok: true, message: "已是最新版本 \(AppConfig.appVersion)")
                }
                return
            }
            guard let target = info.firstURL else {
                self.showToast(AppConfig.Text.noApkUrl)
                self.notifyUpdateResult(ok: false, message: AppConfig.Text.noApkUrl)
                return
            }
            let forced = UpdateService.isForced(info)
            self.updatePrompt = UpdatePrompt(latest: info.latest, forced: forced, message: "发现新版本 \(info.latest)")
            await self.performUpdate(urlString: target, latest: info.latest)
        }
    }

    func performUpdate(urlString: String, latest: String) async {
        if urlString.hasPrefix("itms-services://") {
            if UpdateService.shared.openItmsServices(urlString) {
                notifyUpdateResult(ok: true, message: "已交给系统安装")
            } else {
                showToast(AppConfig.Text.installFailed)
                notifyUpdateResult(ok: false, message: AppConfig.Text.installFailed)
            }
            return
        }

        let result = await UpdateService.shared.downloadPackage(urlString) { ratio in
            Task { @MainActor in self.loadProgress = max(self.loadProgress, ratio) }
        }
        guard result.ok else {
            showToast(result.message)
            notifyUpdateResult(ok: false, message: result.message)
            return
        }
        let installResult = UpdateService.shared.installPackage(at: result.message)
        if !installResult.ok { showToast(installResult.message) }
        notifyUpdateResult(ok: installResult.ok, message: installResult.ok ? "下载完成，请按提示安装" : installResult.message)
    }

    /// 对应 `notifyUpdateResult`：把结果以 CustomEvent 回传 H5。
    func notifyUpdateResult(ok: Bool, message: String) {
        let js = BridgeScripts.updateResultJS(ok: ok, message: message)
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - 脚本注入（对应 injectNativeBridge / onPageStarted / onPageFinished）

    func injectBridge() {
        guard let webView else { return }
        let bridge = BridgeScripts.bridgeJS(
            appVersion: AppConfig.appVersion,
            apiBase: runtimeAPIBase,
            apiBaseBackup: apiBaseBackup
        )
        let cache = BridgeScripts.bridgeCacheJS(apiBase: runtimeAPIBase, promoAgentId: "")
        let promo = BridgeScripts.promoTokenJS(PromoBindStore.token())
        let extra = BridgeScripts.extraAdsFlagJS(AppConfig.extraAdsEnabled)
        let playerFlag = BridgeScripts.playerExtraFlagJS(AppConfig.playerExtraEnabled)
        let tuneFlag = BridgeScripts.playerTuneFlagJS(AppConfig.playerTuneEnabled)
        let v2 = BridgeScripts.iosPatchJS(ownHosts: BridgeScripts.staticOwnHosts(includeDebugSeeds: SeedCatalog.usesDebugSeeds)
            + trustedHosts)
        webView.evaluateJavaScript(bridge, completionHandler: nil)
        webView.evaluateJavaScript(cache + promo + extra + playerFlag + tuneFlag, completionHandler: nil)
        webView.evaluateJavaScript(BridgeScripts.patchJS, completionHandler: nil)
        webView.evaluateJavaScript(v2, completionHandler: nil)
        webView.evaluateJavaScript("try{window.HGApp&&window.HGApp.sweepAds&&window.HGApp.sweepAds();}catch(e){}", completionHandler: nil)
        setPlayerModeJS(isPlayerPage)
    }

    /// 设置页切换「额外去广告」/「播放页沉浸式」后实时生效（无需重装）。
    func applyExtraAdsSetting() {
        guard let webView else { return }
        let js = BridgeScripts.extraAdsFlagJS(AppConfig.extraAdsEnabled)
            + BridgeScripts.playerExtraFlagJS(AppConfig.playerExtraEnabled)
            + "try{window.HGApp&&window.HGApp.sweepAds&&window.HGApp.sweepAds();}catch(e){}"
        webView.evaluateJavaScript(js, completionHandler: nil)
        setPlayerModeJS(isPlayerPage)
        if isPlayerPage {
            setImmersiveJS(isLandscapeForced)
            centerVideoJS()
        }
    }

    /// 让原生侧主动刷新一次桥接缓存（促销 token 变化时）。
    func pushPromoTokenToPage() {
        webView?.evaluateJavaScript(BridgeScripts.promoTokenJS(PromoBindStore.token()), completionHandler: nil)
    }

    func reload() {
        webView?.reload()
    }

    func loadIfNeeded() {
        guard let webView, let entryURL, webView.url == nil else { return }
        webView.load(URLRequest(url: entryURL))
    }

    /// 由 `WebShellView.makeUIView` 注册，等价于 Android `this.webView = WebView(context)`。
    func register(webView: WKWebView) {
        self.webView = webView
        if let current = webView.url?.absoluteString, !current.isEmpty {
            rememberHost(current)
        }
    }

    // MARK: - Toast（对应 Android Toast）

    func showToast(_ text: String) {
        HGLog.i("Toast", text)
        NotificationCenter.default.post(name: .hgToast, object: text)
    }
}

extension Notification.Name {
    static let hgToast = Notification.Name("hg.toast")
}
