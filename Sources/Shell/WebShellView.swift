import SwiftUI
import UIKit
import WebKit

/// `WKWebView` 外壳，对应 `MainActivity.setupWebView() + onCreate()` 中的 WebView 配置。
///
/// Android 设置 → iOS 对等项：
///  - `setUserAgentString(默认 UA + " HuangGuoApp/x HGApp/x")` → `customUserAgent`
///  - `setJavaScriptEnabled(true)`                 → `defaultWebpagePreferences.allowsContentJavaScript`
///  - `setDomStorageEnabled(true)`                 → `WKWebsiteDataStore.default()`
///  - `setMediaPlaybackRequiresUserGesture(false)` → `mediaTypesRequiringUserActionForPlayback = []`
///  - `setSupportZoom/setBuiltInZoomControls/setDisplayZoomControls(false)` → scrollView 缩放锁定
///  - `setTextZoom(100)`                           → `pageZoom = 1.0`
///  - `setUseWideViewPort/setLoadWithOverviewMode` → viewport 生效 + `pageZoom = 1.0`
///  - `setMixedContentMode(MIXED_CONTENT_ALWAYS_ALLOW)` → Info.plist 的 ATS 任意加载
///  - `setSupportMultipleWindows(true)` + `setJavaScriptCanOpenWindowsAutomatically(true)`
///      → `javaScriptCanOpenWindowsAutomatically` + `createWebViewWith`
///  - `setBackgroundColor(#22242A)`                → 容器与 scrollView 背景
///  - `SwipeRefreshLayout`（`isPlayPath` 时禁用）   → `UIRefreshControl`
struct WebShellView: UIViewRepresentable {

    @ObservedObject var model: ShellModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        // 混合内容（对应 setMixedContentMode(MIXED_CONTENT_ALWAYS_ALLOW)）由 Info.plist 的
        // NSAllowsArbitraryLoads / NSAllowsArbitraryLoadsInWebContent 覆盖，不触碰私有键。

        // 注入时机：全部在 atDocumentStart 装好，避免首页首个数据请求抢在补丁之前
        // （真机上实测：只靠 didStart 的 evaluateJavaScript 会漏掉首页两排外链广告图标）。
        // 桥接/补丁都带守卫可重复执行；页面开始/结束时仍会再注入一次以刷新 apiBase / token / 开关。
        let ownHosts = BridgeScripts.staticOwnHosts(includeDebugSeeds: SeedCatalog.usesDebugSeeds)
        let startScripts = [
            "window.__HG_NATIVE_APP__=1;",
            BridgeScripts.extraAdsFlagJS(AppConfig.extraAdsEnabled),
            BridgeScripts.bridgeJS(appVersion: AppConfig.appVersion,
                                   apiBase: AppConfig.apiSeed,
                                   apiBaseBackup: AppConfig.apiSeedBackup),
            BridgeScripts.patchJS,
            BridgeScripts.iosPatchJS(ownHosts: ownHosts),
        ]
        for source in startScripts {
            controller.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // 关掉自带侧滑返回，改用左缘手势走「先问 H5」的返回语义（对齐 Android 物理返回键）
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = true
        webView.isOpaque = true
        webView.backgroundColor = AppConfig.chromeColor
        webView.scrollView.backgroundColor = AppConfig.chromeColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // 纵向回弹必须保留，否则 UIRefreshControl 收不到下拉手势
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.maximumZoomScale = 1       // setSupportZoom(false)
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.bouncesZoom = false        // setBuiltInZoomControls(false)
        webView.pageZoom = 1.0                        // setTextZoom(100)
        if #available(iOS 16.4, *) {
            webView.isInspectable = AppConfig.isDebugBuild
        }

        let refresh = UIRefreshControl()
        refresh.tintColor = AppConfig.accentColor
        refresh.backgroundColor = AppConfig.refreshBackgroundColor
        refresh.isEnabled = true
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        webView.customUserAgent = WebShellView.composedUserAgent()

