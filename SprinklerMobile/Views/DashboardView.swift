import SwiftUI

/// Shared relative formatter used for presenting schedule start and end times in a conversational manner.
private let scheduleRelativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
}()

/// Formatter dedicated to displaying just the time component for schedule summaries.
private let scheduleTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

/// Landing page that surfaces the most important controller information in four distinct panels:
/// LED status, current schedule summary, pin controls, and rain automation state.
struct DashboardView: View {
    @EnvironmentObject private var connectivityStore: ConnectivityStore
    @EnvironmentObject private var sprinklerStore: SprinklerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var pinListEditMode: EditMode = .inactive

    private var toastBinding: Binding<ToastState?> {
        Binding(get: { sprinklerStore.toast }, set: { sprinklerStore.toast = $0 })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appCanvas
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        connectivityStatusBadge
                        ledStatusCard
                        DashboardCard(title: "Schedule Summary") {
                            ScheduleSummaryView()
                        }
                        DashboardCard(title: "Pin Controls") {
                            PinListSection(isRefreshing: sprinklerStore.isRefreshing)
                        }
                        rainStatusCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await refreshAll() }
            }
            .navigationTitle("Sprinkler")
            .toolbar { refreshToolbarItem }
            .task { await refreshAll() }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await refreshAll() }
            }
        }
        .environment(\.editMode, $pinListEditMode)
        .toast(state: toastBinding)
    }

    /// High level controller connectivity indicator shown at the top of the dashboard.
    private var connectivityStatusBadge: some View {
        ConnectivityBadgeView(state: connectivityStore.state,
                               isLoading: connectivityStore.isChecking || sprinklerStore.isRefreshing)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Section containing a compact grid of GPIO indicators along with controller and rain status lights.
    private var ledStatusCard: some View {
        DashboardCard(title: "LED Status") {
            GPIOIndicatorGrid(pins: sprinklerStore.pins,
                              controllerState: connectivityStore.state,
                              rain: sprinklerStore.rain,
                              isRainAutomationEnabled: sprinklerStore.rainAutomationEnabled)
        }
    }

    /// Section visualising the current rain automation configuration and live delay state.
    private var rainStatusCard: some View {
        DashboardCard(title: "Rain Status") {
            RainStatusView(rain: sprinklerStore.rain,
                           connectivity: connectivityStore.state,
                           isLoading: sprinklerStore.isRefreshing,
                           isAutomationEnabled: sprinklerStore.rainAutomationEnabled,
                           isUpdatingAutomation: sprinklerStore.isUpdatingRainAutomation,
                           manualDelayHours: sprinklerStore.manualRainDelayHours,
                           onToggleRain: { isActive, duration in
                               let resolvedDuration = isActive ? (duration ?? sprinklerStore.manualRainDelayHours) : nil
                               sprinklerStore.setRain(active: isActive, durationHours: resolvedDuration)
                           },
                           onToggleAutomation: sprinklerStore.setRainAutomationEnabled,
                           onUpdateManualRainDuration: sprinklerStore.updateManualRainDelayHours)
        }
    }

    /// Toolbar button mirroring pull-to-refresh for additional discoverability.
    private var refreshToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await refreshAll() }
            } label: {
                if sprinklerStore.isRefreshing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .accessibilityLabel("Refreshing controller state")
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .accessibilityLabel("Refresh dashboard data")
        }
    }

    /// Triggers both the connectivity check and the controller status refresh in parallel.
    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await connectivityStore.refresh() }
            group.addTask { await sprinklerStore.refresh() }
        }
    }
}

