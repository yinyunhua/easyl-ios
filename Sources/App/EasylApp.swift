import SwiftUI

@main
struct EasylApp: App {
    @StateObject private var store = SourceStore()
    @StateObject private var downloads = DownloadManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(downloads)
                .preferredColorScheme(nil)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }

            LiveView()
                .tabItem { Label("直播", systemImage: "antenna.radiowaves.left.and.right") }

            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            DownloadsView()
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
