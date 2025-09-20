import SwiftUI
#if os(iOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared formatter to keep relative time strings consistent across the settings view.
private let settingsRelativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

/// Settings screen redesigned around card-based sections for clarity and modern aesthetics.
struct SettingsView: View {
    @EnvironmentObject private var store: ConnectivityStore
    @EnvironmentObject private var sprinklerStore: SprinklerStore
    @FocusState private var isURLFieldFocused: Bool
    @StateObject private var discoveryViewModel = DiscoveryViewModel()
    @State private var showCopiedAlert = false
    @State private var isShowingLogs = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.appCanvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        SettingsHeroCard(state: store.state,
                                         baseURL: store.baseURLString,
                                         lastChecked: store.lastTestResult?.date ?? store.lastCheckedDate,
                                         lastResult: store.lastTestResult)

                        ConnectionSettingsCard(baseURL: $store.baseURLString,
                                               discoveryViewModel: discoveryViewModel,
                                               logs: Array(store.recentLogs.prefix(3)),
                                               isDiscoveryEnabled: ControllerConfig.isDiscoveryEnabled,
                                               isChecking: store.isChecking,
                                               state: store.state,
                                               validationMessage: validationMessage,
                                               lastResult: store.lastTestResult,
                                               lastChecked: store.lastTestResult?.date ?? store.lastCheckedDate,
                                               focus: $isURLFieldFocused,
                                               onCommit: runHealthCheck,
                                               onCopy: copyAddressToPasteboard,
                                               onViewLogs: { isShowingLogs = true },
                                               onRefreshDiscovery: refreshDiscovery,
                                               onSelectDevice: useDiscoveredDevice)

                        RainDelaySettingsCard(store: sprinklerStore,
                                               onSave: {
                                                   Task { await sprinklerStore.saveRainSettings() }
                                               })

                        NavigationLink {
                            PinSettingsView()
                        } label: {
                            PinManagementCard(activePins: sprinklerStore.activePins.count,
                                              totalPins: sprinklerStore.pins.count)
                        }
                        .buttonStyle(.plain)

                        HelpfulSettingsTipsCard()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Settings")
            .toolbar { keyboardToolbar }
            .alert("Controller URL copied", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) { showCopiedAlert = false }
            } message: {
                Text("You can now paste the sprinkler controller address wherever it's needed.")
            }
            .onAppear {
                if ControllerConfig.isDiscoveryEnabled {
                    discoveryViewModel.start()
                }
            }
            .onDisappear {
                if ControllerConfig.isDiscoveryEnabled {
                    discoveryViewModel.stop()
                }
            }
            .sheet(isPresented: $isShowingLogs) {
                ConnectionLogsView(logs: store.recentLogs)
            }
        }
    }

    /// Toolbar item that provides a convenient Done button for dismissing the keyboard.
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { isURLFieldFocused = false }
        }
    }

    /// Consolidated validation message presented underneath the quick status badge.
    private var validationMessage: String? {
        if let inline = store.validationMessage, !inline.isEmpty {
            return inline
        }

        switch store.state {
        case .connected:
            return nil
        case .offline:
            return store.state.errorDescription
        }
    }

    /// Triggers a connectivity test using the current address.
    private func runHealthCheck() {
        Task { await store.testConnection() }
    }

    /// Applies the selected Bonjour device to the connection settings and tests immediately.
    private func useDiscoveredDevice(_ device: DiscoveredDevice) {
        isURLFieldFocused = false
        guard ControllerConfig.isDiscoveryEnabled else { return }
        store.baseURLString = device.baseURLString
        runHealthCheck()
    }

    /// Initiates another search for Bonjour services.
    private func refreshDiscovery() {
        isURLFieldFocused = false
        guard ControllerConfig.isDiscoveryEnabled else { return }
        discoveryViewModel.refresh()
    }

    /// Copies the configured address to the system pasteboard.
    private func copyAddressToPasteboard() {
        #if os(iOS)
        UIPasteboard.general.string = store.baseURLString
        showCopiedAlert = true
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.baseURLString, forType: .string)
        showCopiedAlert = true
        #else
        print("Controller URL copied: \(store.baseURLString)")
        #endif
    }
}

// MARK: - Supporting Sections

/// Hero card used to set the tone of the settings page with immediate feedback.
private struct SettingsHeroCard: CardView {
    let state: ConnectivityState
    let baseURL: String
    let lastChecked: Date?
    let lastResult: ConnectionTestLog?

