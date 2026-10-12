import SwiftUI
import UIKit

/// 自检页：内置资源、源状态、网络连通性、脚本日志，一眼定位"没内容/播不了"的原因
struct DiagnosticsView: View {
    @EnvironmentObject private var store: SourceStore
    @ObservedObject private var log = LogBus.shared

    @State private var bundleDemoJS = false
    @State private var bundleDemoM3U = false
    @State private var networkResult = "未测试"
    @State private var testing = false
    @State private var sourceTestResult: [String: String] = [:]
    @State private var testingSource: String?

    var body: some View {
        List {
            Section("内置资源") {
                InfoRow("demo.js（演示源）", bundleDemoJS ? "已打包 ✅" : "缺失 ❌")
                InfoRow("demo.m3u（演示直播）", bundleDemoM3U ? "已打包 ✅" : "缺失 ❌")
                InfoRow("已安装源", "\(store.scripts.count) 个 / 启用 \(store.enabledSources.count) 个")
            }

            Section("网络连通性") {
                InfoRow("Apple 测试流", networkResult)
                Button {
                    Task { await testNetwork() }
                } label: {
                    Label(testing ? "测试中…" : "测试网络（HEAD 请求）", systemImage: "wifi")
                }
            }

            Section("源自检（运行 home()）") {
                if store.enabledSources.isEmpty {
                    Text("没有启用的源").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(store.enabledSources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(source.name).font(.subheadline)
                            Spacer()
                            Button(testingSource == source.id ? "测试中…" : "测试") {
                                Task { await testSource(source) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        if let result = sourceTestResult[source.id] {
                            Text(result).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("日志（最近 \(log.entries.count) 条）") {
                if log.entries.isEmpty {
                    Text("暂无日志：脚本 console.log、播放错误都会出现在这里")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(log.entries.suffix(40)) { entry in
                    Text("[\(entry.source)] \(entry.text)")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("复制全部日志") {
                    UIPasteboard.general.string = log.dump
                }
                Button("清空日志", role: .destructive) {
                    log.clear()
                }
            }
        }
        .navigationTitle("自检")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            bundleDemoJS = Bundle.main.url(forResource: "demo", withExtension: "js") != nil
            bundleDemoM3U = Bundle.main.url(forResource: "demo", withExtension: "m3u") != nil
            LogBus.shared.log("自检页打开：demo.js=\(bundleDemoJS) demo.m3u=\(bundleDemoM3U) 源=\(store.scripts.count)", source: "diag")
        }
    }

    private func testNetwork() async {
        testing = true
        do {
            let data = try await HTTP.request("https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")
            networkResult = "连通（\(data.count) 字节）"
            LogBus.shared.log("网络测试通过：\(data.count) 字节", source: "diag")
        } catch {
            networkResult = "失败：\(error.localizedDescription)"
            LogBus.shared.log("网络测试失败：\(error.localizedDescription)", source: "diag")
        }
        testing = false
    }

    private func testSource(_ source: ScriptSource) async {
        testingSource = source.id
        do {
            let sections = try await ScriptService.shared.home(source)
            sourceTestResult[source.id] = sections.isEmpty
                ? "home() 成功但没有栏目"
                : "home() 成功：\(sections.count) 个栏目，共 \(sections.reduce(0) { $0 + $1.items.count }) 个条目"
        } catch {
            sourceTestResult[source.id] = "失败：\(error.localizedDescription)"
        }
        testingSource = nil
    }
}
