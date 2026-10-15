import Foundation

/// 对应 `com.hg.app.PromoBindStore`：把渠道绑定 token 落到 `hg_promo_bind` 容器（key = `bind_token`）。
///
/// Android 用 SharedPreferences("hg_promo_bind")；iOS 用同一名字的 UserDefaults suite，
/// 语义一致：同 key 覆盖写、读空返回空串、不写空值。
struct PromoBindStore {

    static let prefsName = AppConfig.promoPrefsName
    static let tokenKey = AppConfig.promoTokenKey

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: prefsName) ?? .standard
    }

    /// 对应 `PromoBindStore.get(context)`：没有则返回空串。
    static func token() -> String {
        let value = defaults.string(forKey: tokenKey) ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 对应 `PromoBindStore.save(context, token)`：空值不写。
    @discardableResult
    static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed != self.token() else { return false }
        defaults.set(trimmed, forKey: tokenKey)
        defaults.synchronize()
        HGLog.i("PromoBindStore", "bind_token saved: \(trimmed)")
        NotificationCenter.default.post(name: .hgPromoBindUpdated, object: trimmed)
        return true
    }

    static func clear() {
        defaults.removeObject(forKey: tokenKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: .hgPromoBindUpdated, object: "")
    }
}

extension Notification.Name {
    static let hgPromoBindUpdated = Notification.Name("hg.promo.bind.updated")
}
