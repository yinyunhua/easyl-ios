import Foundation
import UIKit

/// 对应 MainActivity.isEmulator()：判断当前是否跑在模拟器上。
/// Android 端用途：模拟器 / 部分机型上关闭硬件加速图层（`setLayerType`）。
/// iOS 端用途：模拟器上 WKWebView 视频解码受限，同样降级渲染策略。
enum EnvProbe {

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// 硬件加速是否可用（Android: WebView 硬件层；iOS: WebContent GPU 进程）。
    static var supportsHardwareLayer: Bool { !isSimulator }

    /// 设备指纹摘要，用于诊断页与 H5 侧透传（等价 Android Build.FINGERPRINT 等字段）。
    @MainActor
    static var deviceFingerprint: String {
        let d = UIDevice.current
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return "\(d.systemName) \(d.systemVersion)|\(machine)|\(d.model)|\(d.name)"
    }
}
