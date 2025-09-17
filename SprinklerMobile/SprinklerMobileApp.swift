import SwiftUI

@main
struct SprinklerMobileApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var appState: AppState

    init() {
        let settingsStore = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _appState = StateObject(wrappedValue: AppState(settings: settingsStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
                .environmentObject(appState)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "speedometer")
                }
            SchedulesView()
                .tabItem {
                    Label("Schedules", systemImage: "calendar")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            await appState.refresh()
        }
    }
}
