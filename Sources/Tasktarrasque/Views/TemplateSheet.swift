import SwiftUI
import UniformTypeIdentifiers

struct TemplateSheet: View {
    @EnvironmentObject private var store: TaskStore
    let onClose: () -> Void

    @State private var draft = WeeklyTemplate()
    @State private var selectedDay: Weekday = .monday
    @State private var draggedItem: TemplateItemFocus?
    @FocusState private var focusedItem: TemplateItemFocus?
    @FocusState private var renameItem: TemplateItemFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text("Template changes apply to new weeks only. Big Three items are set separately for each week.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                leftColumn
                    .frame(width: 300)
                    .padding(.trailing, 12)
                TasktarrasqueStyle.verticalDivider
                rightColumn
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .background(TasktarrasqueStyle.panelMaterial)
        .onAppear { draft = store.template }
        .onMoveCommand(perform: moveFocus)
        .onDeleteCommand(perform: deleteFocusedItem)
        .onKeyPress(.return) {
            if renameItem != nil { renameItem = nil } else { renameItem = focusedItem }
            return .handled
        }
        // Template items have no done state, so swallow "d" to keep it from
        // bubbling up and toggling anything in the main view behind the sheet.
        .onKeyPress("d") { return .handled }
        .onKeyPress("h") { createItem(in: .habits); return .handled }
        .onKeyPress("w") { createItem(in: .thisWeek); return .handled }
        .onKeyPress("n") { createItem(in: .day(selectedDay)); return .handled }
        .onKeyPress("r") { renameItem = focusedItem; return .handled }
        .onKeyPress(keys: [.upArrow]) { press in
            guard press.modifiers.contains(.shift) else { return .ignored }
            moveFocusedItem(offset: -1)
            return .handled
        }
        .onKeyPress(keys: [.downArrow]) { press in
            guard press.modifiers.contains(.shift) else { return .ignored }
            moveFocusedItem(offset: 1)
            return .handled
        }
        .onExitCommand {
            if renameItem != nil { renameItem = nil } else { onClose() }
        }
    }

