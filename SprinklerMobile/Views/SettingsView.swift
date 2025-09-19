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
    @FocusState private var isURLFieldFocused: Bool
    @StateObject private var discoveryViewModel = DiscoveryViewModel()
    @State private var showCopiedAlert = false

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
                                         lastChecked: store.lastCheckedDate)

                        ConnectionSettingsCard(baseURL: $store.baseURLString,
                                               isChecking: store.isChecking,
                                               state: store.state,
                                               validationMessage: validationMessage,
                                               focus: $isURLFieldFocused,
                                               onCommit: runHealthCheck,
                                               onCopy: copyAddressToPasteboard)

                        DiscoveryCard(viewModel: discoveryViewModel,
                                      onSelect: useDiscoveredDevice,
                                      onRefresh: refreshDiscovery)

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

            VStack(alignment: .leading, spacing: 4) {
                Text("Configured URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(baseURL)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.primary)

                if let lastChecked {
                    Text("Last checked \(settingsRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))")
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
    let focus: FocusState<Bool>.Binding
    let onCommit: () -> Void
    let onCopy: () -> Void

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

                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            ConnectivityBadgeView(state: state, isLoading: isChecking)

            if let validationMessage, !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Connection error: \(validationMessage)")
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

/// Displays discovered Bonjour devices in a stylised card.
private struct DiscoveryCard: View {
    @ObservedObject var viewModel: DiscoveryViewModel
    let onSelect: (DiscoveredDevice) -> Void
    let onRefresh: () -> Void

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
