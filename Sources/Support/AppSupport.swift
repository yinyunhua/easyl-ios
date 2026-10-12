import SwiftUI
import UIKit

/// 通用信息行，用于设置/详情等页面
struct InfoRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var scripts: URL { ensure(documents.appendingPathComponent("Scripts", isDirectory: true)) }
    static var downloads: URL { ensure(documents.appendingPathComponent("Downloads", isDirectory: true)) }

    static func sourceDir(_ id: String) -> URL {
        ensure(scripts.appendingPathComponent(safeName(id), isDirectory: true))
    }

    static func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// 防止脚本用 ../../ 越权写文件
    static func safeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var out = ""
        for scalar in name.unicodeScalars {
            out.append(allowed.contains(scalar) ? Character(scalar) : "_")
        }
        return out.isEmpty ? "unnamed" : out
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, min(1, value)) * 100)
    }
}

extension UIColor {
    /// 支持 #RGB / #RRGGBB / #AARRGGBB，失败返回 nil
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard let value = UInt64(text, radix: 16) else { return nil }
        switch text.count {
        case 3:
            let r = CGFloat((value >> 8) & 0xF) / 15
            let g = CGFloat((value >> 4) & 0xF) / 15
            let b = CGFloat(value & 0xF) / 15
            self.init(red: r, green: g, blue: b, alpha: 1)
        case 6:
            self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                      green: CGFloat((value >> 8) & 0xFF) / 255,
                      blue: CGFloat(value & 0xFF) / 255,
                      alpha: 1)
        case 8:
            self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                      green: CGFloat((value >> 8) & 0xFF) / 255,
                      blue: CGFloat(value & 0xFF) / 255,
                      alpha: CGFloat((value >> 24) & 0xFF) / 255)
        default:
            return nil
        }
    }
}

extension Color {
    init?(hex: String) {
        guard let uiColor = UIColor(hex: hex) else { return nil }
        self.init(uiColor: uiColor)
    }
}
