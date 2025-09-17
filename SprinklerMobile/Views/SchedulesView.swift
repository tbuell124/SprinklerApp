import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingDraft: ScheduleDraft?
    @State private var isPresentingEditor = false
    @State private var isAddingGroup = false
    @State private var newGroupName: String = ""
    @State private var isLoadingGroups = false

    private var toastBinding: Binding<ToastState?> {
        Binding(get: { appState.toast }, set: { appState.toast = $0 })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Schedules") {
                    if appState.isRefreshing && appState.schedules.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            ScheduleRowSkeleton()
                        }
                    } else if appState.schedules.isEmpty {
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
                        ForEach(appState.schedules) { schedule in
                            Button {
                                editingDraft = ScheduleDraft(schedule: schedule)
                                isPresentingEditor = true
                            } label: {
                                ScheduleRowView(schedule: schedule)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let schedule = appState.schedules[index]
                                appState.deleteSchedule(schedule)
                            }
                        }
                        .onMove(perform: appState.reorderSchedules)
                    }
                }

                if isLoadingGroups || !appState.scheduleGroups.isEmpty || isAddingGroup {
                    Section("Groups") {
                        if isLoadingGroups {
                            ForEach(0..<2, id: \.self) { _ in
                                ScheduleGroupSkeleton()
                            }
                        } else {
                            ForEach(appState.scheduleGroups) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.name ?? "Group")
                                        .font(.headline)
                                    LazyHStack(spacing: 12) {
                                        Button("Select") {
                                            appState.selectScheduleGroup(id: group.id)
                                        }
                                        Button("Add All") {
                                            appState.addAllToGroup(id: group.id)
                                        }
                                        Button(role: .destructive) {
                                            appState.deleteScheduleGroup(id: group.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                if isAddingGroup {
                    Section("New Group") {
                        TextField("Group name", text: $newGroupName)
                        Button("Create") {
                            let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            appState.createScheduleGroup(name: trimmed)
                            newGroupName = ""
                            withAnimation { isAddingGroup = false }
                        }
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
                        editingDraft = ScheduleDraft()
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(isAddingGroup ? "Cancel" : "New Group") {
                        withAnimation {
                            isAddingGroup.toggle()
                        }
                        if !isAddingGroup {
                            newGroupName = ""
                        }
                    }
                }
            }
            .sheet(isPresented: $isPresentingEditor, onDismiss: { editingDraft = nil }) {
                if let draft = editingDraft {
                    ScheduleEditorView(draft: draft) { updated in
                        appState.upsertSchedule(updated)
                    }
                }
            }
            .task {
                isLoadingGroups = true
                defer { isLoadingGroups = false }
                await appState.loadScheduleGroups()
            }
        }
        .toast(state: toastBinding)
    }
}
