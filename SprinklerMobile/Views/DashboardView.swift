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
                LinearGradient.appCanvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        DashboardHeroCard(state: store.state,
                                          lastChecked: store.lastCheckedDate,
                                          baseURL: store.baseURLString,
                                          isLoading: store.isChecking)

                        DashboardQuickActionsSection(isChecking: store.isChecking,
                                                      onRefresh: { Task { await store.refresh() } },
                                                      onCopy: copyAddressToPasteboard)

                        DashboardStatusSection(state: store.state,
                                               lastChecked: store.lastCheckedDate,
                                               baseURL: store.baseURLString)

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

// MARK: - Sections

private struct DashboardQuickActionsSection: View {
    let isChecking: Bool
    let onRefresh: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Quick Actions")

            VStack(spacing: 12) {
                QuickActionCardButton(title: isChecking ? "Checking…" : "Run Health Check",
                                       subtitle: "Verifies that the controller is reachable right now.",
                                       icon: "wave.3.left",
                                       action: onRefresh)
                .disabled(isChecking)

                QuickActionCardButton(title: "Copy Controller URL",
                                       subtitle: "Share the configured address with another device.",
                                       icon: "doc.on.doc",
                                       action: onCopy)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DashboardStatusSection: View {
    let state: ConnectivityState
    let lastChecked: Date?
    let baseURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Status Highlights")

            VStack(spacing: 12) {
                StatusHighlightCard(title: "Reachability",
                                    icon: state.statusIcon,
                                    tint: state.statusColor,
                                    value: state.statusTitle,
                                    detail: state.statusMessage)

                if let lastChecked {
                    StatusHighlightCard(title: "Last Checked",
                                        icon: "clock.badge.checkmark",
                                        tint: Color.appAccentPrimary,
                                        value: lastChecked.formatted(date: .omitted, time: .shortened),
                                        detail: dashboardRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))
                }

                StatusHighlightCard(title: "Controller Address",
                                    icon: "network",
                                    tint: Color.appAccentSecondary,
                                    value: baseURL,
                                    detail: "Tap copy above to share this address with others.")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DashboardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.appHeadline)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Cards

/// A featured card that visualises the current connection state.
private struct DashboardHeroCard: CardView {
    let state: ConnectivityState
    let lastChecked: Date?
    let baseURL: String
    let isLoading: Bool

    var cardConfiguration: CardConfiguration { .hero(accent: state.statusColor) }

    var cardBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(state.statusColor.opacity(0.22))
                        .frame(width: 62, height: 62)
                    Image(systemName: state.statusIcon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(state.statusColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(state.statusTitle)
                        .font(.appLargeTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let message = state.statusMessage {
                        Text(message)
                            .font(.appBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .accessibilityLabel("Loading latest status")
                }
            }

            Divider()
                .background(Color.appSeparator.opacity(0.5))

            VStack(alignment: .leading, spacing: 6) {
                Text("Controller URL")
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                Text(baseURL)
                    .font(.appMonospacedBody)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Configured controller URL: \(baseURL)")

                if let lastChecked {
                    Text("Last updated \(dashboardRelativeFormatter.localizedString(for: lastChecked, relativeTo: .now))")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run a health check to capture the latest status.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact card used to display individual metrics or highlights.
private struct StatusHighlightCard: CardView {
    let title: String
    let icon: String
    let tint: Color
    let value: String
    let detail: String?

    var cardConfiguration: CardConfiguration { .subtle }

    var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.appSubheadline)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()
                .background(Color.appSeparator.opacity(0.5))

            Text(value)
                .font(.appMonospacedBody)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The reusable card-style button that drives the quick actions section.
private struct QuickActionCardButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardContainer(configuration: .subtle) {
                HStack(alignment: .center, spacing: 16) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color.appAccentPrimary, Color.appAccentPrimary.opacity(0.7)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.appButton)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.appBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }
}

/// A lightweight card that surfaces contextual tips for maintaining connectivity.
private struct HelpfulTipsCard: CardView {
    var cardBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Keep things running smoothly", systemImage: "lightbulb")
                .font(.appButton)
                .foregroundStyle(Color.appAccentSecondary)
                .labelStyle(.titleAndIcon)

            VStack(alignment: .leading, spacing: 10) {
                TipRow(text: "Ensure the Raspberry Pi remains on the same Wi-Fi network as your phone.")
                TipRow(text: "Reserve the Pi's IP address on your router to avoid unexpected changes.")
                TipRow(text: "Use the Settings tab to update the base URL whenever your network changes.")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Single row used inside the tips card to avoid repeating layout code.
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

// MARK: - Helpers live in shared extensions.
