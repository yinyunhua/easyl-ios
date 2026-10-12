import Foundation

/// 全局设置（UserDefaults 持久化，和原版 Easyl 的 UA/Cookie/Referer 全局项对应）
enum AppSettings {
    private static let defaults = UserDefaults.standard

    static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static var userAgent: String {
        get { defaults.string(forKey: "net.ua") ?? defaultUserAgent }
        set { defaults.set(newValue, forKey: "net.ua") }
    }

    static var referer: String {
        get { defaults.string(forKey: "net.referer") ?? "" }
        set { defaults.set(newValue, forKey: "net.referer") }
    }

    static var cookie: String {
        get { defaults.string(forKey: "net.cookie") ?? "" }
        set { defaults.set(newValue, forKey: "net.cookie") }
    }

    static var timeout: Double {
        get { defaults.object(forKey: "net.timeout") as? Double ?? 15 }
        set { defaults.set(newValue, forKey: "net.timeout") }
    }

    static var defaultSpeed: Double {
        get { defaults.object(forKey: "play.speed") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "play.speed") }
    }

    static var autoPlayNext: Bool {
        get { defaults.object(forKey: "play.autoNext") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "play.autoNext") }
    }

    static var defaultDanmakuOn: Bool {
        get { defaults.object(forKey: "danmaku.on") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "danmaku.on") }
    }

    static var danmakuFontSize: Double {
        get { defaults.object(forKey: "danmaku.size") as? Double ?? 15 }
        set { defaults.set(newValue, forKey: "danmaku.size") }
    }

    static var danmakuOpacity: Double {
        get { defaults.object(forKey: "danmaku.opacity") as? Double ?? 0.9 }
        set { defaults.set(newValue, forKey: "danmaku.opacity") }
    }

    static var danmakuSpeed: Double {
        get { defaults.object(forKey: "danmaku.speed") as? Double ?? 8 }
        set { defaults.set(newValue, forKey: "danmaku.speed") }
    }

    /// 直播源列表（m3u / m3u8 地址或本地文件名）
    static var liveSources: [String] {
        get { defaults.stringArray(forKey: "live.sources") ?? [] }
        set { defaults.set(newValue, forKey: "live.sources") }
    }
}