    var cardConfiguration: CardConfiguration { .hero(accent: Color.appAccentPrimary) }

    var cardBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Controller Overview")
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                Text("Stay connected to your sprinkler")
                    .font(.appTitle)
                    .foregroundStyle(.primary)
            }

            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.appAccentPrimary.opacity(0.18))
                    .overlay {
                        Image(systemName: state.statusIcon)
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.appAccentPrimary)
                    }
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.statusTitle)
                        .font(.appButton)
                        .foregroundStyle(.primary)
                    if let message = state.statusMessage {
                        Text(message)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Configured Address")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text(baseURL)
                    .font(.appMonospacedBody)
                    .foregroundStyle(.primary)

                if let lastResult {
                    Text(lastResult.message)
                        .font(.appCaption)
                        .foregroundStyle(lastResult.outcome == .success ? Color.appSuccess : Color.appDanger)
                        .accessibilityLabel("Last test result: \(lastResult.message)")
                }

                if let lastChecked {
                    Text("Last tested \(settingsRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run a health check to capture the current status.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Primary card that holds the controller address field and connectivity state.
private struct ConnectionSettingsCard: CardView {
    @Binding var baseURL: String
    @ObservedObject var discoveryViewModel: DiscoveryViewModel
    let logs: [ConnectionTestLog]
    let isDiscoveryEnabled: Bool
    let isChecking: Bool
    let state: ConnectivityState
    let validationMessage: String?
    let lastResult: ConnectionTestLog?
    let lastChecked: Date?
    let focus: FocusState<Bool>.Binding
    let onCommit: () -> Void
    let onCopy: () -> Void
    let onViewLogs: () -> Void
    let onRefreshDiscovery: () -> Void
    let onSelectDevice: (DiscoveredDevice) -> Void

    /// Cached trimmed value of the base URL to avoid repeating string operations.
    private var trimmedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cardBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Controller Address")
                    .font(.appHeadline)
                Text("Provide the Raspberry Pi's HTTP base URL. We'll remember it for future sessions.")
                    .font(.appBody)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField(ControllerConfig.defaultBaseAddress, text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                    .textContentType(.URL)
                    .focused(focus)
                    .font(.appBody)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.appSecondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Controller address")
                    .accessibilityHint("Enter the Raspberry Pi host name or IP address.")
                    .id("controller-base-url")

                HStack(spacing: 12) {
                    Button(action: onCommit) {
                        if isChecking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Test Connection")
                                .font(.appButton)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking || trimmedBaseURL.isEmpty)
                    .accessibilityLabel("Test connection")
                    .accessibilityHint("Send a request to the sprinkler controller to verify connectivity.")

                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.appButton)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(trimmedBaseURL.isEmpty)
                    .accessibilityLabel("Copy controller address")
                    .accessibilityHint("Copies the configured address to the clipboard.")
                }
            }

            ConnectivityBadgeView(state: state, isLoading: isChecking)

            if let validationMessage, !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Connection error: \(validationMessage)")
            }

            if let lastResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lastResult.message)
                        .font(.appFootnote)
                        .foregroundStyle(lastResult.outcome == .success ? Color.appSuccess : Color.appDanger)
                        .accessibilityLabel("Last test result: \(lastResult.message)")

                    if let lastChecked {
                        Text("Last tested \(settingsRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))")
                            .font(.appFootnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isDiscoveryEnabled {
                discoverySection
            }

            if !logs.isEmpty {
                diagnosticsSection
            }

            Button(action: onViewLogs) {
                Label("View Connection Logs", systemImage: "list.bullet.rectangle")
                    .font(.appButton)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens the detailed history of recent connection checks.")
        }
        .accessibilityElement(children: .contain)
    }

    /// Renders the discovery interface showing Bonjour results beneath the manual entry field.
    @ViewBuilder
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Discovered Devices")
                    .font(.appSubheadline.weight(.semibold))
                Spacer()
                if discoveryViewModel.isBrowsing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Discovering devices")
                } else {
                    Button("Refresh", action: onRefreshDiscovery)
                        .font(.appButton)
                        .disabled(discoveryViewModel.isBrowsing)
                }
            }

            if let message = discoveryViewModel.errorMessage {
                Text(message)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            if discoveryViewModel.devices.isEmpty {
                Group {
                    if discoveryViewModel.isBrowsing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching your network…")
                                .font(.appFootnote)
                        }
                    } else if discoveryViewModel.errorMessage == nil {
                        Text("No sprinkler controllers discovered yet. Tap Refresh to try again.")
                            .font(.appFootnote)
                    }
                }
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(discoveryViewModel.devices) { device in
                        Button {
                            onSelectDevice(device)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(deviceDisplayName(device))
                                        .font(.appSubheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(deviceSubtitle(for: device))
                                        .font(.appCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isDeviceSelected(device) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appAccentPrimary)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(Color.appSecondaryBackground.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Connect to \(deviceDisplayName(device))")
                    }
                }
            }
        }
        .transition(.opacity)
    }

    /// Surfaces recent connection attempts so the user can correlate discovery results with health checks.
    @ViewBuilder
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.appSeparator.opacity(0.4))
            Text("Recent Connection Tests")
                .font(.appSubheadline.weight(.semibold))

            VStack(spacing: 8) {
                ForEach(logs) { log in
                    ConnectionLogPreviewRow(log: log)
                }
            }
        }
    }

    /// Determines whether the discovered device matches the currently configured base URL.
    private func isDeviceSelected(_ device: DiscoveredDevice) -> Bool {
        baseURL == device.baseURLString
    }

    /// Produces a human-friendly name for the discovered service.
    private func deviceDisplayName(_ device: DiscoveredDevice) -> String {
        let trimmed = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "sprinkler" : trimmed
    }

    /// Formats the subtitle showing host/IP and port information.
    private func deviceSubtitle(for device: DiscoveredDevice) -> String {
        let endpoint = device.host ?? device.ip ?? "—"
        return "\(endpoint):\(device.port)"
    }
}