        // 左缘返回手势：先问 H5（__HG_HANDLE_BACK__），未处理才 goBack。取代原悬浮按钮，避免压住 H5 头部图标。
        let edgePan = UIScreenEdgePanGestureRecognizer(target: context.coordinator,
                                                       action: #selector(Coordinator.handleEdgePan(_:)))
        edgePan.edges = .left
        edgePan.cancelsTouchesInView = false
        webView.addGestureRecognizer(edgePan)

        let bridge = WebBridge(model: model, webView: webView)
        controller.add(bridge, name: AppConfig.messageHandlerName)
        context.coordinator.bridge = bridge
        context.coordinator.attach(webView)

        model.register(webView: webView)

        DispatchQueue.main.async {
            model.loadIfNeeded()
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 对应 SwipeRefreshLayout.setEnabled(!isPlayPath)
        webView.scrollView.refreshControl?.isEnabled = model.pullRefreshEnabled
        webView.scrollView.alwaysBounceVertical = model.pullRefreshEnabled
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: AppConfig.messageHandlerName)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    /// UA = 默认 UA + " HuangGuoApp/<version> HGApp/<version>"（与 Android 拼接顺序一致）。
    /// 不读私有 `userAgent` 键，避免 KVC 抛 `NSUnknownKeyException`。
    static func composedUserAgent() -> String {
        fallbackUserAgent() + AppConfig.userAgentSuffix
    }

    static func fallbackUserAgent() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion)_\(os.minorVersion)"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(version) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    // MARK: - Coordinator

    /// 主 actor 隔离：WebKit 的 delegate 回调都在主线程投递，
    /// 且 Xcode 16（iOS 18 SDK）起这些协议自带 `@MainActor` 标注。
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        let model: ShellModel
        var bridge: WebBridge?
        private var progressObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private weak var webView: WKWebView?

        init(model: ShellModel) {
            self.model = model
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            // KVO 闭包不在主 actor 上，因此只读 change.newValue（纯值），
            // 并把 model 提成强引用局部量，再跳主线程处理（避免在并发闭包里引用捕获的 weak self）。
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue, let model = self?.model else { return }
                Task { @MainActor in model.onPageProgress(value) }
            }
            canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue, let model = self?.model else { return }
                Task { @MainActor in model.onNavigationUpdate(canGoBack: value) }
            }
        }

        func detach() {
            progressObservation?.invalidate()
            canGoBackObservation?.invalidate()
            progressObservation = nil
            canGoBackObservation = nil
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            sender.endRefreshing()
            model.reload()
        }

        /// 左缘右滑 = 返回（对齐 Android 物理返回键语义）。
        @objc func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let translation = gesture.translation(in: gesture.view).x
            let velocity = gesture.velocity(in: gesture.view).x
            guard translation > 60 || velocity > 500 else { return }
            model.handleBack()
        }

        // MARK: 导航策略（对应 shouldOverrideUrlLoading → handleNav）

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            let trusted = HostTrustStore.shared.isTrusted(url.host)
            let isNewWindow = navigationAction.targetFrame == nil
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false

            // 非 http(s)：alipays / weixin / intent: / itms-services … 一律交外壳外开
            if scheme != "http" && scheme != "https" {
                _ = model.handleNav(url)
                decisionHandler(.cancel)
                return
            }

            // 新窗口（target=_blank 等）：对应 Android WebChromeClient.onCreateWindow
            if isNewWindow {
                decisionHandler(.cancel)
                if trusted {
                    loadInPlace(url, webView: webView)
                } else {
                    _ = model.handleNav(url)
                }
                return
            }

            // 主框架跳转到白名单以外的域名 → 交系统浏览器
            if isMainFrame && !trusted {
                _ = model.handleNav(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        private func loadInPlace(_ url: URL, webView: WKWebView) {
            model.rememberHost(url.absoluteString)
            model.updatePullRefreshEnabled(url.absoluteString)
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.onPageStarted(webView.url?.absoluteString ?? "")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.onPageFinished(webView.url?.absoluteString ?? "")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            model.onPageFailed(webView.url?.absoluteString ?? "", error: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            model.onPageFailed(webView.url?.absoluteString ?? "", error: error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            HGLog.w("MainActivity", "web content process terminated, reloading")
            webView.reload()
        }

        // MARK: 新窗口（对应 WebChromeClient.onCreateWindow）

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if HostTrustStore.shared.isTrusted(url.host) {
                    loadInPlace(url, webView: webView)
                } else {
                    _ = model.handleNav(url)
                }
            }
            return nil
        }

        // MARK: 原生弹窗（对应 WebChromeClient 默认实现）

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let box = CallbackBox(completionHandler)
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in box.value() })
            UpdateService.topViewController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let box = CallbackBox(completionHandler)
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in box.value(true) })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in box.value(false) })
            UpdateService.topViewController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let box = CallbackBox(completionHandler)
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                box.value(alert.textFields?.first?.text)
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in box.value(nil) })
            UpdateService.topViewController()?.present(alert, animated: true)
        }
    }
}
