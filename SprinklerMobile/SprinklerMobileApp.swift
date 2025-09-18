import SwiftUI

@main
struct SprinklerMobileApp: App {
    @StateObject private var connectivityStore = ConnectivityStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connectivityStore)
        }
    }
}

private struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "speedometer")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
