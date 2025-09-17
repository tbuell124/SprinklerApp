import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: SprinklerStore

    private var toastBinding: Binding<ToastState?> {
        Binding(get: { store.toast }, set: { store.toast = $0 })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    connectionBanner
                }
                PinsListView(pins: store.activePins,
                             totalPinCount: store.pins.count,
                             isLoading: store.isRefreshing && store.pins.isEmpty,
                             onToggle: { pin, newValue in store.togglePin(pin, to: newValue) },
                             onReorder: store.reorderPins)
                Section("Rain Delay") {
                    RainCardView(rain: store.rain,
                                 isLoading: store.isRefreshing && store.rain == nil) { isActive, hours in
                        store.setRain(active: isActive, durationHours: hours)
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dashboard")
            .toolbar { EditButton() }
            .refreshable {
                await store.refresh()
            }
        }
        .toast(state: toastBinding)
    }

    private var connectionBanner: some View {
        HStack {
            Image(systemName: store.connectionStatus.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(store.connectionStatus.isReachable ? .green : .orange)
            VStack(alignment: .leading) {
                Text(store.connectionStatus.bannerText)
                    .font(.headline)
                if let last = store.lastSuccessfulConnection {
                    Text("Last Connected: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let version = store.serverVersion {
                    Text("Server Version: \(version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if case let .unreachable(message) = store.connectionStatus {
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
