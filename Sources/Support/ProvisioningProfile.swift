import Foundation

/// 读取并解析 App 包内嵌的 embedded.mobileprovision
struct ProvisioningProfile {
    let name: String
    let appID: String
    let teamIdentifier: String
    let creationDate: Date?
    let expirationDate: Date?
    let platforms: [String]
    let provisionedDeviceCount: Int
    let entitlementCount: Int
    let provisionsAllDevices: Bool

    var type: String {
        if provisionsAllDevices { return "企业证书（全设备分发）" }
        if provisionedDeviceCount > 0 { return "开发 / Ad Hoc（含设备 UDID 列表）" }
        return "App Store 或未知类型"
    }

    var remainingText: String {
        guard let expirationDate else { return "-" }
        let seconds = expirationDate.timeIntervalSinceNow
        if seconds <= 0 { return "已过期，需要重新签名" }
        let days = Int(seconds / 86400)
        let hours = Int(seconds.truncatingRemainder(dividingBy: 86400) / 3600)
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        return "\(hours) 小时"
    }

    static func embedded() -> ProvisioningProfile? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<plist"),
              let end = raw.range(of: "</plist>") else { return nil }

        let xml = String(raw[start.lowerBound..<end.upperBound])
        guard let xmlData = xml.data(using: .utf8),
              let object = try? PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil),
              let dict = object as? [String: Any] else { return nil }

        let entitlements = dict["Entitlements"] as? [String: Any] ?? [:]

        return ProvisioningProfile(
            name: dict["Name"] as? String ?? "未命名描述文件",
            appID: entitlements["application-identifier"] as? String ?? "-",
            teamIdentifier: (dict["TeamIdentifier"] as? [String])?.first ?? "-",
            creationDate: dict["CreationDate"] as? Date,
            expirationDate: dict["ExpirationDate"] as? Date,
            platforms: dict["Platform"] as? [String] ?? [],
            provisionedDeviceCount: (dict["ProvisionedDevices"] as? [String])?.count ?? 0,
            entitlementCount: entitlements.count,
            provisionsAllDevices: dict["ProvisionsAllDevices"] as? Bool ?? false
        )
    }
}
