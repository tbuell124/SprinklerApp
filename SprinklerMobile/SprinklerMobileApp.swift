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
    @EnvironmentObject private var sprinklerStore: SprinklerStore
    @Environment(\.scenePhase) private var scenePhase

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
        .task { sprinklerStore.beginStatusPolling() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                sprinklerStore.beginStatusPolling()
            case .background, .inactive:
                sprinklerStore.endStatusPolling()
            @unknown default:
                sprinklerStore.endStatusPolling()
            }
        }
    }
}
