import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: SourceStore
    @EnvironmentObject private var downloads: DownloadManager

    @State private var ua = AppSettings.userAgent
    @State private var referer = AppSettings.referer
    @State private var cookie = AppSettings.cookie
    @State private var timeout = AppSettings.timeout
    @State private var speed = AppSettings.defaultSpeed
    @State private var autoNext = AppSettings.autoPlayNext
    @State private var danmakuDefault = AppSettings.defaultDanmakuOn
    @State private var danmakuSize = AppSettings.danmakuFontSize
    @State private var danmakuOpacity = AppSettings.danmakuOpacity
    @State private var danmakuSpeed = AppSettings.danmakuSpeed
    @State private var liveSources = AppSettings.liveSources
    @State private var newLive = ""
    @State private var showAddLive = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("源") {
                    NavigationLink {
                        SourceListView()
                    } label: {
                        Label("源管理（\(store.scripts.count) 个 / 启用 \(store.enabledSources.count) 个）",
                              systemImage: "square.stack.3d.up")
                    }
                }

                Section("播放") {
                    Picker("默认倍速", selection: $speed) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { value in
                            Text(String(format: "%.2fx", value)).tag(value)
                        }
                    }
                    Toggle("自动连播下一集", isOn: $autoNext)
                    Toggle("默认开启弹幕", isOn: $danmakuDefault)

                    HStack {
                        Text("弹幕字号")
                        Slider(value: $danmakuSize, in: 10...24, step: 1)
                        Text("\(Int(danmakuSize))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                    }

                    HStack {
                        Text("弹幕透明度")
                        Slider(value: $danmakuOpacity, in: 0.3...1, step: 0.05)
                    }

                    HStack {
                        Text("弹幕速度")
                        Slider(value: $danmakuSpeed, in: 4...14, step: 1)
                        Text("\(Int(danmakuSpeed))s")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Section {
                    TextField("User-Agent", text: $ua, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.footnote)
                    TextField("Referer", text: $referer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote)
                    TextField("Cookie", text: $cookie, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.footnote)
                    HStack {
                        Text("请求超时")
                        Spacer()
                        Text("\(Int(timeout)) 秒").foregroundStyle(.secondary)
                    }
                    Slider(value: $timeout, in: 5...40, step: 1)
                } header: {
                    Text("网络")
                } footer: {
                    Text("全局请求头；源里单独配置的 UA / Referer / Cookie 优先级更高。")
                }

                Section("直播源") {
                    ForEach(liveSources, id: \.self) { item in
                        Text(item).font(.footnote).lineLimit(1)
                    }
                    .onDelete { indexSet in
                        liveSources.remove(atOffsets: indexSet)
                        AppSettings.liveSources = liveSources
                    }

                    Button {
                        showAddLive = true
                    } label: {
                        Label("添加 m3u 地址", systemImage: "plus")
                    }
                }

                Section("存储") {
                    Button("清理脚本缓存") {
                        clearScriptCache()
                        toast = "脚本缓存已清理"
                    }
                    Button("删除全部下载", role: .destructive) {
                        downloads.removeAll()
                        toast = "下载已清空"
                    }
                    InfoRow("文件目录", "「文件」App → 我的 iPhone → EasylForIOS")
                }

                Section("关于") {
                    InfoRow("版本", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    InfoRow("Bundle ID", Bundle.main.bundleIdentifier ?? "-")
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("自检（资源 / 网络 / 源 / 日志）", systemImage: "stethoscope")
                    }
                    NavigationLink {
                        SignatureView()
                    } label: {
                        Label("签名状态（7 天倒计时）", systemImage: "checkmark.seal")
                    }
                    Button("复制诊断信息") { copyDiagnostics() }
                }
            }
            .navigationTitle("设置")
            .alert("添加 m3u 直播源", isPresented: $showAddLive) {
                TextField("https://example.com/live.m3u", text: $newLive)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("添加") {
                    let text = newLive.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        liveSources.append(text)
                        AppSettings.liveSources = liveSources
                    }
                    newLive = ""
                }
                Button("取消", role: .cancel) {}
            }
            .overlay(alignment: .bottom) {
                if let message = toast {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            toast = nil
                        }
                }
            }
            .onChange(of: speed) { AppSettings.defaultSpeed = $0 }
            .onChange(of: autoNext) { AppSettings.autoPlayNext = $0 }
            .onChange(of: danmakuDefault) { AppSettings.defaultDanmakuOn = $0 }
            .onChange(of: danmakuSize) { AppSettings.danmakuFontSize = $0 }
            .onChange(of: danmakuOpacity) { AppSettings.danmakuOpacity = $0 }
            .onChange(of: danmakuSpeed) { AppSettings.danmakuSpeed = $0 }
            .onChange(of: ua) { AppSettings.userAgent = $0 }
            .onChange(of: referer) { AppSettings.referer = $0 }
            .onChange(of: cookie) { AppSettings.cookie = $0 }
            .onChange(of: timeout) { AppSettings.timeout = $0 }
        }
    }

    private func clearScriptCache() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("easyl.cache.") {
            defaults.removeObject(forKey: key)
        }
    }

    private func copyDiagnostics() {
        let text = """
        Easyl iOS \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "-")
        源: \(store.scripts.map(\.name).joined(separator: " / "))
        启用源: \(store.enabledSources.count)
        UA: \(AppSettings.userAgent)
        """
        UIPasteboard.general.string = text
        toast = "诊断信息已复制"
    }
}
