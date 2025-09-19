import SwiftUI

struct RainCardView: View {
    let rain: RainDTO?
    let isLoading: Bool
    let isAutomationEnabled: Bool
    let isUpdatingAutomation: Bool
    let onToggleAutomation: (Bool) -> Void

    init(rain: RainDTO?,
         isLoading: Bool = false,
         isAutomationEnabled: Bool,
         isUpdatingAutomation: Bool,
         onToggleAutomation: @escaping (Bool) -> Void) {
        self.rain = rain
        self.isLoading = isLoading
        self.isAutomationEnabled = isAutomationEnabled
        self.isUpdatingAutomation = isUpdatingAutomation
        self.onToggleAutomation = onToggleAutomation
    }

    var body: some View {
        Group {
            if isLoading {
                RainCardSkeleton()
            } else {
                CardContainer {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 12) {
                            Toggle(isOn: automationBinding) {
                                Text("Automatic Rain Delay")
                                    .font(.appButton)
                            }
                            .toggleStyle(.switch)
                            .disabled(!canToggleAutomation)

                            if isUpdatingAutomation {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .accessibilityLabel("Updating automation settings")
                            }
                        }

                        Label {
                            Text(rainStatusText)
                                .font(.appBody)
                        } icon: {
                            Image(systemName: rain?.isActive == true ? "cloud.rain.fill" : "cloud")
                        }
                        .foregroundStyle(rainStatusColor)

                        if let endsAt = rain?.endsAt, rain?.isActive == true {
                            Text("Ends: \(endsAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .background(Color.appSeparator.opacity(0.5))

                        LabeledContent("Chance of Rain") {
                            Text(chanceText)
                                .font(.appBody)
                                .foregroundStyle(chanceColor)
                        }

                        LabeledContent("Threshold") {
                            Text(thresholdText)
                                .font(.appBody)
                        }

                        if let zipText = zipText {
                            LabeledContent("ZIP Code") {
                                Text(zipText)
                                    .font(.appBody)
                            }
                        }

                        if !canToggleAutomation {
                            Text("Configure ZIP code and threshold in Settings to enable automation.")
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                        } else if !isAutomationEnabled {
                            Text("Automation is disabled. The controller will not schedule rain delays automatically.")
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
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

    private var canToggleAutomation: Bool {
        hasConfiguration && !isUpdatingAutomation
    }

    private var hasConfiguration: Bool {
        guard let zip = rain?.zipCode, !zip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let _ = rain?.thresholdPercent else {
            return false
        }
        return true
    }

    private var chanceText: String {
        guard let chance = rain?.chancePercent else { return "--" }
        return "\(chance)%"
    }

    private var chanceColor: Color {
        guard isAutomationEnabled,
              let chance = rain?.chancePercent,
              let threshold = rain?.thresholdPercent else {
            return .primary
        }
        return chance >= threshold ? .appWarning : .appSuccess
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

    private var rainStatusText: String {
        if rain?.isActive == true {
            return "Rain delay is active"
        }
        return "Rain delay is inactive"
    }

    private var rainStatusColor: Color {
        rain?.isActive == true ? .appInfo : .secondary
    }
}
