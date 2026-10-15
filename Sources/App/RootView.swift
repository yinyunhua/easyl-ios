import SwiftUI
import UIKit

/// 外壳根视图，对应 `MainActivity.onCreate` 里的 FrameLayout 叠层结构：
///   FrameLayout(#22242A)
///     ├─ SwipeRefreshLayout → WebView
///     ├─ ImageView(splash_brand)   品牌闪屏
///     ├─ ProgressBar               连接中指示
///     └─ TextView("正在连接…" / "无法连接APP，点此重试")
struct RootView: View {

    @StateObject private var model = ShellModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var toastText: String?
    @State private var toastToken = UUID()

    var body: some View {
        ZStack {
            Color(uiColor: AppConfig.chromeColor)
                .ignoresSafeArea()

            WebShellView(model: model)
                .ignoresSafeArea(edges: .bottom)

            switch model.phase {
            case .booting:
                LoadingOverlay(progress: model.loadProgress)
            case .failed(let text):
                RetryOverlay(text: text) { model.bootstrap() }
            case .loaded:
                EmptyView()
            }

            if model.splashVisible {
                SplashOverlay(alpha: model.splashAlpha)
            }

            overlayControls
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
        .alert(item: $model.updatePrompt) { prompt in
            if prompt.forced {
                return Alert(
                    title: Text("发现新版本"),
                    message: Text("当前版本 \(AppConfig.appVersion)，最新版本 \(prompt.latest)。请更新后继续使用。"),
                    primaryButton: .default(Text("立即更新")) {
                        Task { await updateFromPrompt() }
                    },
                    secondaryButton: .cancel(Text("稍后"))
                )
            }
            return Alert(
                title: Text("发现新版本"),
                message: Text("当前版本 \(AppConfig.appVersion)，最新版本 \(prompt.latest)。"),
                primaryButton: .default(Text("立即更新")) {
                    Task { await updateFromPrompt() }
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
        .onAppear {
            seedPromoBinding()
            model.bootstrap()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            // 对应 onResume 中的三个 capture 调用
            PromoCapture.captureAll(launchURL: nil)
            model.pushPromoTokenToPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hgToast)) { note in
            showToast(note.object as? String ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .hgPromoBindUpdated)) { _ in
            model.pushPromoTokenToPage()
        }
    }

    // MARK: - 悬浮控件

    private var overlayControls: some View {
        ZStack(alignment: .topTrailing) {
            // 播放页：全屏键贴在 H5「速度键」右侧同一行（坐标由 JS 回传）；未回传时退回右上角
            if model.isPlayerPage {
                playerFullscreenButton
            }

            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    if AppConfig.isDebugBuild {
                        Button {
                            model.showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("外壳设置")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                Spacer()

                HStack {
                    Spacer()
                    // 长按左下角 1.2s 打开外壳诊断（Release 构建同样可用）
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 1.2) { model.showSettings = true }
                }

                if let toastText {
                    ToastView(text: toastText)
                        .padding(.bottom, 42)
                        .id(toastToken)
                }
            }
        }
    }

    /// 全屏键：优先贴在 H5 速度键右侧（同一行），拿不到坐标时退回右上角。
    private var playerFullscreenButton: some View {
        GeometryReader { geo in
            let size = geo.size
            let frame = model.playerControlsFrame
            let side: CGFloat = 30
            let x = frame.map { min(size.width - side / 2 - 6, max(side / 2 + 6, $0.maxX + 22)) }
                ?? (size.width - 26)
            let y = frame.map { min(size.height - side / 2 - 6, max(side / 2 + 6, $0.midY)) } ?? 46

            Button {
                model.togglePlayerFullscreen()
            } label: {
                Image(systemName: model.isLandscapeForced
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: side, height: side)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .opacity(0.62)
            .position(x: x, y: y)
            .accessibilityLabel(model.isLandscapeForced ? "退出全屏" : "全屏播放")
        }
    }

    private func showToast(_ text: String) {
        guard !text.isEmpty else { return }
        toastText = text
        toastToken = UUID()
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if toastToken == token { toastText = nil }
        }
    }

    private func seedPromoBinding() {
        // 对应 MainActivity.onCreate 的 PromoBindCapture.captureAll(context, intent)
        var launchURL: URL?
        if let raw = UserDefaults.standard.string(forKey: "hg.lastLaunchURL"), let url = URL(string: raw) {
            launchURL = url
        }
        PromoCapture.captureAll(launchURL: launchURL)
    }

    private func updateFromPrompt() async {
        guard let prompt = model.updatePrompt else { return }
        model.updatePrompt = nil
        let base = model.runtimeAPIBase
        let info = await UpdateService.shared.fetchUpdateInfoAsync(apiBase: base)
        guard let target = info?.firstURL else {
            model.showToast(AppConfig.Text.noApkUrl)
            model.notifyUpdateResult(ok: false, message: AppConfig.Text.noApkUrl)
            return
        }
        await model.performUpdate(urlString: target, latest: prompt.latest)
    }
}
