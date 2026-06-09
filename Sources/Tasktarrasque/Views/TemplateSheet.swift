import SwiftUI
import UniformTypeIdentifiers

struct TemplateSheet: View {
    @EnvironmentObject private var controller: AppController
    @State private var draggedItem: TemplateItemAddress?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text("Template changes apply to new weeks only. Big Three items are set separately for each week.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                leftColumn
                    .frame(width: 260)
                    .padding(.trailing, 12)
                TasktarrasqueStyle.verticalDivider
                rightColumn
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TasktarrasqueStyle.panelMaterial)
        .onAppear { controller.validateTemplateSelection() }
    }

    private var header: some View {
        HStack {
            Text("Weekly Template").font(.system(size: 22, weight: .bold))
            Spacer()
            Button("Cancel") { controller.cancelTemplateAndReturnToMain() }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .glassPill(cornerRadius: 8)
            Button("Save") { controller.saveTemplateAndReturnToMain() }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .glassPill(cornerRadius: 8)
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SharedSectionHeader(title: "Daily Habits", shortcut: "H") {
                        controller.beginNewTemplateItem(in: .habit)
                    }
                    templateList(habitsBinding, list: .habits)
                    TasktarrasqueStyle.divider.padding(.vertical, 8)
                    SharedSectionHeader(title: "This Week", shortcut: "W") {
                        controller.beginNewTemplateItem(in: .thisWeek)
                    }
                    templateList(thisWeekBinding, list: .thisWeek)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SharedSectionHeader(title: "Tasks", shortcut: "N") {
                        controller.beginNewTemplateItem(in: .day(controller.templateSelectedDay))
                    }
                    templateDayTabs
                    templateList(dayTasksBinding(for: controller.templateSelectedDay), list: .day(controller.templateSelectedDay))
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var templateDayTabs: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let taskCount = controller.templateDraft.days.first(where: { $0.weekday == day })?.tasks.count ?? 0
                Button { controller.selectTemplateDay(day) } label: {
                    HStack(spacing: 5) {
                        Text(day.shortName)
                        Spacer(minLength: 1)
                        Text("\(taskCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.82)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(controller.templateSelectedDay == day ? TasktarrasqueStyle.activeControlBackground : TasktarrasqueStyle.controlBackground.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(controller.templateSelectedDay == day ? TasktarrasqueStyle.activeControlStroke : TasktarrasqueStyle.controlStroke))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func templateList(_ tasks: Binding<[TodoTask]>, list: TemplateListKind) -> some View {
        VStack(spacing: 8) {
            ForEach(tasks.wrappedValue) { task in
                let address = address(for: task.id, in: list)
                templateCard(address: address, title: task.title, placeholder: placeholder(for: list), uncheckedIcon: uncheckedIcon(for: list)) {
                    Button(role: .destructive) { controller.removeTemplateItem(address) } label: { Text("Delete") }
                }
                .onDrag {
                    draggedItem = address
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: TemplateTaskDropDelegate(target: address, dragged: $draggedItem, tasks: tasks)
                )
            }

            if let pending = controller.pendingNewTemplateAddress(for: list) {
                templateCard(address: pending, title: "", placeholder: placeholder(for: list), uncheckedIcon: uncheckedIcon(for: list)) {
                    Button(role: .destructive) { controller.cancelTemplateEdit() } label: { Text("Cancel") }
                }
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
    }

    private func templateCard<MenuContent: View>(
        address: TemplateItemAddress,
        title: String,
        placeholder: String,
        uncheckedIcon: String,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) -> some View {
        SharedTaskCard(
            title: editTitleBinding(for: address, currentTitle: title),
            placeholder: placeholder,
            isSelected: controller.selectedTemplateItem == address,
            isEditing: controller.templateEditSession?.target == address,
            isChecked: false,
            checkIcon: uncheckedIcon,
            uncheckedIcon: uncheckedIcon,
            onToggle: nil,
            onSelect: { controller.selectTemplateItem(address) },
            onBeginEdit: { controller.beginTemplateEdit(address, fallbackTitle: title) },
            onCommitEdit: { controller.commitTemplateEdit() },
            onCancelEdit: { controller.cancelTemplateEdit() },
            menu: menu
        )
    }

    private func editTitleBinding(for address: TemplateItemAddress, currentTitle: String) -> Binding<String> {
        Binding(
            get: {
                if controller.templateEditSession?.target == address {
                    return controller.templateEditSession?.draftTitle ?? currentTitle
                }
                return currentTitle
            },
            set: { newTitle in
                if controller.templateEditSession?.target == address {
                    controller.updateTemplateEditDraft(newTitle)
                } else {
                    controller.updateTemplateTitle(for: address, title: newTitle)
                }
            }
        )
    }

    private var habitsBinding: Binding<[TodoTask]> {
        Binding(
            get: { controller.templateDraft.dailyHabits },
            set: {
                controller.templateDraft.dailyHabits = $0
                controller.validateTemplateSelection()
            }
        )
    }

    private var thisWeekBinding: Binding<[TodoTask]> {
        Binding(
            get: { controller.templateDraft.thisWeekTasks },
            set: {
                controller.templateDraft.thisWeekTasks = $0
                controller.validateTemplateSelection()
            }
        )
    }

    private func dayTasksBinding(for day: Weekday) -> Binding<[TodoTask]> {
        Binding(
            get: {
                controller.templateDraft.days.first(where: { $0.weekday == day })?.tasks ?? []
            },
            set: { tasks in
                guard let index = controller.templateDraft.days.firstIndex(where: { $0.weekday == day }) else { return }
                controller.templateDraft.days[index].tasks = tasks
                controller.validateTemplateSelection()
            }
        )
    }

    private func placeholder(for list: TemplateListKind) -> String {
        switch list {
        case .habits: "Habit"
        case .thisWeek: "This Week item"
        case .day: "Task"
        }
    }

    private func uncheckedIcon(for list: TemplateListKind) -> String {
        list == .habits ? "square" : "circle"
    }

    private func address(for id: UUID, in list: TemplateListKind) -> TemplateItemAddress {
        switch list {
        case .habits:
            .habit(id)
        case .thisWeek:
            .thisWeek(id)
        case .day(let day):
            .day(day, id)
        }
    }
}

private struct TemplateTaskDropDelegate: DropDelegate {
    let target: TemplateItemAddress
    @Binding var dragged: TemplateItemAddress?
    var tasks: Binding<[TodoTask]>

    func dropEntered(info: DropInfo) {
        guard let dragged,
              dragged.isSameTemplateList(as: target),
              dragged != target,
              let source = tasks.wrappedValue.firstIndex(where: { $0.id == dragged.itemID }),
              let destination = tasks.wrappedValue.firstIndex(where: { $0.id == target.itemID }) else { return }
        let item = tasks.wrappedValue.remove(at: source)
        let adjusted = source < destination ? destination - 1 : destination
        tasks.wrappedValue.insert(item, at: max(0, min(adjusted, tasks.wrappedValue.count)))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
