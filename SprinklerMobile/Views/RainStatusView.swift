import SwiftUI

/// Card that surfaces controller connectivity, live rain delay status, and automation configuration at a glance.
struct RainStatusView: View {
    let rain: RainDTO?
    let connectivity: ConnectivityState
    let isLoading: Bool
    let isAutomationEnabled: Bool
    let isUpdatingAutomation: Bool
    let manualDelayHours: Int
    let onToggleRain: (Bool, Int?) -> Void
    let onToggleAutomation: (Bool) -> Void
    let onUpdateManualRainDuration: (Int) -> Void

    @State private var isDurationEditorPresented = false
    @State private var manualDurationSelection: Int = 12
    @State private var isActivatingManualDelay = false

    init(rain: RainDTO?,
         connectivity: ConnectivityState,
         isLoading: Bool,
         isAutomationEnabled: Bool,
         isUpdatingAutomation: Bool,
         manualDelayHours: Int,
         onToggleRain: @escaping (Bool, Int?) -> Void,
         onToggleAutomation: @escaping (Bool) -> Void,
         onUpdateManualRainDuration: @escaping (Int) -> Void) {
        self.rain = rain
        self.connectivity = connectivity
        self.isLoading = isLoading
        self.isAutomationEnabled = isAutomationEnabled
        self.isUpdatingAutomation = isUpdatingAutomation
        self.manualDelayHours = manualDelayHours
        self.onToggleRain = onToggleRain
        self.onToggleAutomation = onToggleAutomation
        self.onUpdateManualRainDuration = onUpdateManualRainDuration
        _manualDurationSelection = State(initialValue: max(manualDelayHours, 1))
    }

