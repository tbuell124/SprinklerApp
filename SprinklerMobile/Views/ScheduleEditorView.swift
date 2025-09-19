import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SprinklerStore
    @State private var draft: ScheduleDraft
    @State private var timeSelection: Date
    let onSave: (ScheduleDraft) -> Void

    private let dayOptions = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var pinsByNumber: [Int: PinDTO] {
        Dictionary(uniqueKeysWithValues: store.pins.map { ($0.pin, $0) })
    }

    private var activePins: [PinDTO] {
        store.activePins
    }

    private var missingActivePins: [PinDTO] {
        let assignedPins = Set(draft.sequence.map(\.pin))
        return activePins.filter { !assignedPins.contains($0.pin) }
    }

    private var inactiveSteps: [ScheduleDraft.Step] {
        draft.sequence.filter { step in
            !(pinsByNumber[step.pin]?.isEnabled ?? true)
        }
    }

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
                sequenceSection
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !draft.sequence.isEmpty {
                        EditButton()
                    }
                }
            }
            .onChange(of: timeSelection) { newValue in
                draft.startTime = ScheduleEditorView.timeString(from: newValue)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $draft.name)
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

    private var sequenceSection: some View {
        Section("Sequence") {
            if draft.sequence.isEmpty {
                Text("Add zones to control the watering order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(draft.sequence.enumerated()), id: \.element.id) { index, step in
                    let binding = Binding(
                        get: { draft.sequence[index] },
                        set: { draft.sequence[index] = $0 }
                    )
                    ScheduleSequenceRow(step: binding,
                                        pin: pinsByNumber[step.pin],
                                        isPinEnabled: pinsByNumber[step.pin]?.isEnabled ?? true) {
                        draft.removeSteps(at: IndexSet(integer: index))
                    }
                }
                .onDelete { offsets in
                    draft.removeSteps(at: offsets)
                }
                .onMove { offsets, newOffset in
                    draft.moveSteps(from: offsets, to: newOffset)
                }
            }

            if !missingActivePins.isEmpty {
                Button {
                    draft.addSteps(for: missingActivePins)
                } label: {
                    Label("Add All Active Pins", systemImage: "plus.circle.fill")
                }

                Menu {
                    ForEach(missingActivePins) { pin in
                        Button(pin.name ?? "Pin \(pin.pin)") {
                            draft.addStep(for: pin)
                        }
                    }
                } label: {
                    Label("Add Pin", systemImage: "plus")
                }
            }

            if !inactiveSteps.isEmpty {
                Label("Inactive pins remain in this schedule", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityHint("Enable the pin from the Zones screen to run it in this schedule")
            }
        }
    }

    private var isDraftSavable: Bool {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !draft.sequence.isEmpty
    }

    private func toggle(day: String) {
        if draft.days.contains(day) {
            draft.days.removeAll { $0 == day }
        } else {
            draft.days.append(day)
        }
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

private struct ScheduleSequenceRow: View {
    @Binding var step: ScheduleDraft.Step
    let pin: PinDTO?
    let isPinEnabled: Bool
    let onDelete: () -> Void

    private var pinName: String {
        pin?.name ?? "Pin \(step.pin)"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pinName)
                    .font(.body)
                Text("GPIO \(step.pin)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !isPinEnabled {
                    Label("Pin disabled", systemImage: "slash.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Stepper(value: $step.durationMinutes, in: 0...240) {
                Text("\(step.durationMinutes) min")
                    .font(.body.monospacedDigit())
            }
            .accessibilityLabel(Text("Duration for \(pinName)"))
        }
        .contentShape(Rectangle())
        .opacity(isPinEnabled ? 1 : 0.5)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
