import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    private var toastBinding: Binding<ToastState?> {
        Binding(get: { appState.toast }, set: { appState.toast = $0 })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    connectionBanner
                }
                PinsListView(pins: appState.pins,
                             isLoading: appState.isRefreshing && appState.pins.isEmpty,
                             onToggle: { pin, newValue in appState.togglePin(pin, to: newValue) },
                             onReorder: appState.reorderPins)
                Section("Rain Delay") {
                    RainCardView(rain: appState.rain,
                                 isLoading: appState.isRefreshing && appState.rain == nil) { isActive, hours in
                        appState.setRain(active: isActive, durationHours: hours)
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dashboard")
            .toolbar { EditButton() }
            .refreshable {
                await appState.refresh()
            }
        }
        .toast(state: toastBinding)
    }

    private var connectionBanner: some View {
        HStack {
            Image(systemName: appState.connectionStatus.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(appState.connectionStatus.isReachable ? .green : .orange)
            VStack(alignment: .leading) {
                Text(appState.connectionStatus.bannerText)
                    .font(.headline)
                if let last = appState.settings.lastSuccessfulConnection {
                    Text("Last Connected: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let version = appState.settings.serverVersion {
                    Text("Server Version: \(version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if case let .unreachable(message) = appState.connectionStatus {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
