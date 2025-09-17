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

                Section("Pins") {
                    if store.pins.isEmpty {
                        Text("No Pins Available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.pins.enumerated()), id: \.element.id) { index, pin in
                            PinSettingsRow(pin: pin,
                                           position: index + 1) { updatedPin, newName in
                                store.renamePin(updatedPin, newName: newName)
                            }
                        }
                    }
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

private struct PinSettingsRow: View {
    let pin: PinDTO
    let position: Int
    let onRename: (PinDTO, String) -> Void

    @State private var name: String
    @FocusState private var isFocused: Bool

    init(pin: PinDTO, position: Int, onRename: @escaping (PinDTO, String) -> Void) {
        self.pin = pin
        self.position = position
        self.onRename = onRename
        _name = State(initialValue: pin.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GPIO \(pin.pin)")
                    .font(.subheadline)
                Spacer()
                Text("Pin #\(position)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $name, prompt: Text(pin.displayName))
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(commitRename)
        }
        .onChange(of: pin) { updatedPin in
            let trimmed = updatedPin.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed != name {
                name = trimmed
            }
        }
        .onChange(of: isFocused) { focused in
            if !focused {
                commitRename()
            }
        }
        .padding(.vertical, 4)
    }

    private func commitRename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = pin.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed != current else { return }
        onRename(pin, trimmed)
    }
}