    var body: some View {
        Group {
            if isLoading && rain == nil {
                RainStatusSkeleton()
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ConnectivityBadgeView(state: connectivity, isLoading: isLoading)
                        .accessibilityHint("Indicates whether the controller is reachable on the network.")

                    VStack(alignment: .leading, spacing: 14) {
                        if showAutomationToggle {
                            automationToggle
                        } else {
                            automationStatusLabel
                        }

                        if showManualToggle {
                            manualToggle
                            manualDurationButton
                        }

                        statusHeader

                        if let endsAtText {
                            Text(endsAtText)
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .background(Color.appSeparator.opacity(0.5))

                        metricRow(title: "Chance of Rain", value: chanceText, valueColor: chanceColor)
                        metricRow(title: "Threshold", value: thresholdText)

                        if let zipText {
                            metricRow(title: "ZIP Code", value: zipText)
                        }

                        if !hasAutomationConfiguration {
                            Text("Configure ZIP code and threshold in Settings to enable automation.")
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                        } else if showManualToggle {
                            Text("Use the toggle above to pause watering during unexpected rain.")
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .sheet(isPresented: $isDurationEditorPresented) {
            RainDelayDurationEditor(hours: $manualDurationSelection,
                                    mode: isActivatingManualDelay ? .activate : .configure,
                                    onCancel: {
                                        isActivatingManualDelay = false
                                    },
                                    onConfirm: {
                                        handleDurationConfirmation()
                                        isActivatingManualDelay = false
                                    })
        }
        .onChange(of: manualDelayHours) { _, newValue in
            manualDurationSelection = sanitizedDuration(newValue)
        }
    }

    // MARK: - Subviews

    private var automationToggle: some View {
        HStack(spacing: 12) {
            Toggle(isOn: automationBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatic Rain Delay")
                        .font(.appButton)
                    Text("Controller will pause schedules when rain is likely.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(isUpdatingAutomation)

            if isUpdatingAutomation {
                ProgressView()
                    .progressViewStyle(.circular)
                    .accessibilityLabel("Updating automation settings")
            }
        }
    }

    private var automationStatusLabel: some View {
        Label {
            Text(automationStatusText)
                .font(.appButton)
        } icon: {
            Image(systemName: automationStatusIcon)
        }
        .foregroundStyle(automationStatusColor)
        .accessibilityHint("Automatic rain delay availability summary.")
    }

    private var manualToggle: some View {
        Toggle(isOn: rainBinding) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Rain Delay")
                    .font(.appButton)
                Text("Temporarily pause watering.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .accessibilityHint(manualToggleAccessibilityHint)
    }

    private var manualDurationButton: some View {
        Button {
            presentDurationEditor(activatingDelay: false)
        } label: {
            Label {
                Text("Set duration (\(manualDurationLabel))")
                    .font(.appCaption)
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Set manual rain delay duration")
        .accessibilityValue(manualDurationLabel)
    }


    private var statusHeader: some View {
        Label {
            Text(rainStatusText)
                .font(.appBody)
        } icon: {
            Image(systemName: rain?.isActive == true ? "cloud.rain.fill" : "cloud")
        }
        .foregroundStyle(rainStatusColor)
        .accessibilityLabel(rainStatusAccessibilityLabel)
    }

    private func metricRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.appBody)
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - Computed properties

    private var showManualToggle: Bool {
        !isAutomationEnabled
    }

    private var showAutomationToggle: Bool {
        hasAutomationConfiguration
    }

    private var manualToggleAccessibilityHint: String {
        let actionVerb = rain?.isActive == true ? "end" : "start"
        return "Double tap to \(actionVerb) a temporary rain delay."
    }

    private var hasAutomationConfiguration: Bool {
        guard let zip = rain?.zipCode,
              let threshold = rain?.thresholdPercent else { return false }
        return !zip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && threshold >= 0
    }

    private var rainBinding: Binding<Bool> {
        Binding(
            get: { rain?.isActive ?? false },
            set: { newValue in
                let currentValue = rain?.isActive ?? false
                guard newValue != currentValue else { return }
                if newValue {
                    presentDurationEditor(activatingDelay: true)
                } else {
                    onToggleRain(false, nil)
                }
            }
        )
    }

    private var manualDelayDisplayHours: Int {
        if let duration = rain?.durationHours, rain?.isActive == true, duration > 0 {
            return sanitizedDuration(duration)
        }
        return sanitizedDuration(manualDelayHours)
    }

    private var manualDurationLabel: String {
        let hours = manualDelayDisplayHours
        return "\(hours) \(hours == 1 ? "hour" : "hours")"
    }

    private func presentDurationEditor(activatingDelay: Bool) {
        isActivatingManualDelay = activatingDelay
        let seed: Int
        if activatingDelay {
            seed = sanitizedDuration(rain?.durationHours)
        } else if rain?.isActive == true {
            seed = sanitizedDuration(rain?.durationHours)
        } else {
            seed = sanitizedDuration(manualDelayHours)
        }
        manualDurationSelection = seed
        isDurationEditorPresented = true
    }

    private func handleDurationConfirmation() {
        let selected = sanitizedDuration(manualDurationSelection)
        onUpdateManualRainDuration(selected)
        if isActivatingManualDelay {
            onToggleRain(true, selected)
        }
    }

    private func sanitizedDuration(_ value: Int?) -> Int {
        sanitizedDuration(value ?? manualDelayHours)
    }

    private func sanitizedDuration(_ value: Int) -> Int {
        max(1, min(value, 72))
    }

    private var automationBinding: Binding<Bool> {
        Binding(
            get: { isAutomationEnabled },
            set: { newValue in
                if newValue != isAutomationEnabled {
                    onToggleAutomation(newValue)
                }
            }
        )
    }

    private var rainStatusText: String {
        if rain?.isActive == true {
            return "Rain delay is active"
        }
        return "Rain delay is inactive"
    }

    private var rainStatusAccessibilityLabel: String {
        if rain?.isActive == true {
            return "Rain delay is currently active"
        }
        return "Rain delay is currently inactive"
    }

    private var rainStatusColor: Color {
        rain?.isActive == true ? .appInfo : .secondary
    }

    private var endsAtText: String? {
        guard let endsAt = rain?.endsAt, rain?.isActive == true else { return nil }
        return "Ends: \(endsAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var chanceText: String {
        guard let chance = rain?.chancePercent else { return "--" }
        return "\(chance)%"
    }

    private var thresholdText: String {
        guard let threshold = rain?.thresholdPercent else { return "--" }
        return "\(threshold)%"
    }

    private var zipText: String? {
        guard let zip = rain?.zipCode else { return nil }
        let trimmed = zip.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var chanceColor: Color {
        guard let chance = rain?.chancePercent,
              let threshold = rain?.thresholdPercent,
              hasAutomationConfiguration else { return .primary }
        return chance >= threshold ? .appWarning : .appSuccess
    }

    private var automationStatusText: String {
        hasAutomationConfiguration ? "Automatic rain delay is enabled" : "Configure automation in Settings"
    }

    private var automationStatusIcon: String {
        hasAutomationConfiguration ? "clock.arrow.circlepath" : "gearshape.exclamationmark"
    }

    private var automationStatusColor: Color {
        hasAutomationConfiguration ? .appInfo : .appWarning
    }
}

// MARK: - Manual Rain Delay Editor

/// Sheet that gathers the number of hours to pause schedules when the manual rain delay is toggled on.
private struct RainDelayDurationEditor: View {
    enum Mode {
        case configure
        case activate

        var confirmationTitle: String {
            switch self {
            case .configure: return "Save"
            case .activate: return "Start Delay"
            }
        }
    }

    @Binding var hours: Int
    let mode: Mode
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    private let validRange: ClosedRange<Int> = 1...72
    private let quickPickValues: [Int] = [6, 12, 24, 48]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $hours, in: validRange) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(durationText)
                                .font(.appBody)
                                .fontWeight(.semibold)
                        }
                    }
                    TextField("Hours", value: $hours, format: .number)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($isTextFieldFocused)
                        .id(textFieldID)
                    quickPickRow
                } header: {
                    Text("Delay Length")
                } footer: {
                    Text("All watering schedules will remain paused for the selected duration.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Manual Rain Delay")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmationTitle) {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(!validRange.contains(hours))
                }
            }
        }
        .onAppear {
            // Automatically focus the text field when configuring the default duration.
            if mode == .configure {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
        }
        .onChange(of: hours) { _, newValue in
            if newValue < validRange.lowerBound {
                hours = validRange.lowerBound
            } else if newValue > validRange.upperBound {
                hours = validRange.upperBound
            }
        }
    }

    /// Stable identifier used to keep the duration text field responsive when keyboard events occur.
    private var textFieldID: String {
        switch mode {
        case .configure: return "manual-rain-delay-configure"
        case .activate: return "manual-rain-delay-activate"
        }
    }

    private var durationText: String {
        "\(hours) \(hours == 1 ? "Hour" : "Hours")"
    }

    private var quickPickRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Select")
                .font(.appCaption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(quickPickValues, id: \.self) { value in
                    Button("\(value)h") {
                        hours = value
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

