import SwiftUI

@main
struct SprinklerMobileApp: App {
    @StateObject private var store: SprinklerStore

    init() {
        _store = StateObject(wrappedValue: SprinklerStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var store: SprinklerStore

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
            await store.refresh()
        }
    }
}