/// Reusable wrapper providing a title and shared card styling for dashboard sections.
private struct DashboardCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(.secondary)

            CardContainer {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - GPIO Indicator Grid

/// Compact grid of controller LEDs that mirrors the hardware layout and includes controller level health lights.
private struct GPIOIndicatorGrid: View {
    struct Indicator: Identifiable {
        let id: String
        let title: String
        let caption: String?
        let symbol: String?
        let text: String?
        let fillColor: Color
        let isDimmed: Bool
        let accessibilityLabel: String
    }

    let pins: [PinDTO]
    let controllerState: ConnectivityState
    let rain: RainDTO?
    let isRainAutomationEnabled: Bool

    private var indicators: [Indicator] {
        var results: [Indicator] = pins.map { pin in
            let isActive = pin.isActive ?? false
            let isEnabled = pin.isEnabled ?? true
            let fill = isEnabled ? (isActive ? Color.appAccentPrimary : Color.appSeparator.opacity(0.6)) : Color.appSeparator.opacity(0.35)
            let captionText: String?
            if let name = pin.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name != "GPIO \(pin.pin)" {
                captionText = name
            } else {
                captionText = nil
            }
            return Indicator(id: "pin-\(pin.pin)",
                             title: "GPIO \(pin.pin)",
                             caption: captionText,
                             symbol: nil,
                             text: "\(pin.pin)",
                             fillColor: fill,
                             isDimmed: !isEnabled,
                             accessibilityLabel: "\(pin.displayName) is \(isActive ? "on" : "off")")
        }

        let controllerIsOnline: Bool
        let controllerMessage: String
        switch controllerState {
        case .connected:
            controllerIsOnline = true
            controllerMessage = "Reachable"
        case .offline:
            controllerIsOnline = false
            controllerMessage = controllerState.errorDescription ?? "Offline"
        }

        results.append(
            Indicator(id: "controller",
                      title: "Controller",
                      caption: controllerMessage,
                      symbol: "antenna.radiowaves.left.and.right",
                      text: nil,
                      fillColor: controllerIsOnline ? Color.appSuccess : Color.appDanger,
                      isDimmed: false,
                      accessibilityLabel: "Raspberry Pi connectivity is \(controllerIsOnline ? "online" : "offline")")
        )

        let rainActive = rain?.isActive == true
        let rainCaption: String
        let rainColor: Color
        if !isRainAutomationEnabled {
            rainCaption = "Automation disabled"
            rainColor = Color.appDanger
        } else if rainActive {
            rainCaption = "Delay active"
            rainColor = Color.appAccentSecondary
        } else {
            rainCaption = "No delay"
            rainColor = Color.appSeparator.opacity(0.6)
        }

        results.append(
            Indicator(id: "rain",
                      title: "Rain Delay",
                      caption: rainCaption,
                      symbol: "cloud.rain",
                      text: nil,
                      fillColor: rainColor,
                      isDimmed: !isRainAutomationEnabled && !rainActive,
                      accessibilityLabel: rainAccessibilityLabel(isActive: rainActive))
        )

        return results
    }

    private var columns: [GridItem] {
        let count = max(2, Int(ceil(sqrt(Double(indicators.count)))))
        return Array(repeating: GridItem(.flexible(minimum: 60, maximum: 120), spacing: 16), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(indicators) { indicator in
                IndicatorLight(indicator: indicator)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func rainAccessibilityLabel(isActive: Bool) -> String {
        if !isRainAutomationEnabled {
            return "Rain delay automation is disabled"
        }
        return isActive ? "Rain delay is active" : "Rain delay is inactive"
    }
}

/// Visual representation for a single LED indicator in the dashboard grid.
private struct IndicatorLight: View {
    let indicator: GPIOIndicatorGrid.Indicator

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(indicator.fillColor)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .stroke(Color.appCardStroke.opacity(0.6), lineWidth: 1)
                    }
                    .opacity(indicator.isDimmed ? 0.55 : 1)

                if let symbol = indicator.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .accessibilityHidden(true)
                } else if let text = indicator.text {
                    Text(text)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .accessibilityHidden(true)
                }
            }

            Text(indicator.title)
                .font(.appSubheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let caption = indicator.caption {
                Text(caption)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appCardBackground.opacity(0.45))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(indicator.accessibilityLabel)
    }
}

// MARK: - Schedule Summary

/// Card summarising the current and upcoming watering schedules with a convenient link to the full editor.
private struct ScheduleSummaryView: View {
    @EnvironmentObject private var store: SprinklerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let runningPins = store.runningPins
            ScheduleSummaryRow(mode: .current,
                               run: store.currentScheduleRun,
                               activePins: runningPins)
            Divider()
                .background(Color.appSeparator.opacity(0.4))
            ScheduleSummaryRow(mode: .upcoming,
                               run: store.nextScheduleRun,
                               activePins: runningPins)
            NavigationLink {
                SchedulesView()
            } label: {
                Label("Open schedules", systemImage: "calendar")
                    .font(.appButton)
            }
            .accessibilityHint("Opens the detailed schedule management screen")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Individual row describing either the current or next scheduled run.
private struct ScheduleSummaryRow: View {
    enum Mode {
        case current
        case upcoming

        var title: String {
            switch self {
            case .current: return "Currently Running"
            case .upcoming: return "Next Schedule"
            }
        }

        var emptyStateText: String {
            switch self {
            case .current: return "No zones running"
            case .upcoming: return "No schedule queued"
            }
        }
    }

    let mode: Mode
    let run: SprinklerStore.ScheduleRun?
    let activePins: [PinDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.title)
                .font(.appSubheadline)
                .foregroundStyle(.secondary)

            if let info = contentInfo() {
                Text(info.primary)
                    .font(.appButton)
                    .foregroundStyle(.primary)

                ForEach(info.secondary, id: \.self) { line in
                    Text(line)
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(mode.emptyStateText)
                    .font(.appButton)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func contentInfo() -> (primary: String, secondary: [String])? {
        switch mode {
        case .current:
            return currentRunInfo()
        case .upcoming:
            return upcomingRunInfo()
        }
    }

    private func currentRunInfo() -> (primary: String, secondary: [String])? {
        let activeNames = activePins
            .map { $0.displayName }
            .filter { !$0.isEmpty }
        if let run {
            var secondary: [String] = [detailText(for: run)]
            if !activeNames.isEmpty {
                secondary.append("Zones: \(activeNames.joined(separator: ", "))")
            }
            return (run.schedule.name ?? "Schedule", secondary)
        }

        if !activeNames.isEmpty {
            return ("Manual watering active",
                    ["Zones: \(activeNames.joined(separator: ", "))"])
        }
        return nil
    }

    private func upcomingRunInfo() -> (primary: String, secondary: [String])? {
        guard let run else { return nil }
        return (run.schedule.name ?? "Schedule", [detailText(for: run)])
    }

    private func detailText(for run: SprinklerStore.ScheduleRun) -> String {
        switch mode {
        case .current:
            let endText = scheduleTimeFormatter.string(from: run.endDate)
            let relative = scheduleRelativeFormatter.localizedString(for: run.endDate, relativeTo: .now)
            return "Ends at \(endText) (\(relative))"
        case .upcoming:
            let startText = scheduleTimeFormatter.string(from: run.startDate)
            let relative = scheduleRelativeFormatter.localizedString(for: run.startDate, relativeTo: .now)
            return "Starts \(relative) at \(startText)"
        }
    }
}

// MARK: - Pin List Section

/// Card containing the list of controllable pins with inline run timers and drag-to-reorder support.
private struct PinListSection: View {
    @EnvironmentObject private var store: SprinklerStore
    @Environment(\.editMode) private var editMode
    @State private var isExpanded = true
    @State private var durationInputs: [Int: String] = [:]
    @FocusState private var focusedDurationField: Int?

    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isExpanded {
                Divider()
                    .background(Color.appSeparator.opacity(0.35))

                if isRefreshing && store.activePins.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        PinRowSkeleton()
                    }
                } else if store.activePins.isEmpty {
                    Text("Enable pins in Settings to control these zones.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    List {
                        ForEach(store.activePins) { pin in
                            PinControlRow(pin: pin,
                                          durationBinding: binding(for: pin),
                                          focus: $focusedDurationField,
                                          onToggle: togglePin(_:desiredState:),
                                          onRun: runPin(_:minutes:))
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .moveDisabled(editMode?.wrappedValue != .active)
                        }
                        .onMove(perform: movePins)
                    }
                    .frame(maxHeight: listHeight)
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .scrollDismissesKeyboard(.interactively)
                    .toolbar { keyboardToolbar }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: store.activePins) { _, newPins in
            let valid = Set(newPins.map(\.pin))
            durationInputs = durationInputs.filter { valid.contains($0.key) }
        }
    }

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 96
        let total = CGFloat(store.activePins.count) * rowHeight
        return min(max(total, rowHeight), 480)
    }

    /// Header row containing the disclosure toggle and reorder control.
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        editMode?.wrappedValue = .inactive
                    }
                }
            } label: {
                Label("Active Zones", systemImage: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.appButton)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") the pin controls.")

            Spacer()

            if isExpanded && !store.activePins.isEmpty {
                Button {
                    if editMode?.wrappedValue == .active {
                        editMode?.wrappedValue = .inactive
                    } else {
                        editMode?.wrappedValue = .active
                    }
                } label: {
                    Label(editMode?.wrappedValue == .active ? "Done" : "Reorder",
                          systemImage: editMode?.wrappedValue == .active ? "checkmark" : "arrow.up.arrow.down")
                        .labelStyle(.titleAndIcon)
                        .font(.appCaption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Double tap to \(editMode?.wrappedValue == .active ? "stop" : "start") reordering pins.")
            }
        }
    }

    /// Returns a binding that keeps the timer text field numeric-only.
    private func binding(for pin: PinDTO) -> Binding<String> {
        Binding(
            get: { durationInputs[pin.pin] ?? "" },
            set: { newValue in
                let filtered = newValue.filter { $0.isNumber }
                durationInputs[pin.pin] = filtered
            }
        )
    }

    private func togglePin(_ pin: PinDTO, desiredState: Bool) {
        store.togglePin(pin, to: desiredState)
    }

    private func movePins(from offsets: IndexSet, to destination: Int) {
        guard isExpanded else { return }
        store.reorderPins(from: offsets, to: destination)
    }

    private func runPin(_ pin: PinDTO, minutes: Int) {
        store.runPin(pin, forMinutes: minutes)
        durationInputs[pin.pin] = ""
        focusedDurationField = nil
    }

    /// Toolbar that provides a clear dismissal action for the numeric keypad.
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedDurationField = nil }
        }
    }
}

