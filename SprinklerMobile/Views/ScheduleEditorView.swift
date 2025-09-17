import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleDraft
    let onSave: (ScheduleDraft) -> Void

    private let dayOptions = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(draft: ScheduleDraft, onSave: @escaping (ScheduleDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $draft.name)
                    Stepper(value: $draft.durationMinutes, in: 1...180, step: 1) {
                        Text("Duration: \(draft.durationMinutes) min")
                    }
                    TextField("Start (HH:mm)", text: $draft.startTime)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }

                Section("Days") {
                    ForEach(dayOptions, id: \.self) { day in
                        MultipleSelectionRow(title: day, isSelected: draft.days.contains(day)) {
                            toggle(day: day)
                        }
                    }
                }
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
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func toggle(day: String) {
        if draft.days.contains(day) {
            draft.days.removeAll { $0 == day }
        } else {
            draft.days.append(day)
        }
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
                        .foregroundStyle(.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
