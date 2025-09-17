import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SprinklerStore

    private var toastBinding: Binding<ToastState?> {
        Binding(get: { store.toast }, set: { store.toast = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target IP") {
                    TextField("http://192.168.1.50:5000", text: $store.targetAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                    if let error = store.validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await store.saveAndTestTarget() }
                    } label: {
                        if store.isTestingConnection {
                            ProgressView()
                        } else {
                            Text("Save & Test")
                        }
                    }
                    .disabled(store.targetAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isTestingConnection)
                }

                Section("Connection") {
                    if let last = store.lastSuccessfulConnection {
                        LabeledContent("Last Success") {
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if let version = store.serverVersion {
                        LabeledContent("Server Version") {
                            Text(version)
                        }
                    }
                    if let failure = store.lastFailure {
                        LabeledContent("Last Error") {
                            Text(failure.localizedDescription)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("About") {
                    Text("All commands are issued directly to the Raspberry Pi via its existing HTTP API. The server is never modified by the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .toast(state: toastBinding)
    }
}
