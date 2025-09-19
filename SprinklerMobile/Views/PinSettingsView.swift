import SwiftUI

/// Dedicated management screen for renaming, activating, and reordering sprinkler pins.
struct PinSettingsView: View {
    @EnvironmentObject private var store: SprinklerStore
    @State private var nameDrafts: [Int: String] = [:]
    @State private var pinPendingDisable: PinDTO?
    @State private var lastFocusedPin: Int?
    @State private var showDisableConfirmation = false
    @FocusState private var focusedField: Int?

    private var pins: [PinDTO] {
        store.pins
    }

    var body: some View {
        Form {
            Section("Pins") {
                if pins.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Pins Available")
                            .font(.headline)
                        Text("Connect to the controller and refresh to load available GPIO pins.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(pins) { pin in
                        pinRow(for: pin)
                    }
                    .onMove { offsets, destination in
                        store.reorderPins(from: offsets, to: destination)
                    }
                }
            } footer: {
                Text("Disabled pins will disappear from the dashboard and from schedule editors.")
            }
        }
        .navigationTitle("Pin Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { syncDrafts(force: true) }
        .onChange(of: store.pins) { _ in syncDrafts(force: false) }
        .onChange(of: focusedField) { newFocus in
            if let lastFocusedPin, lastFocusedPin != newFocus {
                persistDraft(for: lastFocusedPin)
            }
            lastFocusedPin = newFocus
        }
        .onDisappear { commitAllDrafts() }
        .alert("Disable pin?", isPresented: $showDisableConfirmation, presenting: pinPendingDisable) { pin in
            Button("Disable", role: .destructive) {
                store.setPinEnabled(pin, isEnabled: false)
                pinPendingDisable = nil
            }
            Button("Cancel", role: .cancel) {
                pinPendingDisable = nil
            }
        } message: { pin in
            Text("\(pin.displayName) will no longer appear on the dashboard or in schedules.")
        }
    }

    private func pinRow(for pin: PinDTO) -> some View {
        let nameBinding = Binding<String>(
            get: { nameDrafts[pin.id] ?? pin.name ?? "" },
            set: { newValue in nameDrafts[pin.id] = newValue }
        )

        let enabledBinding = Binding<Bool>(
            get: { pin.isEnabled ?? true },
            set: { newValue in
                guard let currentPin = store.pins.first(where: { $0.id == pin.id }) else { return }
                persistDraft(for: pin.id)
                if newValue {
                    store.setPinEnabled(currentPin, isEnabled: true)
                } else {
                    pinPendingDisable = currentPin
                    showDisableConfirmation = true
                }
            }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Zone name", text: nameBinding)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($focusedField, equals: pin.id)
                        .onSubmit { persistDraft(for: pin.id) }
                        .accessibilityLabel("Name for GPIO \(pin.pin)")
                        .accessibilityHint("Enter a friendly name for this sprinkler zone.")

                    Text("GPIO \(pin.pin)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: enabledBinding) {
                    Text("Active")
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Active state for \(pin.displayName)")
                .accessibilityHint("Deactivate to hide this pin from the dashboard and schedules.")
            }
        }
        .padding(.vertical, 6)
    }

    private func syncDrafts(force: Bool) {
        var updatedDrafts = nameDrafts
        for pin in store.pins {
            if force || updatedDrafts[pin.id] == nil || focusedField != pin.id {
                updatedDrafts[pin.id] = pin.name ?? ""
            }
        }
        nameDrafts = updatedDrafts
    }

    private func persistDraft(for pinID: Int) {
        guard let pin = store.pins.first(where: { $0.id == pinID }) else { return }
        let draft = nameDrafts[pinID] ?? ""
        store.renamePin(pin, newName: draft)
    }

    private func commitAllDrafts() {
        for pin in store.pins {
            persistDraft(for: pin.id)
        }
    }
}
