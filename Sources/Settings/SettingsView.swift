import SwiftUI
import UIKit
import WebKit

/// 外壳设置 / 诊断页（iOS 侧新增，Android 端无对应界面；用于等价能力的手工操作与排障）。
/// 所有改动都作用在 Android 端存在的同一批参数上：种子列表、API 基址、下拉刷新、渠道 token、桥接状态。
struct SettingsView: View {

    @ObservedObject var model: ShellModel
    @Environment(\.dismiss) private var dismiss

    @State private var devHost: String = UserDefaults.standard.string(forKey: SeedCatalog.Keys.devHost) ?? ""
    @State private var apiBaseOverride: String = UserDefaults.standard.string(forKey: SeedCatalog.Keys.apiBaseOverride) ?? ""
    @State private var useDebugSeeds: Bool = UserDefaults.standard.bool(forKey: SeedCatalog.Keys.useDebugSeeds)
    @State private var tokenInput: String = ""
    @State private var toast: String?
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationView {
            List {
                Section("运行状态") {
                    ForEach(model.diagnostics, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section("H5 种子 / API") {
                    Toggle("使用调试种子（127.0.0.1:5173 等）", isOn: $useDebugSeeds)
                    TextField("DEBUG_HOST（如 192.168.1.10）", text: $devHost)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    TextField("API 基址覆盖（默认 \(AppConfig.apiSeed)）", text: $apiBaseOverride)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    Button("保存并重新 bootstrap") {
                        UserDefaults.standard.set(useDebugSeeds, forKey: SeedCatalog.Keys.useDebugSeeds)
                        UserDefaults.standard.set(devHost, forKey: SeedCatalog.Keys.devHost)
                        UserDefaults.standard.set(apiBaseOverride, forKey: SeedCatalog.Keys.apiBaseOverride)
                        model.bootstrap()
                        showToast("已重新连接")
                    }
                    Button("仅重新加载当前页面") { model.reload() }
                }

                Section("渠道绑定（PromoBind）") {
                    Text("当前 bind_token：\(PromoBindStore.token().isEmpty ? "（空）" : PromoBindStore.token())")
                        .font(.system(size: 12, design: .monospaced))
                    TextField("手动写入 bind_token", text: $tokenInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("保存 token") {
                        if PromoBindStore.save(tokenInput) {
                            model.pushPromoTokenToPage()
                            showToast("已写入并推送到 H5")
                        } else {
                            showToast("token 为空或未变化")
                        }
                    }
                    Button("清空 token", role: .destructive) {
                        PromoBindStore.clear()
                        model.pushPromoTokenToPage()
                        showToast("已清空")
                    }
                    Button("立即重扫（剪贴板 / Inbox / 归因）") {
                        // 剪贴板读取会弹系统授权框，因此只在用户显式点击时执行（includePasteboard: true）
                        PromoCapture.captureAll(launchURL: nil, includePasteboard: true)
                        model.pushPromoTokenToPage()
                        showToast("重扫完成：\(PromoBindStore.token().isEmpty ? "未获取到 token" : PromoBindStore.token())")
                    }
                }

                Section("桥接与补丁") {
                    Button("重新注入 HuangGuoNative + 补丁") {
                        model.injectBridge()
                        showToast("已注入")
                    }
                    Button("校验补丁状态（读 __HG_PATCH_V1__）") { verifyPatch() }
                    Button("触发 checkUpdate()") { model.requestUpdateFromJS() }
                    Button("调用返回键协商 __HG_HANDLE_BACK__") { model.handleBack() }
                }

                Section("下拉刷新") {
                    Toggle("允许下拉刷新", isOn: Binding(
                        get: { model.pullRefreshEnabled },
                        set: { model.setPullRefreshEnabled($0) }
                    ))
                    Text("播放页（play.php / /play）自动禁用，对应 updatePullRefreshByPath")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("日志（最近 \(HGLog.snapshot().count) 条）") {
                    Button("刷新日志") { reloadToken = UUID() }
                    ForEach(HGLog.snapshot().suffix(60)) { line in
                        Text(line.display)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(line.level == .error ? .red : .secondary)
                    }
                    Button("清空日志", role: .destructive) { HGLog.clear() }
                }
            }
            .id(reloadToken)
            .navigationTitle("外壳诊断")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(text: toast).padding(.bottom, 24)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func verifyPatch() {
        guard let webView = model.webView else {
            showToast("WebView 未就绪")
            return
        }
        webView.evaluateJavaScript("JSON.stringify({native:!!window.__HG_NATIVE_APP__,patch:(window.HGApp&&window.HGApp.__patch)||'',vip:typeof window.HuangGuoNative})") { result, error in
            if let error {
                showToast("校验失败：\(error.localizedDescription)")
            } else if let text = result as? String {
                showToast(text)
                HGLog.i("Shell", "patch state: \(text)")
            }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { toast = nil }
    }
}