/// Card that highlights quick access to pin management features.
private struct PinManagementCard: CardView {
    let activePins: Int
    let totalPins: Int

    private var subtitle: String {
        if totalPins == 0 {
            return "Connect to the controller to load configured pins."
        }
        return "Manage naming, activation, and ordering for your zones."
    }

    var cardBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pin Settings")
                        .font(.appHeadline)
                    Text(subtitle)
                        .font(.appBody)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.appAccentSecondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.appAccentSecondary)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 12) {
                Label("Active: \(activePins)", systemImage: "bolt.fill")
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(.primary)
                Label("Total: \(totalPins)", systemImage: "square.stack.3d.up")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pin settings. \(activePins) active pins out of \(totalPins).")
        .accessibilityHint("Opens controls for renaming and activating sprinkler zones.")
    }
}

/// Card that surfaces automatic rain delay options and backend persistence.
private struct RainDelaySettingsCard: CardView {
    @ObservedObject var store: SprinklerStore
    let onSave: () -> Void

    @State private var showDisableConfirmation = false

    var cardBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rain Delay Automation")
                    .font(.appHeadline)
                Text("Automatically pause watering when the forecast exceeds your configured threshold.")
                    .font(.appBody)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: automationBinding) {
                Text("Automatic rain delay")
                    .font(.appButton)
            }
            .disabled(!canEnableAutomation || store.isUpdatingRainAutomation)
            .accessibilityLabel("Automatic rain delay")
            .accessibilityHint("Pause schedules when rain probability exceeds the configured threshold.")

            if store.isUpdatingRainAutomation {
                ProgressView()
                    .progressViewStyle(.circular)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                TextField("ZIP Code", text: zipCodeBinding)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.appBody)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.appSecondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("ZIP code")
                    .accessibilityHint("Enter the ZIP code used for rain forecasts.")
                    .id("rain-settings-zip")

                TextField("Rain threshold (%)", text: thresholdBinding)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.appBody)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.appSecondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Rain threshold percentage")
                    .accessibilityHint("Enter the forecast chance that should trigger a rain delay.")
                    .id("rain-settings-threshold")
            }

            VStack(alignment: .leading, spacing: 6) {
                if !isZipValid {
                    Text("ZIP code must be five digits.")
                        .font(.appCaption)
                        .foregroundStyle(Color.appDanger)
                }
                if !isThresholdValid {
                    Text("Threshold must be between 0% and 100%.")
                        .font(.appCaption)
                        .foregroundStyle(Color.appDanger)
                }
                if !canEnableAutomation {
                    Text("Automation requires both a ZIP code and rain threshold.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onSave) {
                if store.isSavingRainSettings {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save Settings")
                        .font(.appButton)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSavingRainSettings)
            .accessibilityHint("Persist rain delay preferences to the sprinkler controller.")
        }
        .accessibilityElement(children: .contain)
    }

    var body: some View {
        CardContainer { cardBody }
            .alert("Disable automatic rain delay?", isPresented: $showDisableConfirmation) {
                Button("Disable", role: .destructive) {
                    store.setRainAutomationEnabled(false)
                    showDisableConfirmation = false
                }
                Button("Cancel", role: .cancel) {
                    showDisableConfirmation = false
                    store.rainSettingsIsEnabled = true
                }
            } message: {
                Text("Manual confirmation prevents accidental watering during storms.")
            }
    }

    private var zipCodeBinding: Binding<String> {
        Binding(get: { store.rainSettingsZip },
                set: { newValue in
                    let filtered = newValue.filter(\.isNumber)
                    let truncated = String(filtered.prefix(5))
                    store.updateRainSettings(zip: truncated)
                })
    }

    private var thresholdBinding: Binding<String> {
        Binding(get: { store.rainSettingsThreshold },
                set: { newValue in
                    let filtered = newValue.filter(\.isNumber)
                    let truncated = String(filtered.prefix(3))
                    store.updateRainSettings(threshold: truncated)
                })
    }

    private var automationBinding: Binding<Bool> {
        Binding(get: { store.rainSettingsIsEnabled },
                set: { newValue in
                    if newValue {
                        store.setRainAutomationEnabled(true)
                    } else {
                        showDisableConfirmation = true
                    }
                })
    }

    private var canEnableAutomation: Bool {
        isZipValid && isThresholdValid
    }

    private var isZipValid: Bool {
        let trimmed = store.rainSettingsZip.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 5 && trimmed.allSatisfy(\.isNumber)
    }

    private var isThresholdValid: Bool {
        let trimmed = store.rainSettingsThreshold.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return false }
        return (0...100).contains(value)
    }
}

