import SwiftUI
import UIKit

/// 应用入口，对应 Android 的 `com.hg.app.HgApp`(Application) + `MainActivity`。
///
/// `HgApp.onCreate()` → `HgAnalytics.init(context)`：iOS 侧在 `AppDelegate` 中完成同一件事。
@main
struct HgApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 对应 `HgApp.onCreate()` + `MainActivity.onNewIntent/onResume` 的原生入口回调。
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 对应 HgApp.onCreate → HgAnalytics.init(context)
        HgAnalytics.shared.start(remoteBase: nil)
        HGLog.i("HgApp", "didFinishLaunching version=\(AppConfig.appVersion)(\(AppConfig.versionCode))")

        if let url = launchOptions?[.url] as? URL {
            UserDefaults.standard.set(url.absoluteString, forKey: "hg.lastLaunchURL")
            PromoCapture.captureAll(launchURL: url)
        } else {
            PromoCapture.captureAll(launchURL: nil)
        }
        return true
    }

    /// 对应 `MainActivity.onNewIntent` → `PromoBindCapture.captureFromIntent`。
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        UserDefaults.standard.set(url.absoluteString, forKey: "hg.lastLaunchURL")
        PromoCapture.capture(from: url)
        return true
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        UserDefaults.standard.set(url.absoluteString, forKey: "hg.lastLaunchURL")
        PromoCapture.capture(from: url)
        return true
    }

    /// 对应 `MainActivity.onResume` 中的 PromoBindCapture 三连调用。
    func applicationDidBecomeActive(_ application: UIApplication) {
        PromoCapture.captureAll(launchURL: nil)
    }

    /// 外壳自管方向：播放页可锁横屏（H5 在 iOS 上拿不到 orientation.lock）。
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppOrientation.shared.mask
    }
}
