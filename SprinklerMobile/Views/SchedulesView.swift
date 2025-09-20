import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject private var store: SprinklerStore
    @State private var editingDraft: ScheduleDraft?

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
                                // Tapping any row opens an editor sheet populated with that schedule.
                                editingDraft = ScheduleDraft(schedule: schedule, pins: store.pins)
                            } label: {
                                ScheduleRowView(schedule: schedule)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    // Swipe-to-delete to satisfy CRUD requirements.
                                    store.deleteSchedule(schedule)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

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
                        // Create a brand-new schedule and present it in the editor sheet.
                        editingDraft = ScheduleDraft(pins: store.pins)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingDraft, onDismiss: { editingDraft = nil }) { draft in
                ScheduleEditorView(draft: draft) { updated in
                    store.upsertSchedule(updated)
                    editingDraft = nil
                }
            }
        }
        .toast(state: toastBinding)
    }
}
