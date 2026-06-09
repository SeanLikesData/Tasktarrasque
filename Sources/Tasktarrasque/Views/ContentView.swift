import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.default.rawValue
    @StateObject private var interaction = TaskInteractionModel()
    @State private var draggedThisWeekTaskID: UUID?
    @State private var draggedDayTaskID: UUID?

    private var popoverSize: CGSize { (PopoverSize(rawValue: popoverRaw) ?? .default).dimensions }

    private var isSheetOpen: Bool { interaction.activeSheet != nil || interaction.weekPendingDeletion != nil }

    var body: some View {
        ZStack {
            TasktarrasqueStyle.panelMaterial
            VStack(spacing: 0) {
                header
                TasktarrasqueStyle.divider
                weekTabs
                TasktarrasqueStyle.divider
                mainBody
                TasktarrasqueStyle.divider
                BottomBar(
                    onTemplate: { interaction.activeSheet = .template },
                    onShortcuts: { interaction.activeSheet = .shortcuts },
                    onSettings: { interaction.activeSheet = .settings }
                )
            }
            .onMoveCommand { direction in
                guard interaction.canUseMainShortcuts else { return }
                moveSelection(direction)
            }
            .onDeleteCommand {
                guard interaction.canUseMainShortcuts else { return }
                deleteSelectedItem()
            }
            .onKeyPress(.return) {
                guard !isSheetOpen else { return .ignored }
                if interaction.editSession != nil {
                    interaction.commitEdit(using: store)
                } else {
                    beginRenamingSelectedItem()
                }
                return .handled
            }
            .onKeyPress("d") {
                guard interaction.canUseMainShortcuts else { return .ignored }
                toggleSelectedItem()
                return .handled
            }
            .onExitCommand {
                if interaction.weekPendingDeletion != nil {
                    interaction.weekPendingDeletion = nil
                } else if interaction.activeSheet != nil {
                    interaction.activeSheet = nil
                } else if interaction.editSession != nil {
                    interaction.cancelEdit()
                } else {
                    interaction.selectedItem = nil
                }
            }
            .onKeyPress("n") {
                guard interaction.canUseMainShortcuts else { return .ignored }
                createTaskInSelectedDay()
                return .handled
            }
            .onKeyPress("w") {
                guard interaction.canUseMainShortcuts else { return .ignored }
                createThisWeekTask()
                return .handled
            }
            .onKeyPress("?") {
                guard interaction.canUseMainShortcuts else { return .ignored }
                interaction.activeSheet = .shortcuts
                return .handled
            }
            .onKeyPress(keys: [.upArrow]) { press in
                guard interaction.canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveSelectedItemByKeyboard(offset: -1)
                return .handled
            }
            .onKeyPress(keys: [.downArrow]) { press in
                guard interaction.canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveSelectedItemByKeyboard(offset: 1)
                return .handled
            }
            .onKeyPress(keys: [.leftArrow]) { press in
                guard interaction.canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveSelectedItemSideways(toDay: false)
                return .handled
            }
            .onKeyPress(keys: [.rightArrow]) { press in
                guard interaction.canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveSelectedItemSideways(toDay: true)
                return .handled
            }
            .onKeyPress("r") {
                guard interaction.canUseMainShortcuts else { return .ignored }
                beginRenamingSelectedItem()
                return .handled
            }
            if interaction.activeSheet == .settings { SettingsSheet(onClose: { interaction.activeSheet = nil }).zIndex(2) }
            if interaction.activeSheet == .template { TemplateSheet(onClose: { interaction.activeSheet = nil }).environmentObject(store).zIndex(2) }
            if interaction.activeSheet == .shortcuts { KeyboardShortcutsSheet(onClose: { interaction.activeSheet = nil }).zIndex(2) }
            if let week = interaction.weekPendingDeletion { deleteWeekConfirmation(week).zIndex(3) }
            if let persistenceError = store.persistenceError { errorBanner(persistenceError) }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .tasktarrasquePopoverWillClose)) { _ in
            interaction.closeTransientState(committingWith: store)
        }
        .onChange(of: store.selectedWeekID) { _, _ in validateSelectionAfterScopeChange() }
        .onChange(of: store.selectedDay) { _, _ in validateSelectionAfterScopeChange() }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: TasktarrasqueStyle.panelCornerRadius, style: .continuous))
        .overlay(TasktarrasqueStyle.panelBorder)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Week", selection: Binding(get: { store.selectedWeekID ?? store.weeks.first?.id ?? UUID() }, set: { store.selectWeek($0) })) {
                ForEach(store.weeks) { week in Text(week.pickerTitle).tag(week.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 270)
            Button { store.createNewWeek() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("New Week")
                }
            }
            .buttonStyle(.plain)
            .glassPill(cornerRadius: 8)
            .help("Create the next week")
            .accessibilityLabel("Create new week")
            Button { interaction.weekPendingDeletion = store.selectedWeek } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .glassPill(cornerRadius: 8)
            .help("Delete the selected week")
            .accessibilityLabel("Delete selected week")
            .disabled(store.selectedWeek == nil)
            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
        .padding(10)
    }

    private var weekTabs: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let plan = store.selectedWeek?.days.first { $0.weekday == day }
                let score = plan?.scoreText ?? "0/0"
                Button { store.selectedDay = day } label: {
                    HStack(spacing: 5) {
                        Text(day.shortName)
                        Spacer(minLength: 2)
                        Label(score, systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.82)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(store.selectedDay == day ? TasktarrasqueStyle.activeControlBackground : TasktarrasqueStyle.controlBackground.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(store.selectedDay == day ? TasktarrasqueStyle.activeControlStroke : TasktarrasqueStyle.controlStroke))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.rawValue), \(score) complete")
                .accessibilityAddTraits(store.selectedDay == day ? [.isSelected, .isButton] : .isButton)
            }
        }.padding(10)
    }

    private var mainBody: some View {
        HStack(spacing: 0) {
            thisWeekPanel.frame(width: 300)
            TasktarrasqueStyle.verticalDivider
            dayPanel
        }
    }

    private var thisWeekPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SharedSectionHeader(title: "This Week", shortcut: "W") { createThisWeekTask() }
                    bigThree
                    VStack(spacing: 8) {
                        if let week = store.selectedWeek {
                            ForEach(week.thisWeekTasks) { task in
                                let address = TaskItemAddress.thisWeek(weekID: week.id, taskID: task.id)
                                taskCard(
                                    address: address,
                                    title: task.title,
                                    isChecked: false,
                                    onToggle: nil
                                ) {
                                    ForEach(Weekday.allCases) { day in
                                        Button("Move to \(day.rawValue)") {
                                            store.moveThisWeekTask(task.id, to: day)
                                            interaction.select(.dayTask(weekID: week.id, weekday: day, taskID: task.id))
                                        }
                                    }
                                    Divider()
                                    Button("Push to Next Week") {
                                        store.pushThisWeekTaskToNextWeek(task.id)
                                        interaction.validateVisibleItems(selectionOrder())
                                    }
                                    Button(role: .destructive) {
                                        deleteItem(address)
                                    } label: {
                                        Text("Delete")
                                    }
                                }
                                .onDrag {
                                    draggedThisWeekTaskID = task.id
                                    return NSItemProvider(object: task.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text.identifier],
                                    delegate: ThisWeekTaskDropDelegate(
                                        targetTaskID: task.id,
                                        draggedTaskID: $draggedThisWeekTaskID,
                                        store: store
                                    )
                                )
                            }

                            if let pending = pendingNewThisWeekAddress(for: week.id) {
                                taskCard(
                                    address: pending,
                                    title: "",
                                    isChecked: false,
                                    onToggle: nil
                                ) {
                                    Button(role: .destructive) {
                                        interaction.cancelEdit()
                                    } label: {
                                        Text("Cancel")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var dayPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    SharedSectionHeader(title: "Tasks", shortcut: "N") { createTaskInSelectedDay() }
                    if let week = store.selectedWeek,
                       let dayPlan = store.selectedDayPlan,
                       !dayPlan.habits.isEmpty {
                        habitsView(dayPlan.habits, weekID: week.id, weekday: dayPlan.weekday)
                    }
                    if let week = store.selectedWeek, let dayPlan = store.selectedDayPlan {
                        ForEach(dayPlan.tasks) { task in
                            let address = TaskItemAddress.dayTask(weekID: week.id, weekday: dayPlan.weekday, taskID: task.id)
                            taskCard(
                                address: address,
                                title: task.title,
                                isChecked: task.isDone,
                                onToggle: { store.toggleItem(address) }
                            ) {
                                Button(role: .destructive) {
                                    deleteItem(address)
                                } label: {
                                    Text("Delete")
                                }
                            }
                            .onDrag {
                                draggedDayTaskID = task.id
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: DayTaskDropDelegate(
                                    targetTaskID: task.id,
                                    draggedTaskID: $draggedDayTaskID,
                                    draggedThisWeekTaskID: $draggedThisWeekTaskID,
                                    store: store
                                )
                            )
                        }

                        if let pending = pendingNewDayTaskAddress(weekID: week.id, weekday: dayPlan.weekday) {
                            taskCard(
                                address: pending,
                                title: "",
                                isChecked: false,
                                onToggle: nil
                            ) {
                                Button(role: .destructive) {
                                    interaction.cancelEdit()
                                } label: {
                                    Text("Cancel")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
                .padding(12)
            }
            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                handleThisWeekDrop(providers)
            }
        }
    }

    private func habitsView(_ habits: [TodoTask], weekID: UUID, weekday: Weekday) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(habits) { habit in
                    let address = TaskItemAddress.habit(
                        weekID: weekID,
                        weekday: weekday,
                        habitID: habit.id
                    )
                    Button {
                        interaction.select(address)
                        store.toggleItem(address)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: habit.isDone ? "checkmark.square.fill" : "square")
                            Text(habit.title).lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(TasktarrasqueStyle.controlBackground.opacity(0.8)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(habit.title)
                    .accessibilityValue(habit.isDone ? "done" : "not done")
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(interaction.selectedItem == address ? TasktarrasqueStyle.activeControlStroke : Color.clear)
                    )
                }
            }
        }
    }

    private var bigThree: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Big Three").font(.system(size: 13, weight: .bold)).opacity(0.85)
            if let week = store.selectedWeek {
                ForEach(0..<3, id: \.self) { index in
                    let task = week.bigThree[safe: index]
                    let address = TaskItemAddress.bigThree(weekID: week.id, index: index)
                    HStack(spacing: 7) {
                        Button {
                            interaction.select(address)
                            store.toggleItem(address)
                        } label: {
                            Image(systemName: task?.isDone == true ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task?.isDone == true ? "Mark not done" : "Mark done")
                        Group {
                            if interaction.editSession?.target == address {
                                FirstResponderTextField(
                                    text: editTitleBinding(for: address, currentTitle: task?.title ?? ""),
                                    placeholder: "Big task \(index + 1)",
                                    isFirstResponder: true
                                ) {
                                    interaction.commitEdit(using: store)
                                } onCancel: {
                                    interaction.cancelEdit()
                                }
                                .frame(height: 18)
                            } else {
                                Text((task?.title.isEmpty == false ? task?.title : "Big task \(index + 1)") ?? "Big task \(index + 1)")
                                    .foregroundStyle(task?.title.isEmpty == false ? .primary : .secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        beginEditing(address, currentTitle: task?.title ?? "")
                                    }
                                    .onTapGesture(count: 2) {
                                        beginEditing(address, currentTitle: task?.title ?? "")
                                    }
                            }
                        }
                        .strikethrough(task?.isDone == true)
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(interaction.selectedItem == address ? TasktarrasqueStyle.activeControlBackground : TasktarrasqueStyle.editorBackground))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(interaction.selectedItem == address ? TasktarrasqueStyle.activeControlStroke : Color.clear))
                    .onTapGesture { interaction.select(address) }
                }
            }
        }
    }

    private func taskCard<MenuContent: View>(
        address: TaskItemAddress,
        title: String,
        isChecked: Bool,
        onToggle: (() -> Void)?,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) -> some View {
        SharedTaskCard(
            title: editTitleBinding(for: address, currentTitle: title),
            placeholder: "Task",
            isSelected: interaction.selectedItem == address,
            isEditing: interaction.editSession?.target == address,
            isChecked: isChecked,
            checkIcon: "checkmark.circle.fill",
            uncheckedIcon: "circle",
            onToggle: onToggle.map { action in
                {
                    interaction.select(address)
                    action()
                }
            },
            onSelect: { interaction.select(address) },
            onBeginEdit: { beginEditing(address, currentTitle: title) },
            onCommitEdit: { interaction.commitEdit(using: store) },
            onCancelEdit: { interaction.cancelEdit() },
            menu: menu
        )
    }

    private func editTitleBinding(for address: TaskItemAddress, currentTitle: String) -> Binding<String> {
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
                    store.updateTitle(for: address, title: newTitle)
                }
            }
        )
    }

    private func beginEditing(_ address: TaskItemAddress, currentTitle: String) {
        interaction.beginEdit(address, currentTitle: store.title(for: address) ?? currentTitle)
    }

    private func createThisWeekTask() {
        guard let weekID = store.selectedWeek?.id else { return }
        interaction.beginNewTask(in: .thisWeek(weekID: weekID))
    }

    private func createTaskInSelectedDay() {
        guard let weekID = store.selectedWeek?.id else { return }
        interaction.beginNewTask(in: .dayTask(weekID: weekID, weekday: store.selectedDay))
    }

    private func pendingNewThisWeekAddress(for weekID: UUID) -> TaskItemAddress? {
        guard let editSession = interaction.editSession,
              case .new(.thisWeek(let pendingWeekID)) = editSession.mode,
              pendingWeekID == weekID else { return nil }
        return editSession.target
    }

    private func pendingNewDayTaskAddress(weekID: UUID, weekday: Weekday) -> TaskItemAddress? {
        guard let editSession = interaction.editSession,
              case .new(.dayTask(let pendingWeekID, let pendingWeekday)) = editSession.mode,
              pendingWeekID == weekID,
              pendingWeekday == weekday else { return nil }
        return editSession.target
    }

    private func handleThisWeekDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let rawID = object as? String,
                  let taskID = UUID(uuidString: rawID) else { return }
            Task { @MainActor in
                store.moveThisWeekTask(taskID, to: store.selectedDay)
            }
        }
        return true
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
            moveSelectionHorizontally(from: selectedItem, toRightColumn: false)
        case .right:
            moveSelectionHorizontally(from: selectedItem, toRightColumn: true)
        @unknown default:
            break
        }
    }

    private func moveSelectionVertically(from current: TaskItemAddress, offset: Int) {
        let items = selectionColumn(containing: current)
        guard !items.isEmpty, let index = items.firstIndex(of: current) else { return }
        interaction.selectedItem = items[max(0, min(index + offset, items.count - 1))]
    }

    private func moveSelectionHorizontally(from current: TaskItemAddress, toRightColumn: Bool) {
        let source = selectionColumn(containing: current)
        let target = toRightColumn ? rightColumnSelectionOrder() : leftColumnSelectionOrder()
        guard !target.isEmpty else { return }
        let sourceIndex = source.firstIndex(of: current) ?? 0
        interaction.selectedItem = target[min(sourceIndex, target.count - 1)]
    }

    private func selectionColumn(containing item: TaskItemAddress) -> [TaskItemAddress] {
        switch item {
        case .bigThree, .thisWeek:
            leftColumnSelectionOrder()
        case .habit, .dayTask:
            rightColumnSelectionOrder()
        }
    }

    private func deleteSelectedItem() {
        guard let selectedItem = interaction.selectedItem else { return }
        deleteItem(selectedItem)
    }

    private func deleteItem(_ item: TaskItemAddress) {
        let nextSelection = neighborSelection(of: item)
        store.deleteItem(item)
        interaction.selectedItem = nextSelection ?? selectionOrder().first
    }

    /// The item that should be selected after `item` is deleted: the next
    /// item in the same column, or the previous one if it was last.
    private func neighborSelection(of item: TaskItemAddress) -> TaskItemAddress? {
        let column = selectionColumn(containing: item)
        guard let index = column.firstIndex(of: item) else { return nil }
        if index + 1 < column.count { return column[index + 1] }
        if index - 1 >= 0 { return column[index - 1] }
        return nil
    }

    /// Enters rename mode only for items that have an editable text field.
    /// Habits are toggle-only and have no rename field, so renaming them would
    /// leave an invisible, dead rename state.
    private func beginRenamingSelectedItem() {
        guard let selectedItem = interaction.selectedItem,
              let title = store.title(for: selectedItem) else { return }
        interaction.beginEdit(selectedItem, currentTitle: title)
    }

    private func toggleSelectedItem() {
        guard let selectedItem = interaction.selectedItem else { return }
        store.toggleItem(selectedItem)
    }

    private func moveSelectedItemByKeyboard(offset: Int) {
        guard let selectedItem = interaction.selectedItem else { return }
        switch selectedItem {
        case .thisWeek(let weekID, let taskID):
            guard store.selectedWeekID == weekID else { return }
            store.moveThisWeekTaskByKeyboard(taskID, offset: offset)
        case .dayTask(let weekID, let weekday, let taskID):
            guard store.selectedWeekID == weekID, store.selectedDay == weekday else { return }
            store.moveDayTaskByKeyboard(taskID, offset: offset)
        case .habit, .bigThree:
            return
        }
        interaction.validateVisibleItems(selectionOrder())
    }

    private func moveSelectedItemSideways(toDay: Bool) {
        guard let selectedItem = interaction.selectedItem else { return }
        switch (selectedItem, toDay) {
        case (.thisWeek(let weekID, let taskID), true):
            guard store.selectedWeekID == weekID else { return }
            store.moveThisWeekTask(taskID, to: store.selectedDay)
            interaction.select(.dayTask(weekID: weekID, weekday: store.selectedDay, taskID: taskID))
        case (.dayTask(let weekID, let weekday, let taskID), false):
            guard store.selectedWeekID == weekID, store.selectedDay == weekday else { return }
            store.moveDayTaskToThisWeek(taskID)
            interaction.select(.thisWeek(weekID: weekID, taskID: taskID))
        default:
            return
        }
    }

    private func selectionOrder() -> [TaskItemAddress] {
        leftColumnSelectionOrder() + rightColumnSelectionOrder()
    }

    private func validateSelectionAfterScopeChange() {
        interaction.validateVisibleItems(selectionOrder())
    }

    private func leftColumnSelectionOrder() -> [TaskItemAddress] {
        guard let week = store.selectedWeek else { return [] }
        let bigThree = [0, 1, 2].map { TaskItemAddress.bigThree(weekID: week.id, index: $0) }
        var thisWeek = week.thisWeekTasks.map { TaskItemAddress.thisWeek(weekID: week.id, taskID: $0.id) }
        if let pending = pendingNewThisWeekAddress(for: week.id) {
            thisWeek.append(pending)
        }
        return bigThree + thisWeek
    }

    private func rightColumnSelectionOrder() -> [TaskItemAddress] {
        guard let week = store.selectedWeek,
              let dayPlan = store.selectedDayPlan else { return [] }
        let habits = dayPlan.habits.map {
            TaskItemAddress.habit(weekID: week.id, weekday: dayPlan.weekday, habitID: $0.id)
        }
        var day = dayPlan.tasks.map {
            TaskItemAddress.dayTask(weekID: week.id, weekday: dayPlan.weekday, taskID: $0.id)
        }
        if let pending = pendingNewDayTaskAddress(weekID: week.id, weekday: dayPlan.weekday) {
            day.append(pending)
        }
        return habits + day
    }

    private func deleteWeekConfirmation(_ week: WeekPlan) -> some View {
        let taskCount = week.days.reduce(0) { $0 + $1.tasks.count } + week.thisWeekTasks.count
        return ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { interaction.weekPendingDeletion = nil }
            VStack(alignment: .leading, spacing: 14) {
                Text("Delete this week?")
                    .font(.system(size: 17, weight: .bold))
                Text("\(week.title) and its \(taskCount) task\(taskCount == 1 ? "" : "s") will be permanently deleted. This cannot be undone.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { interaction.weekPendingDeletion = nil }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .glassPill(cornerRadius: 8)
                    Button("Delete Week") {
                        store.deleteWeek(week.id)
                        interaction.weekPendingDeletion = nil
                        interaction.validateVisibleItems(selectionOrder())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .foregroundStyle(.red)
                    .glassPill(cornerRadius: 8)
                }
            }
            .padding(18)
            .frame(width: 320)
            .background(TasktarrasqueStyle.panelMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(TasktarrasqueStyle.controlStroke))
        }
    }

    private func errorBanner(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(10)
            Spacer()
        }
        .zIndex(4)
    }
}

private struct ThisWeekTaskDropDelegate: DropDelegate {
    let targetTaskID: UUID
    @Binding var draggedTaskID: UUID?
    let store: TaskStore

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID else { return }
        store.reorderThisWeekTask(draggedTaskID, before: targetTaskID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggedTaskID = nil
        return true
    }
}

private struct DayTaskDropDelegate: DropDelegate {
    let targetTaskID: UUID
    @Binding var draggedTaskID: UUID?
    @Binding var draggedThisWeekTaskID: UUID?
    let store: TaskStore

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID else { return }
        store.reorderDayTask(draggedTaskID, before: targetTaskID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        // A This Week task dropped onto a day task moves into the day and lands
        // at the dropped position rather than silently doing nothing.
        if let thisWeekID = draggedThisWeekTaskID {
            store.moveThisWeekTask(thisWeekID, to: store.selectedDay)
            store.reorderDayTask(thisWeekID, before: targetTaskID)
            draggedThisWeekTaskID = nil
            return true
        }
        draggedTaskID = nil
        return true
    }
}
