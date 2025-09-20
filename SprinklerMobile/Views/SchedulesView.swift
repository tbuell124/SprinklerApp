import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject private var store: SprinklerStore
    @State private var editingDraft: ScheduleDraft?
    @State private var isPresentingEditor = false

    private var toastBinding: Binding<ToastState?> {
        Binding(get: { store.toast }, set: { store.toast = $0 })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Schedules") {
                    if store.isRefreshing && store.schedules.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            ScheduleRowSkeleton()
                        }
                    } else if store.schedules.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No schedules yet")
                                .font(.headline)
                            Text("Tap the plus button to add a watering plan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(store.schedules) { schedule in
                            Button {
                                editingDraft = ScheduleDraft(schedule: schedule, pins: store.pins)
                                isPresentingEditor = true
                            } label: {
                                ScheduleRowView(schedule: schedule)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    store.duplicateSchedule(schedule)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .tint(.accentColor)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let schedule = store.schedules[index]
                                store.deleteSchedule(schedule)
                            }
                        }
                        .onMove(perform: store.reorderSchedules)
                    }
                }

            }
            .listStyle(.insetGrouped)
            .navigationTitle("Schedules")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingDraft = ScheduleDraft(pins: store.pins)
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor, onDismiss: { editingDraft = nil }) {
                if let draft = editingDraft {
                    ScheduleEditorView(draft: draft) { updated in
                        store.upsertSchedule(updated)
                    }
                }
            }
        }
        .toast(state: toastBinding)
    }
}
