import SwiftUI

/// 手动输入任意 HLS / MP4 地址直接播放，用于在不依赖源脚本的情况下验证播放链路
struct DirectPlayView: View {
    struct Target: Identifiable {
        let id = UUID()
        let url: String
    }

    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var playing: Target?

    private static let samples: [(String, String)] = [
        ("Apple BipBop（HLS 测试流）", "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"),
        ("Mux 测试流（HLS）", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"),
        ("Big Buck Bunny（MP4 直链）", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("播放地址") {
                    TextField("https://example.com/video.m3u8 或 .mp4", text: $url, axis: .vertical)
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Button {
                        play()
                    } label: {
                        Label("播放这个地址", systemImage: "play.fill")
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("测试地址（点一下直接播）") {
                    ForEach(Self.samples, id: \.1) { sample in
                        Button {
                            url = sample.1
                            play()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sample.0).font(.subheadline)
                                Text(sample.1).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Text("提示：播放链路 = AVPlayer 直连网络流。若测试地址能播、而源脚本点进去播不了，问题在源脚本返回的 url/headers 上。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("链接播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .fullScreenCover(item: $playing) { target in
                PlayerView(urlString: target.url, title: "链接播放", source: nil, danmakuId: nil)
            }
        }
    }

    private func play() {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        LogBus.shared.log("直接播放: \(trimmed)", source: "player")
        playing = Target(url: trimmed)
    }
}
