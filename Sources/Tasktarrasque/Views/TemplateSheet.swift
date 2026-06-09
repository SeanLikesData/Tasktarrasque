import SwiftUI
import UniformTypeIdentifiers

struct TemplateSheet: View {
    @EnvironmentObject private var store: TaskStore
    let onClose: () -> Void

    @State private var draft = WeeklyTemplate()
    @State private var selectedDay: Weekday = .monday
    @State private var draggedItem: TemplateItemAddress?
    @StateObject private var interaction = TemplateInteractionModel()

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
        .onAppear {
            draft = store.template
            interaction.validateVisibleItems(selectionOrder())
        }
        .onMoveCommand { direction in
            guard interaction.canUseShortcuts else { return }
            moveSelection(direction)
        }
        .onDeleteCommand {
            guard interaction.canUseShortcuts else { return }
            deleteSelectedItem()
        }
        .onKeyPress(.return) {
            if interaction.editSession != nil {
                commitTemplateEdit()
            } else {
                beginEditingSelectedItem()
            }
            return .handled
        }
        .onKeyPress("d") { interaction.canUseShortcuts ? .handled : .ignored }
        .onKeyPress("h") {
            guard interaction.canUseShortcuts else { return .ignored }
            createItem(in: .habits)
            return .handled
        }
        .onKeyPress("w") {
            guard interaction.canUseShortcuts else { return .ignored }
            createItem(in: .thisWeek)
            return .handled
        }
        .onKeyPress("n") {
            guard interaction.canUseShortcuts else { return .ignored }
            createItem(in: .day(selectedDay))
            return .handled
        }
        .onKeyPress("r") {
            guard interaction.canUseShortcuts else { return .ignored }
            beginEditingSelectedItem()
            return .handled
        }
        .onKeyPress(keys: [.upArrow]) { press in
            guard interaction.canUseShortcuts, press.modifiers.contains(.shift) else { return .ignored }
            moveSelectedItem(offset: -1)
            return .handled
        }
        .onKeyPress(keys: [.downArrow]) { press in
            guard interaction.canUseShortcuts, press.modifiers.contains(.shift) else { return .ignored }
            moveSelectedItem(offset: 1)
            return .handled
        }
        .onExitCommand {
            if interaction.editSession != nil {
                interaction.cancelEdit()
            } else {
                onClose()
            }
        }
        .onChange(of: selectedDay) { _, _ in interaction.validateVisibleItems(selectionOrder()) }
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
                let address = address(for: task.id, in: list)
                templateCard(address: address, title: task.title, placeholder: placeholder(for: list), uncheckedIcon: uncheckedIcon(for: list)) {
                    Button(role: .destructive) { remove(address) } label: { Text("Delete") }
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

            if let pending = pendingNewAddress(for: list) {
                templateCard(address: pending, title: "", placeholder: placeholder(for: list), uncheckedIcon: uncheckedIcon(for: list)) {
                    Button(role: .destructive) { interaction.cancelEdit() } label: { Text("Cancel") }
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
            isSelected: interaction.selectedItem == address,
            isEditing: interaction.editSession?.target == address,
            isChecked: false,
            checkIcon: uncheckedIcon,
            uncheckedIcon: uncheckedIcon,
            onToggle: nil,
            onSelect: { interaction.select(address) },
            onBeginEdit: { beginEditing(address, currentTitle: title) },
            onCommitEdit: { commitTemplateEdit() },
            onCancelEdit: { interaction.cancelEdit() },
            menu: menu
        )
    }

    private func editTitleBinding(for address: TemplateItemAddress, currentTitle: String) -> Binding<String> {
        Binding(
            get: {
                if interaction.editSession?.target == address {
                    return interaction.editSession?.draftTitle ?? currentTitle
                }
                return currentTitle
            },
            set: { newTitle in
                if interaction.editSession?.target == address {
                    interaction.updateDraftTitle(newTitle)
                } else {
                    updateTitle(for: address, title: newTitle)
                }
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

    private func creationTarget(for list: TemplateListKind) -> TemplateCreationTarget {
        switch list {
        case .habits:
            .habit
        case .thisWeek:
            .thisWeek
        case .day(let day):
            .day(day)
        }
    }

    private func createItem(in list: TemplateListKind) {
        interaction.beginNewItem(in: creationTarget(for: list))
    }

    private func beginEditing(_ address: TemplateItemAddress, currentTitle: String) {
        interaction.beginEdit(address, currentTitle: title(for: address) ?? currentTitle)
    }

    private func beginEditingSelectedItem() {
        guard let selectedItem = interaction.selectedItem,
              let title = title(for: selectedItem) else { return }
        interaction.beginEdit(selectedItem, currentTitle: title)
    }

    private func pendingNewAddress(for list: TemplateListKind) -> TemplateItemAddress? {
        guard let editSession = interaction.editSession else { return nil }
        switch (editSession.mode, list) {
        case (.new(.habit), .habits),
             (.new(.thisWeek), .thisWeek):
            return editSession.target
        case (.new(.day(let pendingDay)), .day(let listDay)) where pendingDay == listDay:
            return editSession.target
        default:
            return nil
        }
    }

    private func title(for address: TemplateItemAddress) -> String? {
        switch address {
        case .habit(let id):
            draft.dailyHabits.first { $0.id == id }?.title
        case .thisWeek(let id):
            draft.thisWeekTasks.first { $0.id == id }?.title
        case .day(let weekday, let id):
            draft.days.first { $0.weekday == weekday }?.tasks.first { $0.id == id }?.title
        }
    }

    private func updateTitle(for address: TemplateItemAddress, title: String) {
        switch address {
        case .habit(let id):
            guard let index = draft.dailyHabits.firstIndex(where: { $0.id == id }) else { return }
            draft.dailyHabits[index].title = title
        case .thisWeek(let id):
            guard let index = draft.thisWeekTasks.firstIndex(where: { $0.id == id }) else { return }
            draft.thisWeekTasks[index].title = title
        case .day(let weekday, let id):
            guard let dayIndex = draft.days.firstIndex(where: { $0.weekday == weekday }),
                  let taskIndex = draft.days[dayIndex].tasks.firstIndex(where: { $0.id == id }) else { return }
            draft.days[dayIndex].tasks[taskIndex].title = title
        }
    }

    private func appendItem(id: UUID, title: String, to target: TemplateCreationTarget) {
        let item = TodoTask(id: id, title: title)
        switch target {
        case .habit:
            draft.dailyHabits.append(item)
        case .thisWeek:
            draft.thisWeekTasks.append(item)
        case .day(let day):
            guard let index = draft.days.firstIndex(where: { $0.weekday == day }) else { return }
            draft.days[index].tasks.append(item)
        }
    }

    private func commitTemplateEdit() {
        guard let editSession = interaction.editSession else { return }
        let trimmedTitle = editSession.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        switch editSession.mode {
        case .existing:
            updateTitle(for: editSession.target, title: editSession.draftTitle)
        case .new(let target):
            if !trimmedTitle.isEmpty, let id = editSession.target.itemID {
                appendItem(id: id, title: trimmedTitle, to: target)
            }
        }

        interaction.selectedItem = editSession.target
        interaction.editSession = nil
        interaction.validateVisibleItems(selectionOrder())
    }

    private func remove(_ address: TemplateItemAddress) {
        switch address {
        case .habit(let id):
            draft.dailyHabits.removeAll { $0.id == id }
        case .thisWeek(let id):
            draft.thisWeekTasks.removeAll { $0.id == id }
        case .day(let weekday, let id):
            guard let dayIndex = draft.days.firstIndex(where: { $0.weekday == weekday }) else { return }
            draft.days[dayIndex].tasks.removeAll { $0.id == id }
        }
        interaction.validateVisibleItems(selectionOrder())
    }

    private func deleteSelectedItem() {
        guard let selectedItem = interaction.selectedItem else { return }
        if interaction.editSession?.target == selectedItem {
            interaction.cancelEdit()
            return
        }
        remove(selectedItem)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let selectedItem = interaction.selectedItem else {
            interaction.selectedItem = selectionOrder().first
            return
        }

        switch direction {
        case .up:
            moveSelectionVertically(from: selectedItem, offset: -1)
        case .down:
            moveSelectionVertically(from: selectedItem, offset: 1)
        case .left:
            moveSelectionHorizontally(toRightColumn: false)
        case .right:
            moveSelectionHorizontally(toRightColumn: true)
        @unknown default:
            break
        }
    }

    private func moveSelectionVertically(from current: TemplateItemAddress, offset: Int) {
        let items = column(containing: current)
        guard let index = items.firstIndex(of: current), !items.isEmpty else { return }
        interaction.selectedItem = items[max(0, min(index + offset, items.count - 1))]
    }

    private func moveSelectionHorizontally(toRightColumn: Bool) {
        let target = toRightColumn ? rightColumnOrder() : leftColumnOrder()
        guard !target.isEmpty else { return }
        interaction.selectedItem = target.first
    }

    private func moveSelectedItem(offset: Int) {
        guard let selectedItem = interaction.selectedItem else { return }
        switch selectedItem {
        case .habit(let id):
            move(id, offset: offset, in: &draft.dailyHabits)
        case .thisWeek(let id):
            move(id, offset: offset, in: &draft.thisWeekTasks)
        case .day(let day, let id):
            guard let index = draft.days.firstIndex(where: { $0.weekday == day }) else { return }
            move(id, offset: offset, in: &draft.days[index].tasks)
        }
        interaction.validateVisibleItems(selectionOrder())
    }

    private func move(_ id: UUID, offset: Int, in tasks: inout [TodoTask]) {
        guard let source = tasks.firstIndex(where: { $0.id == id }) else { return }
        let target = max(0, min(source + offset, tasks.count - 1))
        guard source != target else { return }
        let item = tasks.remove(at: source)
        tasks.insert(item, at: target)
    }

    private func selectionOrder() -> [TemplateItemAddress] {
        leftColumnOrder() + rightColumnOrder()
    }

    private func leftColumnOrder() -> [TemplateItemAddress] {
        var items = draft.dailyHabits.map { TemplateItemAddress.habit($0.id) } +
            draft.thisWeekTasks.map { TemplateItemAddress.thisWeek($0.id) }
        if let pendingHabit = pendingNewAddress(for: .habits) {
            items.append(pendingHabit)
        }
        if let pendingThisWeek = pendingNewAddress(for: .thisWeek) {
            items.append(pendingThisWeek)
        }
        return items
    }

    private func rightColumnOrder() -> [TemplateItemAddress] {
        guard let index = draft.days.firstIndex(where: { $0.weekday == selectedDay }) else { return [] }
        var items = draft.days[index].tasks.map { TemplateItemAddress.day(selectedDay, $0.id) }
        if let pending = pendingNewAddress(for: .day(selectedDay)) {
            items.append(pending)
        }
        return items
    }

    private func column(containing item: TemplateItemAddress) -> [TemplateItemAddress] {
        switch item {
        case .habit, .thisWeek:
            leftColumnOrder()
        case .day:
            rightColumnOrder()
        }
    }

    private func saveAndClose() {
        commitTemplateEdit()
        store.updateTemplate(draft)
        onClose()
    }
}

enum TemplateListKind: Hashable {
    case habits
    case thisWeek
    case day(Weekday)
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

private extension TemplateItemAddress {
    var itemID: UUID? {
        switch self {
        case .habit(let id),
             .thisWeek(let id),
             .day(_, let id):
            id
        }
    }

    func isSameTemplateList(as other: TemplateItemAddress) -> Bool {
        switch (self, other) {
        case (.habit, .habit),
             (.thisWeek, .thisWeek):
            true
        case (.day(let lhsDay, _), .day(let rhsDay, _)):
            lhsDay == rhsDay
        default:
            false
        }
    }
}
