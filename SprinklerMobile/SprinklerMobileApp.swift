import SwiftUI

@main
struct SprinklerMobileApp: App {
    @StateObject private var connectivityStore = ConnectivityStore(
        checker: HealthService(authentication: AuthenticationController())
    )
    @StateObject private var sprinklerStore = SprinklerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connectivityStore)
                .environmentObject(sprinklerStore)
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
        .tint(Color.appAccentPrimary)
    }
}
