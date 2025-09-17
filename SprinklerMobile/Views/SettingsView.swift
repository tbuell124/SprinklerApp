import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    private var toastBinding: Binding<ToastState?> {
        Binding(get: { appState.toast }, set: { appState.toast = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target IP") {
                    TextField("http://192.168.1.50:5000", text: $settings.targetAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                    if let error = settings.validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await appState.saveAndTestTarget() }
                    } label: {
                        if settings.isTestingConnection {
                            ProgressView()
                        } else {
                            Text("Save & Test")
                        }
                    }
                    .disabled(settings.targetAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.isTestingConnection)
                }

                Section("Connection") {
                    if let last = settings.lastSuccessfulConnection {
                        LabeledContent("Last Success") {
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if let version = settings.serverVersion {
                        LabeledContent("Server Version") {
                            Text(version)
                        }
                    }
                    if let failure = settings.lastFailure {
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
