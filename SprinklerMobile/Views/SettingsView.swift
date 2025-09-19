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
                LinearGradient(colors: [Color.appBackground, Color.appSecondaryBackground],
                               startPoint: .top,
                               endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        SettingsHeroCard(state: store.state,
                                         baseURL: store.baseURLString,
                                         lastChecked: store.lastTestResult?.date ?? store.lastCheckedDate,
                                         lastResult: store.lastTestResult)

                        ConnectionSettingsCard(baseURL: $store.baseURLString,
                                               isChecking: store.isChecking,
                                               state: store.state,
                                               validationMessage: validationMessage,
                                               lastResult: store.lastTestResult,
                                               lastChecked: store.lastTestResult?.date ?? store.lastCheckedDate,
                                               focus: $isURLFieldFocused,
                                               onCommit: runHealthCheck,
                                               onCopy: copyAddressToPasteboard,
                                               onViewLogs: { isShowingLogs = true })

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

                        DiscoveryCard(viewModel: discoveryViewModel,
                                      logs: Array(store.recentLogs.prefix(3)),
                                      onSelect: useDiscoveredDevice,
                                      onRefresh: refreshDiscovery,
                                      onViewLogs: { isShowingLogs = true })

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
            .onAppear { discoveryViewModel.start() }
            .onDisappear { discoveryViewModel.stop() }
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
        case let .offline(message):
            return message
        }
    }

    /// Triggers a connectivity test using the current address.
    private func runHealthCheck() {
        Task { await store.testConnection() }
    }

    /// Applies the selected Bonjour device to the connection settings and tests immediately.
    private func useDiscoveredDevice(_ device: DiscoveredDevice) {
        isURLFieldFocused = false
        store.baseURLString = device.baseURLString
        runHealthCheck()
    }

    /// Initiates another search for Bonjour services.
    private func refreshDiscovery() {
        isURLFieldFocused = false
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
private struct SettingsHeroCard: View {
    let state: ConnectivityState
    let baseURL: String
    let lastChecked: Date?
    let lastResult: ConnectionTestLog?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Controller Overview")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Stay connected to your sprinkler")
                    .font(.title2.weight(.bold))
            }

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: state.statusIcon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(state.statusColor)
                    .frame(width: 60, height: 60)
                    .background(state.statusColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.statusTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let message = state.statusMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Configured Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(baseURL)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.primary)

                if let lastResult {
                    Text(lastResult.message)
                        .font(.caption)
                        .foregroundStyle(lastResult.outcome == .success ? Color.appSuccess : Color.appDanger)
                        .accessibilityLabel("Last test result: \(lastResult.message)")
                }

                if let lastChecked {
                    Text("Last tested \(settingsRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run a health check to capture the current status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// Primary card that holds the controller address field and connectivity state.
private struct ConnectionSettingsCard: View {
    @Binding var baseURL: String
    let isChecking: Bool
    let state: ConnectivityState
    let validationMessage: String?
    let lastResult: ConnectionTestLog?
    let lastChecked: Date?
    let focus: FocusState<Bool>.Binding
    let onCommit: () -> Void
    let onCopy: () -> Void
    let onViewLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Controller Address")
                .font(.headline)

            Text("Provide the Raspberry Pi's HTTP base URL. We'll remember it for future sessions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("http://sprinkler.local:8000", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                    .textContentType(.URL)
                    .focused(focus)
                    .accessibilityLabel("Controller address")
                    .accessibilityHint("Enter the Raspberry Pi host name or IP address.")
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.appSecondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 12) {
                    Button(action: onCommit) {
                        if isChecking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Test Connection")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Test connection")
                    .accessibilityHint("Send a request to the sprinkler controller to verify connectivity.")

                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Copy controller address")
                    .accessibilityHint("Copies the configured address to the clipboard.")
                }
            }

            ConnectivityBadgeView(state: state, isLoading: isChecking)

            if let validationMessage, !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Connection error: \(validationMessage)")
            }

            if let lastResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lastResult.message)
                        .font(.footnote)
                        .foregroundStyle(lastResult.outcome == .success ? Color.appSuccess : Color.appDanger)
                        .accessibilityLabel("Last test result: \(lastResult.message)")

                    if let lastChecked {
                        Text("Last tested \(settingsRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(action: onViewLogs) {
                Label("View Connection Logs", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens the detailed history of recent connection checks.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Card that highlights quick access to pin management features.
private struct PinManagementCard: View {
    let activePins: Int
    let totalPins: Int

    private var subtitle: String {
        if totalPins == 0 {
            return "Connect to the controller to load configured pins."
        }
        return "Manage naming, activation, and ordering for your zones."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pin Settings")
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .padding(12)
                    .background(Color.appSecondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 12) {
                Label("Active: \(activePins)", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Label("Total: \(totalPins)", systemImage: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pin settings. \(activePins) active pins out of \(totalPins).")
        .accessibilityHint("Opens controls for renaming and activating sprinkler zones.")
    }
}

/// Card that surfaces automatic rain delay options and backend persistence.
private struct RainDelaySettingsCard: View {
    @ObservedObject var store: SprinklerStore
    let onSave: () -> Void

    @State private var showDisableConfirmation = false

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

    private var canEnableAutomation: Bool {
        isZipValid && isThresholdValid
    }

    private var isZipValid: Bool {
        let trimmed = store.rainSettingsZip.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 5 && trimmed.allSatisfy(\.isNumber)
    }

    private var isThresholdValid: Bool {
        let trimmed = store.rainSettingsThreshold.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed), (0...100).contains(value) {
            return true
        }
        return false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rain Delay Settings")
                .font(.headline)

            Text("Automatically pause watering when the forecast exceeds your configured threshold.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle(isOn: automationBinding) {
                Text("Automatic rain delay")
                    .font(.subheadline.weight(.semibold))
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
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.appSecondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("ZIP code")
                    .accessibilityHint("Enter the ZIP code used for rain forecasts.")

                TextField("Rain threshold (%)", text: thresholdBinding)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.appSecondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Rain threshold percentage")
                    .accessibilityHint("Enter the forecast chance that should trigger a rain delay.")
            }

            VStack(alignment: .leading, spacing: 6) {
                if !isZipValid {
                    Text("ZIP code must be five digits.")
                        .font(.caption)
                        .foregroundStyle(Color.appDanger)
                }
                if !isThresholdValid {
                    Text("Threshold must be between 0% and 100%.")
                        .font(.caption)
                        .foregroundStyle(Color.appDanger)
                }
                if !canEnableAutomation {
                    Text("Automation requires both a ZIP code and rain threshold.")
                        .font(.caption)
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
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSavingRainSettings)
            .accessibilityHint("Persist rain delay preferences to the sprinkler controller.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .alert("Disable automatic rain delay?", isPresented: $showDisableConfirmation) {
            Button("Disable", role: .destructive) {
                store.setRainAutomationEnabled(false)
                showDisableConfirmation = false
            }
            Button("Cancel", role: .cancel) {
                showDisableConfirmation = false
            }
        } message: {
            Text("Manual confirmation prevents accidental watering during storms.")
        }
    }
}

/// Displays discovered Bonjour devices in a stylised card.
private struct DiscoveryCard: View {
    @ObservedObject var viewModel: DiscoveryViewModel
    let logs: [ConnectionTestLog]
    let onSelect: (DiscoveredDevice) -> Void
    let onRefresh: () -> Void
    let onViewLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Discovered Devices")
                    .font(.headline)
                Spacer()
                if viewModel.isBrowsing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.devices.isEmpty {
                Group {
                    if viewModel.isBrowsing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching your network…")
                        }
                    } else if viewModel.errorMessage == nil {
                        Text("No sprinkler controllers discovered yet. Tap Refresh to try again.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.devices) { device in
                        Button {
                            onSelect(device)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(device.name.isEmpty ? "sprinkler" : device.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(deviceSubtitle(for: device))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.appSecondaryBackground.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !logs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("Recent Connection Tests")
                        .font(.subheadline.weight(.semibold))
                    VStack(spacing: 8) {
                        ForEach(logs) { log in
                            ConnectionLogPreviewRow(log: log)
                        }
                    }
                    Button(action: onViewLogs) {
                        Label("View All Logs", systemImage: "clock.arrow.circlepath")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens the detailed list of connection attempts.")
                }
            }

            HStack {
                Spacer()
                Button("Refresh", action: onRefresh)
                    .disabled(viewModel.isBrowsing)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }

    private func deviceSubtitle(for device: DiscoveredDevice) -> String {
        let endpoint = device.host ?? device.ip ?? "—"
        return "\(endpoint):\(device.port)"
    }
}

/// Compact row used to preview a single connection test result inside the discovery card.
private struct ConnectionLogPreviewRow: View {
    let log: ConnectionTestLog

    private var accentColor: Color {
        log.outcome == .success ? .appSuccess : .appDanger
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: log.outcome == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(log.outcome.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentColor)
                    if let latency = log.formattedLatency {
                        Text(latency)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(settingsRelativeFormatter.localizedString(for: log.date, relativeTo: .now))
                .font(.caption2)
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
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Connection Logs")
                            .font(.headline)
                        Text("Run a connection test to capture history.")
                            .font(.subheadline)
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
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(log.outcome == .success ? Color.appSuccess : Color.appDanger)
                                Spacer()
                                Text(settingsRelativeFormatter.localizedString(for: log.date, relativeTo: .now))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(log.message)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if let latency = log.formattedLatency {
                                Text("Latency: \(latency)")
                                    .font(.caption)
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
private struct HelpfulSettingsTipsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Helpful Tips", systemImage: "info.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TipRow(text: "Double-check that the Raspberry Pi stays powered and connected to your LAN.")
                TipRow(text: "Update this URL if you move to a new network or change routers.")
                TipRow(text: "Restrict access to trusted devices and keep your token secure.")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Single tip row reused within the settings tips card.
private struct TipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