/// Row showing a single pin with toggle and duration input.
private struct PinControlRow: View {
    let pin: PinDTO
    @Binding var durationBinding: String
    let focus: FocusState<Int?>.Binding
    let onToggle: (PinDTO, Bool) -> Void
    let onRun: (PinDTO, Int) -> Void

    private var isEnabled: Bool { pin.isEnabled ?? true }
    private var isActive: Bool { pin.isActive ?? false }
    private var minutesValue: Int? { Int(durationBinding) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.displayName)
                        .font(.appButton)
                        .foregroundStyle(.primary)
                    Text("GPIO \(pin.pin)")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(isOn: Binding(
                    get: { pin.isActive ?? false },
                    set: { newValue in
                        if isEnabled {
                            onToggle(pin, newValue)
                        }
                    }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(!isEnabled)
                .accessibilityLabel("Toggle \(pin.displayName)")
                .accessibilityHint("Double tap to \(pin.isActive ?? false ? "turn off" : "activate") this zone.")
            }

            if !isEnabled {
                Text("Enable in Settings to control this zone.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TextField("Minutes", text: $durationBinding)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 80)
                    .disabled(!isEnabled || isActive)
                    .focused(focus, equals: pin.pin)
                    .submitLabel(.done)
                    .accessibilityLabel("Run duration for \(pin.displayName)")
                    .accessibilityHint("Enter the number of minutes to run this zone.")
                    .id("pin-duration-\(pin.id)")

                Button("Start") {
                    if let minutes = minutesValue, minutes > 0 {
                        onRun(pin, minutes)
                        focus.wrappedValue = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isEnabled || isActive || (minutesValue ?? 0) <= 0)
                .accessibilityHint("Double tap to start the zone for the specified duration.")

                if isActive {
                    Text("Running…")
                        .font(.appCaption)
                        .foregroundStyle(Color.appInfo)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
