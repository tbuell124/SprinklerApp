import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleDraft
    @State private var timeSelection: Date
    let onSave: (ScheduleDraft) -> Void

    private let dayOptions = Schedule.defaultDays

    init(draft: ScheduleDraft, onSave: @escaping (ScheduleDraft) -> Void) {
        var workingDraft = draft
        let parsedTime = ScheduleEditorView.date(from: draft.startTime) ?? ScheduleEditorView.defaultTime
        workingDraft.startTime = ScheduleEditorView.timeString(from: parsedTime)
        _draft = State(initialValue: workingDraft)
        _timeSelection = State(initialValue: parsedTime)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                daysSection
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isDraftSavable)
                }
            }
            .onChange(of: timeSelection, initial: false) { _, newValue in
                draft.startTime = ScheduleEditorView.timeString(from: newValue)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $draft.name)
                .id("schedule-name-\(draft.id)")
                .keyboardType(.default)
                .autocorrectionDisabled()
            LabeledContent("Run Time (min)") {
                TextField("0", value: $draft.runTimeMinutes, format: .number)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            DatePicker("Start Time",
                       selection: $timeSelection,
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
            Toggle("Enabled", isOn: $draft.isEnabled)
        }
    }

    private var daysSection: some View {
        Section("Days") {
            ForEach(dayOptions, id: \.self) { day in
                MultipleSelectionRow(title: day, isSelected: draft.days.contains(day)) {
                    toggle(day: day)
                }
            }
        }
    }

    private var isDraftSavable: Bool {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && draft.runTimeMinutes > 0 && !draft.days.isEmpty
    }

    private func toggle(day: String) {
        let normalizedDay = day.lowercased()
        if draft.days.contains(where: { $0.lowercased() == normalizedDay }) {
            draft.days.removeAll { $0.lowercased() == normalizedDay }
        } else {
            draft.days.append(day)
        }
        draft.days = Schedule.orderedDays(from: draft.days)
    }

    private static func date(from timeString: String) -> Date? {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }
        return Calendar.current.date(bySettingHour: hour,
                                     minute: minute,
                                     second: 0,
                                     of: Date())
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()
    }
}

private struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
