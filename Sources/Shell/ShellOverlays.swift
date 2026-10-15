import SwiftUI
import UIKit

/// 品牌闪屏，对应 Android 的 `ImageView(R.drawable.splash_brand)`：
/// `#22242A` 背景 + 满屏铺开 + 220ms 淡出。
///
/// 与 Android 的差别（也是修掉的观感问题）：`CENTER_CROP` 直接铺满时，素材里的
/// logo 簇（标 + 标题）本身位于约 47% 高度、47.8% 宽度，在长屏手机上会显得偏上偏左。
/// 这里读出 `splash_anchor.json` 里实测的簇中心，按锚点把图精确居中：
/// 先按 cover 缩放并额外放大一点腾出可平移余量，再平移 `(0.5 - 锚点) * 屏幕尺寸`，
/// 平移量夹在余量内，因此任何屏幕比例下都不会露边。
struct SplashOverlay: View {
    var alpha: Double

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color(uiColor: AppConfig.chromeColor)
                if let image = SplashArtwork.image, size.width > 1, size.height > 1 {
                    let source = image.size
                    let deltaX = 0.5 - SplashArtwork.anchor.x
                    let deltaY = 0.5 - SplashArtwork.anchor.y
                    // 放大系数：留出足够平移余量，同时避免明显放大
                    let zoom = 1 + max(abs(deltaX) * 2.4, abs(deltaY) * 2.4)
                    let scale = max(size.width / source.width, size.height / source.height) * zoom
                    let rendered = CGSize(width: source.width * scale, height: source.height * scale)
                    let slackX = max(0, (rendered.width - size.width) / 2)
                    let slackY = max(0, (rendered.height - size.height) / 2)
                    let offsetX = min(max(deltaX * size.width, -slackX), slackX)
                    let offsetY = min(max(deltaY * size.height, -slackY), slackY)

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rendered.width, height: rendered.height)
                        .offset(x: offsetX, y: offsetY)
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
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .opacity(alpha)
        .allowsHitTesting(false)
    }
}

enum SplashArtwork {

    struct Anchor {
        /// 素材里 logo 簇中心的纵向比例（缺 JSON 时按本素材实测值兜底）
        var y: CGFloat = 0.4702
        /// 横向比例
        var x: CGFloat = 0.4778
        var detected: Bool = false
    }

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

    /// 锚点由 `scripts/make_assets.py` 量测并写入 `Resources/splash_anchor.json`。
    static let anchor: Anchor = {
        guard let url = Bundle.main.url(forResource: "splash_anchor", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return Anchor()
        }
        var anchor = Anchor()
        if let y = object["contentCenterY"] as? Double { anchor.y = CGFloat(y) }
        if let x = object["contentCenterX"] as? Double { anchor.x = CGFloat(x) }
        anchor.detected = (object["detected"] as? Bool) ?? false
        return anchor
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
