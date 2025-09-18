import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ConnectivityStore
    @FocusState private var isURLFieldFocused: Bool

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

                Section("Tips") {
                    Text("Enter the Raspberry Pi's base URL once, then tap Test Connection to verify the sprinkler controller is reachable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
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
}
