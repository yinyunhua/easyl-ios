import Foundation
import UIKit

/// 原生方向控制（iOS 16+ 用 `UIWindowScene.requestGeometryUpdate`）。
///
/// 背景：H5 播放页在 Android 端靠 WebChromeClient 的 `onShowCustomView` 全屏 + 系统旋转；
/// iOS 上 `screen.orientation.lock()` 不被支持，所以「横屏」必须由外壳提供：
///  - 播放页点外壳的旋转键 → 优先进原生全屏播放（WKWebView 的 `webkitEnterFullscreen`），
///    没有 video 元素时退化为锁定横屏；
///  - 离开播放页自动恢复竖屏。
///
/// `mask` 用锁保护，供 `application(_:supportedInterfaceOrientationsFor:)` 从任意线程读取。
final class AppOrientation: @unchecked Sendable {

    static let shared = AppOrientation()

    private let lock = NSLock()
    private var storedMask: UIInterfaceOrientationMask = .allButUpsideDown

    private init() {}

    var mask: UIInterfaceOrientationMask {
        lock.lock()
        defer { lock.unlock() }
        return storedMask
    }

    /// 是否处于「锁定横屏 / 播放态」
    private(set) var isLandscapeForced: Bool = false

    @MainActor
    func lockLandscape() {
        store(.landscape)
        isLandscapeForced = true
        apply(.landscape)
    }

    @MainActor
    func lockPortrait() {
        store(.portrait)
        isLandscapeForced = false
        apply(.portrait)
    }

    /// 恢复系统默认（竖屏为主，允许横屏）
    @MainActor
    func unlock() {
        store(.allButUpsideDown)
        isLandscapeForced = false
        apply(.allButUpsideDown)
    }

    private func store(_ value: UIInterfaceOrientationMask) {
        lock.lock()
        storedMask = value
        lock.unlock()
    }

    @MainActor
    private func apply(_ value: UIInterfaceOrientationMask) {
        guard let scene = Self.activeScene() else {
            HGLog.w("Orientation", "no active window scene")
            return
        }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: value)) { error in
            HGLog.w("Orientation", "requestGeometryUpdate failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
