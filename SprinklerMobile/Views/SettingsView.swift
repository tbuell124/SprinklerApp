import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ConnectivityStore
    @FocusState private var isURLFieldFocused: Bool
    @StateObject private var discoveryViewModel = DiscoveryViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Sprinkler Controller") {
                    TextField("http://sprinkler.local:8000", text: $store.baseURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .focused($isURLFieldFocused)

                    Button(action: runHealthCheck) {
                        if store.isChecking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Test Connection")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTestButtonDisabled)

                    ConnectivityBadgeView(state: store.state, isLoading: store.isChecking)
                        .accessibilityLabel(accessibilityLabel)
                        .padding(.vertical, 4)

                    if case let .offline(error?) = store.state {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Connection error: \(error)")
                    }
                }

                discoverySection

                Section("Tips") {
                    Text("Enter the Raspberry Pi's base URL once, then tap Test Connection to verify the sprinkler controller is reachable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                discoveryViewModel.attach(connectivityStore: store)
                discoveryViewModel.start()
            }
            .onDisappear {
                discoveryViewModel.stop()
            }
        }
    }

    private func runHealthCheck() {
        Task { await store.testConnection() }
    }

    private var isTestButtonDisabled: Bool {
        store.isChecking || store.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var accessibilityLabel: String {
        switch store.state {
        case .connected:
            return "Controller connected"
        case let .offline(description):
            if let description {
                return "Controller offline: \(description)"
            }
            return "Controller offline"
        }
    }

    @ViewBuilder
    private var discoverySection: some View {
        Section {
            if let message = discoveryViewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if discoveryViewModel.devices.isEmpty {
                if discoveryViewModel.isBrowsing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching your network…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if discoveryViewModel.errorMessage == nil {
                    Text("No sprinkler controllers discovered yet. Tap Refresh to search again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(discoveryViewModel.devices) { device in
                Button {
                    isURLFieldFocused = false
                    discoveryViewModel.select(device: device)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name.isEmpty ? "sprinkler" : device.name)
                            .font(.body)
                        let subtitle = deviceSubtitle(for: device)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("Refresh") {
                    isURLFieldFocused = false
                    discoveryViewModel.refresh()
                }
                .disabled(discoveryViewModel.isBrowsing)
            }
        } header: {
            HStack {
                Text("Discovered Devices")
                Spacer()
                if discoveryViewModel.isBrowsing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func deviceSubtitle(for device: DiscoveredDevice) -> String {
        let endpoint = device.host ?? device.ip ?? "—"
        return "\(endpoint):\(device.port)"
    }
}
