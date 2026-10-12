import SwiftUI

/// 自签用户最实用的一页：读 embedded.mobileprovision，显示证书到期与倒计时
struct SignatureView: View {
    @State private var profile: ProvisioningProfile?

    var body: some View {
        List {
            Section("App") {
                InfoRow("Bundle ID", Bundle.main.bundleIdentifier ?? "-")
                InfoRow("版本", "\(version) (\(build))")
                InfoRow("最低系统", minOS)
            }

            if let profile {
                Section("描述文件") {
                    InfoRow("名称", profile.name)
                    InfoRow("类型", profile.type)
                    InfoRow("Team ID", profile.teamIdentifier)
                    InfoRow("App ID", profile.appID)
                    InfoRow("Entitlements", "\(profile.entitlementCount) 项")
                }
                Section("有效期") {
                    InfoRow("签发时间", dateText(profile.creationDate))
                    InfoRow("到期时间", dateText(profile.expirationDate))
                    InfoRow("剩余", profile.remainingText)
                }
            } else {
                Section("描述文件") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("未检测到 embedded.mobileprovision", systemImage: "checkmark.seal")
                            .font(.subheadline)
                        Text("未签名的包、App Store 安装的包都不会内嵌描述文件。用 Sideloadly / ESign 等工具签名安装后，这里会显示证书到期时间与剩余天数。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("自签提示") {
                Text("免费 Apple ID 签名的描述文件 7 天后失效：App 图标还在但打不开，用同一 Bundle ID 覆盖安装即可恢复，本地数据不会丢。付费开发者账号为 1 年。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("签名状态")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profile = ProvisioningProfile.embedded() }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var minOS: String {
        Bundle.main.object(forInfoDictionaryKey: "MinimumOSVersion") as? String ?? "-"
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