/// Compact row used to preview a single connection test result inside the discovery section.
private struct ConnectionLogPreviewRow: View {
    let log: ConnectionTestLog

    private var accentColor: Color {
        log.outcome == .success ? .appSuccess : .appDanger
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: log.outcome == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.message)
                    .font(.appFootnote)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(log.outcome.label)
                        .font(.appCaption2.weight(.semibold))
                        .foregroundStyle(accentColor)
                    if let latency = log.formattedLatency {
                        Text(latency)
                            .font(.appCaption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(settingsRelativeFormatter.localizedString(for: log.date, relativeTo: .now))
                .font(.appCaption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(log.outcome.label) \(log.message)")
    }
}

/// Full screen sheet that lists connection attempts with timestamps and latency readings.
private struct ConnectionLogsView: View {
    let logs: [ConnectionTestLog]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(.largeTitle, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("No Connection Logs")
                            .font(.appHeadline)
                        Text("Run a connection test to capture history.")
                            .font(.appBody)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: log.outcome == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(log.outcome == .success ? Color.appSuccess : Color.appDanger)
                                Text(log.outcome.label)
                                    .font(.appSubheadline.weight(.semibold))
                                    .foregroundStyle(log.outcome == .success ? Color.appSuccess : Color.appDanger)
                                Spacer()
                                Text(settingsRelativeFormatter.localizedString(for: log.date, relativeTo: .now))
                                    .font(.appCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(log.message)
                                .font(.appBody)
                                .foregroundStyle(.primary)
                            if let latency = log.formattedLatency {
                                Text("Latency: \(latency)")
                                    .font(.appCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(log.outcome.label) at \(settingsRelativeFormatter.localizedString(for: log.date, relativeTo: .now)). \(log.message)")
                    }
                }
            }
            .navigationTitle("Connection Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Reinforces best practices for keeping connectivity stable.
private struct HelpfulSettingsTipsCard: CardView {
    var cardBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Helpful Tips", systemImage: "info.circle")
                .font(.appHeadline)

            VStack(alignment: .leading, spacing: 10) {
                TipRow(text: "Double-check that the Raspberry Pi stays powered and connected to your LAN.")
                TipRow(text: "Update this URL if you move to a new network or change routers.")
                TipRow(text: "Restrict access to trusted devices and keep your token secure.")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Single tip row reused within the settings tips card.
private struct TipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.appSuccess)
                .accessibilityHidden(true)
            Text(text)
                .font(.appBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
