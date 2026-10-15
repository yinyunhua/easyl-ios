import SwiftUI
import UIKit

/// 品牌闪屏，对应 Android 的 `ImageView(R.drawable.splash_brand)`：
/// `CENTER_CROP` 铺满 + `#22242A` 背景 + 220ms 淡出。
struct SplashOverlay: View {
    var alpha: Double

    var body: some View {
        ZStack {
            Color(uiColor: AppConfig.chromeColor)
                .ignoresSafeArea()
            if let image = SplashArtwork.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Text(AppConfig.displayName)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Color(uiColor: AppConfig.accentColor))
                    Text("v\(AppConfig.appVersion)")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .opacity(alpha)
        .allowsHitTesting(false)
    }
}

enum SplashArtwork {
    /// 由 APK 的 `res/drawable-nodpi/splash_brand.webp` 转换而来（scripts/make_assets.py）。
    static let image: UIImage? = {
        if let url = Bundle.main.url(forResource: "splash_brand", withExtension: "png"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        if let url = Bundle.main.url(forResource: "splash_brand", withExtension: "webp"),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }()
}

/// 连接中状态，对应 Android 的 `ProgressBar + TextView("正在连接…")`。
struct LoadingOverlay: View {
    var progress: Double
    var text: String = AppConfig.Text.connecting

    var body: some View {
        VStack(spacing: 18) {
            ProgressView(value: progress > 0 ? progress : nil)
                .progressViewStyle(.linear)
                .tint(Color(uiColor: AppConfig.accentColor))
                .frame(width: 160)
                .opacity(progress > 0 ? 1 : 0)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color(uiColor: AppConfig.accentColor))
                .opacity(progress > 0 ? 0 : 1)
            Text(text)
                .font(.system(size: 17))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: AppConfig.chromeColor).ignoresSafeArea())
        .allowsHitTesting(false)
    }
}

/// 失败态，对应 `status.setText("无法连接APP，点此重试")` + 点击重新 `bootstrap()`。
struct RetryOverlay: View {
    var text: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(Color(uiColor: AppConfig.accentColor))
            Button(action: onRetry) {
                Text(text)
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: AppConfig.chromeColor).ignoresSafeArea())
    }
}

/// 轻提示，对应 Android `Toast`。
struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.82))
            .clipShape(Capsule())
            .transition(.opacity)
    }
}

/// 悬浮返回键：对应 Android 物理返回键（`handleNativeBack`）。
struct ShellBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.45))
                .clipShape(Circle())
        }
        .accessibilityLabel("返回")
    }
}
