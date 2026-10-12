import Foundation

enum DanmakuMode: String {
    case scroll
    case top
    case bottom

    static func parse(_ value: String?) -> DanmakuMode {
        switch value?.lowercased() {
        case "top", "1": return .top
        case "bottom", "2": return .bottom
        default: return .scroll
        }
    }
}

struct DanmakuComment: Identifiable, Hashable {
    let id = UUID()
    var text: String
    var time: Double          // 相对视频开始的秒数
    var mode: DanmakuMode
    var colorHex: String
    var lane: Int = 0
    var width: CGFloat = 0
}
