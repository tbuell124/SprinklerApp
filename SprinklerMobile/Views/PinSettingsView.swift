import SwiftUI

/// Dedicated management screen for renaming, activating, and reordering sprinkler pins.
struct PinSettingsView: View {
    @EnvironmentObject private var store: SprinklerStore
    @State private var nameDrafts: [Int: String] = [:]
    @State private var pinPendingDisable: PinDTO?
    @State private var lastFocusedPin: Int?
    @State private var showDisableConfirmation = false
    @FocusState private var focusedField: Int?
    @State private var pinsSyncWorkItem: DispatchWorkItem?

    private var pins: [PinDTO] {
        store.pins
    }

    var body: some View {
        Form { pinsSection }
            .navigationTitle("Pin Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
            .onAppear { syncDrafts(force: true) }
            .onChange(of: store.pins, initial: false) { _, _ in
                pinsSyncWorkItem?.cancel()
                let workItem = DispatchWorkItem { syncDrafts(force: false) }
                pinsSyncWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
            }
            .onChange(of: focusedField, initial: false) { _, newFocus in
                if let lastFocusedPin, lastFocusedPin != newFocus {
                    persistDraft(for: lastFocusedPin)
                }
                lastFocusedPin = newFocus
            }
            .onDisappear {
                pinsSyncWorkItem?.cancel()
                commitAllDrafts()
            }
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

    @ViewBuilder
    private var pinsSection: some View {
        Section {
            if pins.isEmpty {
                PinSettingsEmptyStateView()
            } else {
                let reorderAction: (IndexSet, Int) -> Void = { offsets, destination in
                    store.reorderPins(from: offsets, to: destination)
                }

                ForEach(pins, id: \.id) { pin in
                    pinRow(for: pin)
                }
                .onMove(perform: reorderAction)
            }
        } header: {
            PinSettingsHeaderView(activeCount: activePinCount, totalCount: pins.count)
        } footer: {
            PinSettingsValidationsView()
        }
    }

    @ViewBuilder
    private func pinRow(for pin: PinDTO) -> some View {
        let nameBinding = Binding<String>(
            get: { nameDrafts[pin.id] ?? pin.name ?? "" },
            set: { newValue in nameDrafts[pin.id] = newValue }
        )

        let enabledBinding = Binding<Bool>(
            get: { pin.isEnabled ?? true },
            set: { newValue in handleToggleChange(newValue, for: pin) }
        )

        PinSettingsRowView(
            pin: pin,
            name: nameBinding,
            isEnabled: enabledBinding,
            focusBinding: $focusedField,
            onSubmit: { persistDraft(for: pin.id) }
        )
    }

    private func handleToggleChange(_ newValue: Bool, for pin: PinDTO) {
        guard let currentPin = store.pins.first(where: { $0.id == pin.id }) else { return }
        persistDraft(for: pin.id)
        if newValue {
            store.setPinEnabled(currentPin, isEnabled: true)
        } else {
            pinPendingDisable = currentPin
            showDisableConfirmation = true
        }
    }

    private var activePinCount: Int {
        pins.filter { $0.isEnabled ?? true }.count
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

private struct PinSettingsRowView: View {
    let pin: PinDTO
    let name: Binding<String>
    let isEnabled: Binding<Bool>
    let focusBinding: FocusState<Int?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Zone name", text: name)
                        .pinNameFieldStyle(
                            focusBinding: focusBinding,
                            pinID: pin.id,
                            onSubmit: onSubmit,
                            pinNumber: pin.pin
                        )
                        .id("pin-name-\(pin.id)")

                    PinSettingsCounterText(value: pin.pin)
                }

                PinSettingsToggleView(
                    isEnabled: isEnabled,
                    pinName: pin.displayName
                )
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PinSettingsHeaderView: View {
    let activeCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            PinSettingsIconView(symbolName: "slider.horizontal.3", font: .title2)
            PinSettingsCountersView(activeCount: activeCount, totalCount: totalCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PinSettingsIconView: View {
    let symbolName: String
    let font: Font

    init(symbolName: String = "bolt.horizontal.circle", font: Font = .largeTitle) {
        self.symbolName = symbolName
        self.font = font
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(font)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

private struct PinSettingsCountersView: View {
    let activeCount: Int
    let totalCount: Int

    private var inactiveCount: Int { max(0, totalCount - activeCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Pins")
                .font(.headline)
            Text("\(activeCount) active • \(inactiveCount) inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PinSettingsCounterText: View {
    let value: Int

    var body: some View {
        Text("GPIO \(value)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct PinSettingsToggleView: View {
    let isEnabled: Binding<Bool>
    let pinName: String

    var body: some View {
        Toggle(isOn: isEnabled) {
            Text("Active")
                .font(.subheadline.weight(.semibold))
        }
        .toggleStyle(.switch)
        .accessibilityLabel("Active state for \(pinName)")
        .accessibilityHint("Deactivate to hide this pin from the dashboard and schedules.")
    }
}

private struct PinSettingsEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            PinSettingsIconView()
            Text("No Pins Available")
                .font(.headline)
            Text("Connect to the controller and refresh to load available GPIO pins.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

private struct PinSettingsValidationsView: View {
    var body: some View {
        Text("Disabled pins will disappear from the dashboard and from schedule editors.")
    }
}

private extension View {
    func pinNameFieldStyle(
        focusBinding: FocusState<Int?>.Binding,
        pinID: Int,
        onSubmit: @escaping () -> Void,
        pinNumber: Int
    ) -> some View {
        textInputAutocapitalization(.words)
            .disableAutocorrection(true)
            .submitLabel(.done)
            .focused(focusBinding, equals: pinID)
            .onSubmit(onSubmit)
            .accessibilityLabel("Name for GPIO \(pinNumber)")
            .accessibilityHint("Enter a friendly name for this sprinkler zone.")
    }
}
