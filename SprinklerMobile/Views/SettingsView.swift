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
                        .textContentType(.URL)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(store.validationError == nil ? Color.secondary.opacity(0.2) : .red,
                                              lineWidth: store.validationError == nil ? 0.5 : 1.5)
                        }
                        .accessibilityHint("Enter the sprinkler controller base URL.")
                    if let error = store.validationError {
                        Label {
                            Text(error)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel(Text("Validation error: \(error)"))
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

                Section("Discovered Controllers") {
                    if store.isDiscoveringServices {
                        Label("Searching local network…", systemImage: "dot.radiowaves.left.and.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if store.discoveredServices.isEmpty {
                        Text("No controllers found yet. Ensure the Pi is powered on, connected to the same network, or enter the address manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.discoveredServices) { service in
                            Button {
                                store.useDiscoveredService(service)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.name)
                                        .font(.body)
                                    Text(service.detailDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Pins") {
                    if store.pins.isEmpty {
                        Text("No Pins Available")
                            .foregroundStyle(.secondary)
                    } else {
                        PinsTableHeader()
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 2, trailing: 0))
                        ForEach(store.pins, id: \.id) { pin in
                            PinSettingsRow(pin: pin,
                                           onRename: { updatedPin, newName in
                                               store.renamePin(updatedPin, newName: newName)
                                           },
                                           onToggleActive: { updatedPin, isActive in
                                               store.setPinEnabled(updatedPin, isEnabled: isActive)
                                           })
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        }
                    }
                }

                Section("Rain Delay Automation") {
                    TextField("ZIP Code", text: $store.rainSettingsZip)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    TextField("Threshold (%)", text: $store.rainSettingsThreshold)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    Toggle("Enable Automation", isOn: $store.rainSettingsIsEnabled)

                    if let chance = store.rain?.chancePercent {
                        LabeledContent("Current Chance of Rain") {
                            Text("\(chance)%")
                                .font(.subheadline)
                        }
                    } else {
                        Text("Chance of rain will populate after saving a ZIP code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await store.saveRainSettings() }
                    } label: {
                        if store.isSavingRainSettings {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save Rain Settings")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(store.isSavingRainSettings)
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
        .onAppear { store.beginBonjourDiscovery() }
        .onDisappear { store.endBonjourDiscovery() }
    }
}

private struct PinsTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("GPIO")
                .frame(width: 60, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Enabled")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

private struct PinSettingsRow: View {
    let pin: PinDTO
    let onRename: (PinDTO, String) -> Void
    let onToggleActive: (PinDTO, Bool) -> Void

    @State private var name: String
    @State private var isEnabled: Bool
    @FocusState private var isFocused: Bool

    init(pin: PinDTO,
         onRename: @escaping (PinDTO, String) -> Void,
         onToggleActive: @escaping (PinDTO, Bool) -> Void) {
        self.pin = pin
        self.onRename = onRename
        self.onToggleActive = onToggleActive
        _name = State(initialValue: pin.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        _isEnabled = State(initialValue: pin.isEnabled ?? true)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(pin.pin)")
                .frame(width: 60, alignment: .leading)
                .font(.subheadline)

            TextField("", text: $name, prompt: Text(pin.displayName))
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(commitRename)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: isEnabled) { newValue in
                    onToggleActive(pin, newValue)
                }
                .frame(width: 80, alignment: .trailing)
        }
        .controlSize(.small)
        .padding(.vertical, 4)
        .onChange(of: pin) { updatedPin in
            let trimmed = updatedPin.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed != name {
                name = trimmed
            }
            let enabled = updatedPin.isEnabled ?? true
            if enabled != isEnabled {
                isEnabled = enabled
            }
        }
        .onChange(of: isFocused) { focused in
            if !focused {
                commitRename()
            }
        }
    }

    private func commitRename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = pin.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed != current else { return }
        onRename(pin, trimmed)
    }
}
