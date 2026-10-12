import SwiftUI

struct SourceListView: View {
    @EnvironmentObject private var store: SourceStore

    @State private var showAdd = false
    @State private var input = ""
    @State private var showCode = false

    var body: some View {
        List {
            Section {
                ForEach(store.scripts) { source in
                    NavigationLink {
                        SourceDetailView(source: source)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(source.name).font(.subheadline)
                                if !source.enabled {
                                    Text("已停用")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.secondary.opacity(0.2), in: Capsule())
                                }
                            }
                            Text("\(source.id) · \(source.code.count) 字符 · \(source.location == "local" ? "本地" : "远程")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.remove(source)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            store.toggle(source)
                        } label: {
                            Label(source.enabled ? "停用" : "启用", systemImage: "power")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                Text("已导入的源")
            } footer: {
                Text("脚本接口：home / search / detail / play / danmaku，运行时提供 req、post、console、cache、local、kits（md5、sha1、aes 等）。详细协议见 README。")
            }

            if store.scripts.isEmpty {
                Section {
                    Text("暂无源。点右上角 + 导入远程 JS 地址，或直接粘贴脚本内容。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("源管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("导入源脚本", isPresented: $showAdd) {
            TextField("https://... 或粘贴脚本正文", text: $input, axis: .vertical)
                .lineLimit(3...8)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(store.isImporting ? "导入中…" : "导入") {
                let text = input
                input = ""
                Task {
                    let lines = text
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    // 一次粘贴多行 URL = 批量导入（多仓订阅）
                    if lines.count > 1 && lines.allSatisfy({ $0.hasPrefix("http") }) {
                        for line in lines {
                            _ = await store.importScript(from: line)
                        }
                    } else {
                        _ = await store.importScript(from: text)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("提示", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.message ?? "")
        }
    }
}

struct SourceDetailView: View {
    @EnvironmentObject private var store: SourceStore

    @State var source: ScriptSource
    @State private var testOutput = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $source.name)
                if !source.isRemote {
                    Text("本地脚本（\(source.code.count) 字符）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Toggle("启用", isOn: $source.enabled)
            }

            Section("独立请求头（可选）") {
                TextField("User-Agent", text: Binding(get: { source.userAgent ?? "" }, set: { source.userAgent = $0 }))
                    .font(.footnote)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Referer", text: Binding(get: { source.referer ?? "" }, set: { source.referer = $0 }))
                    .font(.footnote)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Cookie", text: Binding(get: { source.cookie ?? "" }, set: { source.cookie = $0 }))
                    .font(.footnote)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("调试") {
                Button {
                    Task { await runTest() }
                } label: {
                    Label(testing ? "正在测试…" : "运行 home() 测试", systemImage: "play.circle")
                }
                if !testOutput.isEmpty {
                    Text(testOutput).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("脚本内容") {
                Text(String(source.code.prefix(4000)) + (source.code.count > 4000 ? "\n…（截断显示）" : ""))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section {
                Button("删除该源", role: .destructive) {
                    store.remove(source)
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            store.upsert(source)
        }
    }

    private func runTest() async {
        testing = true
        testOutput = ""
        store.upsert(source)
        do {
            let sections = try await ScriptService.shared.home(source)
            testOutput = sections.isEmpty
                ? "执行成功，但没有返回栏目"
                : "执行成功：\(sections.count) 个栏目，首个栏目 \(sections[0].items.count) 个条目"
        } catch {
            testOutput = "失败：\(error.localizedDescription)"
        }
        testing = false
    }
}
