import SwiftUI
#if os(iOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared relative date formatter so all components display consistent phrasing.
private let dashboardRelativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

/// Landing view that presents a rich overview of the sprinkler controller's health
/// and quick access to the most common actions.
struct DashboardView: View {
    @EnvironmentObject private var store: ConnectivityStore
    @State private var showCopiedToast = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                // A subtle background gradient keeps the dashboard feeling lively without
                // overpowering the content so the cards remain the primary focus.
                LinearGradient(colors: [Color.appBackground, Color.appSecondaryBackground],
                               startPoint: .top,
                               endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        DashboardHeroCard(state: store.state,
                                          lastChecked: store.lastCheckedDate,
                                          baseURL: store.baseURLString,
                                          isLoading: store.isChecking)

                        quickActionsSection

                        statusHighlightsSection

                        HelpfulTipsCard()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                }
            }
            .navigationTitle("Sprinkler")
            .toolbar { refreshToolbarItem }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .alert("Controller URL copied", isPresented: $showCopiedToast) {
                Button("OK", role: .cancel) { showCopiedToast = false }
            } message: {
                Text("Share this address with anyone who needs access to the sprinkler controller.")
            }
            .onChange(of: scenePhase) { _, phase in
                // Automatically refresh whenever the app becomes active so the dashboard
                // always reflects the most recent controller state.
                if phase == .active {
                    Task { await store.refresh() }
                }
            }
        }
    }

    /// Toolbar button that mirrors pull-to-refresh for discoverability.
    private var refreshToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isChecking {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .accessibilityLabel("Refresh controller status")
        }
    }

    /// Section that houses contextual quick actions for the controller.
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                QuickActionButton(title: store.isChecking ? "Checking…" : "Run Health Check",
                                   subtitle: "Verifies that the controller is reachable right now.",
                                   icon: "wave.3.left") {
                    Task { await store.refresh() }
                }
                .disabled(store.isChecking)

                QuickActionButton(title: "Copy Controller URL",
                                   subtitle: "Share the configured address with another device.",
                                   icon: "doc.on.doc") {
                    copyAddressToPasteboard()
                }
            }
        }
    }

    /// Section that highlights status information about connectivity and configuration.
    private var statusHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status Highlights")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                StatusHighlightCard(title: "Reachability",
                                    icon: store.state.statusIcon,
                                    tint: store.state.statusColor,
                                    value: store.state.statusTitle,
                                    detail: store.state.statusMessage)

                if let lastChecked = store.lastCheckedDate {
                    StatusHighlightCard(title: "Last Checked",
                                        icon: "clock.badge.checkmark",
                                        tint: .blue,
                                        value: lastChecked.formatted(date: .omitted, time: .shortened),
                                        detail: dashboardRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))
                }

                StatusHighlightCard(title: "Controller Address",
                                    icon: "network",
                                    tint: .teal,
                                    value: store.baseURLString,
                                    detail: "Tap copy above to share this address with others.")
            }
        }
    }

    /// Copies the configured controller address to the user's pasteboard with platform awareness.
    private func copyAddressToPasteboard() {
        #if os(iOS)
        UIPasteboard.general.string = store.baseURLString
        showCopiedToast = true
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.baseURLString, forType: .string)
        showCopiedToast = true
        #else
        // Other platforms may not offer a convenient API; fall back to logging so developers
        // still have visibility during testing.
        print("Controller URL copied: \(store.baseURLString)")
        #endif
    }
}

// MARK: - Supporting Views

/// A featured card that visualises the current connection state.
private struct DashboardHeroCard: View {
    let state: ConnectivityState
    let lastChecked: Date?
    let baseURL: String
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(state.statusColor.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: state.statusIcon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(state.statusColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(state.statusTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    if let message = state.statusMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.3))

            VStack(alignment: .leading, spacing: 4) {
                Text("Controller URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(baseURL)
                    .font(.headline.monospaced())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Configured controller URL: \(baseURL)")

                if let lastChecked {
                    Text("Last updated \(dashboardRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run a health check to capture the latest status.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [state.statusColor.opacity(0.25), Color.appSecondaryBackground],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// Compact card used to display individual metrics or highlights.
private struct StatusHighlightCard: View {
    let title: String
    let icon: String
    let tint: Color
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
                .background(Color.appSeparator)

            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// The reusable card-style button that drives the quick actions section.
private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A lightweight card that surfaces contextual tips for maintaining connectivity.
private struct HelpfulTipsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep things running smoothly", systemImage: "lightbulb")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TipRow(text: "Ensure the Raspberry Pi remains on the same Wi-Fi network as your phone.")
                TipRow(text: "Reserve the Pi's IP address on your router to avoid unexpected changes.")
                TipRow(text: "Use the Settings tab to update the base URL whenever your network changes.")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Single row used inside the tips card to avoid repeating layout code.
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

// MARK: - Helpers live in shared extensions.