    private var header: some View {
        HStack {
            Text("Weekly Template").font(.system(size: 22, weight: .bold))
            Spacer()
            Button("Cancel", action: onClose)
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .glassPill(cornerRadius: 8)
            Button("Save") { saveAndClose() }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .glassPill(cornerRadius: 8)
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SharedSectionHeader(title: "Daily Habits", shortcut: "H") { createItem(in: .habits) }
                    templateList($draft.dailyHabits, list: .habits)
                    TasktarrasqueStyle.divider.padding(.vertical, 8)
                    SharedSectionHeader(title: "This Week", shortcut: "W") { createItem(in: .thisWeek) }
                    templateList($draft.thisWeekTasks, list: .thisWeek)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SharedSectionHeader(title: "Tasks", shortcut: "N") { createItem(in: .day(selectedDay)) }
                    templateDayTabs
                    if let index = draft.days.firstIndex(where: { $0.weekday == selectedDay }) {
                        templateList($draft.days[index].tasks, list: .day(selectedDay))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var templateDayTabs: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let taskCount = draft.days.first(where: { $0.weekday == day })?.tasks.count ?? 0
                Button { selectedDay = day } label: {
                    HStack(spacing: 5) {
                        Text(day.shortName)
                        Spacer(minLength: 2)
                        Text("\(taskCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.82)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(selectedDay == day ? TasktarrasqueStyle.activeControlBackground : TasktarrasqueStyle.controlBackground.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedDay == day ? TasktarrasqueStyle.activeControlStroke : TasktarrasqueStyle.controlStroke))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func templateList(_ tasks: Binding<[TodoTask]>, list: TemplateListKind) -> some View {
        VStack(spacing: 8) {
            ForEach(tasks.wrappedValue) { task in
                let focus = TemplateItemFocus(list: list, id: task.id)
                SharedTaskCard(
                    title: titleBinding(for: task.id, in: tasks),
                    placeholder: placeholder(for: list),
                    isSelected: focusedItem == focus,
                    isChecked: false,
                    checkIcon: list == .habits ? "checkmark.square.fill" : "checkmark.circle.fill",
                    uncheckedIcon: list == .habits ? "square" : "circle",
                    onToggle: nil,
                    renameFocus: $renameItem,
                    focusID: focus
                ) {
                    Button("Rename") { renameItem = focus }
                    Button(role: .destructive) { remove(task.id, from: tasks) } label: { Text("Delete") }
                }
                .focusable()
                .focused($focusedItem, equals: focus)
                .onTapGesture { focusedItem = focus }
                .onDrag {
                    draggedItem = focus
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                .onDrop(of: [UTType.text.identifier], delegate: TemplateTaskDropDelegate(target: focus, dragged: $draggedItem, tasks: tasks))
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
    }

    private func placeholder(for list: TemplateListKind) -> String {
        switch list {
        case .habits: "Habit"
        case .thisWeek: "This Week item"
        case .day: "Task"
        }
    }

    private func titleBinding(for id: UUID, in tasks: Binding<[TodoTask]>) -> Binding<String> {
        Binding(
            get: { tasks.wrappedValue.first(where: { $0.id == id })?.title ?? "" },
            set: { value in
                guard let index = tasks.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                tasks.wrappedValue[index].title = value
            }
        )
    }

    private func createItem(in list: TemplateListKind) {
        let item = TodoTask(title: "")
        switch list {
        case .habits:
            draft.dailyHabits.append(item)
        case .thisWeek:
            draft.thisWeekTasks.append(item)
        case .day(let day):
            guard let index = draft.days.firstIndex(where: { $0.weekday == day }) else { return }
            draft.days[index].tasks.append(item)
        }
        let focus = TemplateItemFocus(list: list, id: item.id)
        focusedItem = focus
        DispatchQueue.main.async { renameItem = focus }
    }

    private func saveAndClose() {
        store.updateTemplate(draft)
        onClose()
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        guard let focusedItem else {
            self.focusedItem = focusOrder().first
            return
        }
        switch direction {
        case .up: moveFocusVertically(from: focusedItem, offset: -1)
        case .down: moveFocusVertically(from: focusedItem, offset: 1)
        case .left: moveFocusHorizontally(toRightColumn: false)
        case .right: moveFocusHorizontally(toRightColumn: true)
        @unknown default: break
        }
    }

    private func moveFocusVertically(from current: TemplateItemFocus, offset: Int) {
        let items = column(containing: current)
        guard let index = items.firstIndex(of: current), !items.isEmpty else { return }
        focusedItem = items[max(0, min(index + offset, items.count - 1))]
    }

    private func moveFocusHorizontally(toRightColumn: Bool) {
        let target = toRightColumn ? rightColumnOrder() : leftColumnOrder()
        guard !target.isEmpty else { return }
        focusedItem = target.first
    }

    private func deleteFocusedItem() {
        guard let focusedItem else { return }
        switch focusedItem.list {
        case .habits: remove(focusedItem.id, from: $draft.dailyHabits)
        case .thisWeek: remove(focusedItem.id, from: $draft.thisWeekTasks)
        case .day(let day):
            guard let index = draft.days.firstIndex(where: { $0.weekday == day }) else { return }
            remove(focusedItem.id, from: $draft.days[index].tasks)
        }
        self.focusedItem = focusOrder().first
    }

    private func moveFocusedItem(offset: Int) {
        guard let focusedItem else { return }
        switch focusedItem.list {
        case .habits: move(focusedItem.id, offset: offset, in: &draft.dailyHabits)
        case .thisWeek: move(focusedItem.id, offset: offset, in: &draft.thisWeekTasks)
        case .day(let day):
            guard let index = draft.days.firstIndex(where: { $0.weekday == day }) else { return }
            move(focusedItem.id, offset: offset, in: &draft.days[index].tasks)
        }
    }

    private func remove(_ id: UUID, from tasks: Binding<[TodoTask]>) {
        tasks.wrappedValue.removeAll { $0.id == id }
    }

    private func move(_ id: UUID, offset: Int, in tasks: inout [TodoTask]) {
        guard let source = tasks.firstIndex(where: { $0.id == id }) else { return }
        let target = max(0, min(source + offset, tasks.count - 1))
        guard source != target else { return }
        let item = tasks.remove(at: source)
        tasks.insert(item, at: target)
    }

    private func focusOrder() -> [TemplateItemFocus] { leftColumnOrder() + rightColumnOrder() }

    private func leftColumnOrder() -> [TemplateItemFocus] {
        draft.dailyHabits.map { TemplateItemFocus(list: .habits, id: $0.id) } +
        draft.thisWeekTasks.map { TemplateItemFocus(list: .thisWeek, id: $0.id) }
    }

    private func rightColumnOrder() -> [TemplateItemFocus] {
        guard let index = draft.days.firstIndex(where: { $0.weekday == selectedDay }) else { return [] }
        return draft.days[index].tasks.map { TemplateItemFocus(list: .day(selectedDay), id: $0.id) }
    }

    private func column(containing item: TemplateItemFocus) -> [TemplateItemFocus] {
        switch item.list {
        case .habits, .thisWeek: leftColumnOrder()
        case .day: rightColumnOrder()
        }
    }
}

enum TemplateListKind: Hashable {
    case habits
    case thisWeek
    case day(Weekday)
}

struct TemplateItemFocus: Hashable {
    let list: TemplateListKind
    let id: UUID
}

private struct TemplateTaskDropDelegate: DropDelegate {
    let target: TemplateItemFocus
    @Binding var dragged: TemplateItemFocus?
    var tasks: Binding<[TodoTask]>

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged.list == target.list, dragged.id != target.id,
              let source = tasks.wrappedValue.firstIndex(where: { $0.id == dragged.id }),
              let destination = tasks.wrappedValue.firstIndex(where: { $0.id == target.id }) else { return }
        let item = tasks.wrappedValue.remove(at: source)
        let adjusted = source < destination ? destination - 1 : destination
        tasks.wrappedValue.insert(item, at: max(0, min(adjusted, tasks.wrappedValue.count)))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}
