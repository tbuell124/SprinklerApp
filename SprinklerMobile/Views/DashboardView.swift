import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: ConnectivityStore

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    ConnectivityBadgeView(state: store.state, isLoading: store.isChecking)
                    if case let .offline(error?) = store.state {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dashboard")
            .refreshable {
                await store.refresh()
            }
        }
        .task {
            await store.refresh()
        }
    }
}
