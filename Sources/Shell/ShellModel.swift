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
        pullRefreshEnabled = !Self.isPlayPath(path)
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

    func handleBack() {
        guard let webView else { return }
        if canGoBack {
            webView.goBack()
            return
        }
        // 首页再返回：交给 H5 的 __HG_HANDLE_BACK__，未处理则静默（iOS 无 finish）
        webView.evaluateJavaScript(BridgeScripts.handleBackJS) { _, _ in }
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
        webView.evaluateJavaScript(bridge, completionHandler: nil)
        webView.evaluateJavaScript(cache + promo, completionHandler: nil)
        webView.evaluateJavaScript(BridgeScripts.patchJS, completionHandler: nil)
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
