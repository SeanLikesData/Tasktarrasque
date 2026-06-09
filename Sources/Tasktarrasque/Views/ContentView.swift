import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.default.rawValue
    @State private var showingSettings = false
    @State private var showingTemplate = false
    @State private var showingShortcuts = false
    @State private var weekPendingDeletion: WeekPlan?
    @State private var draggedThisWeekTaskID: UUID?
    @State private var draggedDayTaskID: UUID?
    @FocusState private var focusedTask: FocusedTask?
    @FocusState private var focusedRenameField: FocusedTask?

    private var popoverSize: CGSize { (PopoverSize(rawValue: popoverRaw) ?? .default).dimensions }

    /// True while any sheet is showing. The main-view key handlers below
    /// short-circuit in that case so shortcuts do not act on the hidden main
    /// view while the user is in a sheet.
    private var isSheetOpen: Bool { showingSettings || showingTemplate || showingShortcuts || weekPendingDeletion != nil }
    private var canUseMainShortcuts: Bool { !isSheetOpen && focusedRenameField == nil }

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
                    onTemplate: { showingTemplate = true },
                    onShortcuts: { showingShortcuts = true },
                    onSettings: { showingSettings = true }
                )
            }
            .onMoveCommand { direction in
                guard canUseMainShortcuts else { return }
                moveFocus(direction)
            }
            .onDeleteCommand {
                guard canUseMainShortcuts else { return }
                deleteFocusedTask()
            }
            .onKeyPress(.return) {
                guard !isSheetOpen else { return .ignored }
                if focusedRenameField != nil {
                    focusedRenameField = nil
                } else {
                    beginRenamingFocusedTask()
                }
                return .handled
            }
            .onKeyPress("d") {
                guard canUseMainShortcuts else { return .ignored }
                toggleFocusedTask()
                return .handled
            }
            .onExitCommand {
                if weekPendingDeletion != nil {
                    weekPendingDeletion = nil
                } else if showingTemplate {
                    showingTemplate = false
                } else if showingShortcuts {
                    showingShortcuts = false
                } else if showingSettings {
                    showingSettings = false
                } else {
                    focusedRenameField = nil
                }
            }
            .onKeyPress("n") {
                guard canUseMainShortcuts else { return .ignored }
                createTask(in: .day(store.selectedDay))
                return .handled
            }
            .onKeyPress("w") {
                guard canUseMainShortcuts else { return .ignored }
                createTask(in: .thisWeek)
                return .handled
            }
            .onKeyPress("?") {
                guard canUseMainShortcuts else { return .ignored }
                showingShortcuts = true
                return .handled
            }
            .onKeyPress(keys: [.upArrow]) { press in
                guard canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveFocusedTaskByKeyboard(offset: -1)
                return .handled
            }
            .onKeyPress(keys: [.downArrow]) { press in
                guard canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveFocusedTaskByKeyboard(offset: 1)
                return .handled
            }
            .onKeyPress(keys: [.leftArrow]) { press in
                guard canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveFocusedTaskSideways(toDay: false)
                return .handled
            }
            .onKeyPress(keys: [.rightArrow]) { press in
                guard canUseMainShortcuts, press.modifiers.contains(.shift) else { return .ignored }
                moveFocusedTaskSideways(toDay: true)
                return .handled
            }
            .onKeyPress("r") {
                guard canUseMainShortcuts else { return .ignored }
                beginRenamingFocusedTask()
                return .handled
            }
            if showingSettings { SettingsSheet(onClose: { showingSettings = false }).zIndex(2) }
            if showingTemplate { TemplateSheet(onClose: { showingTemplate = false }).environmentObject(store).zIndex(2) }
            if showingShortcuts { KeyboardShortcutsSheet(onClose: { showingShortcuts = false }).zIndex(2) }
            if let week = weekPendingDeletion { deleteWeekConfirmation(week).zIndex(3) }
            if let persistenceError = store.persistenceError { errorBanner(persistenceError) }
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .tasktarrasquePopoverWillClose)) { _ in
            showingSettings = false
            showingTemplate = false
            showingShortcuts = false
            weekPendingDeletion = nil
            focusedRenameField = nil
        }
        .onChange(of: store.selectedWeekID) { _, _ in validateFocusAfterSelectionChange() }
        .onChange(of: store.selectedDay) { _, _ in validateFocusAfterSelectionChange() }
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
            Button { weekPendingDeletion = store.selectedWeek } label: {
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
                Button { store.selectedDay = day } label: {
                    HStack(spacing: 5) {
                        Text(day.shortName)
                        Spacer(minLength: 2)
                        Label("\(plan?.completedCount ?? 0)", systemImage: "checkmark.circle.fill")
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
                .accessibilityLabel("\(day.rawValue), \(plan?.completedCount ?? 0) done")
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
                    SharedSectionHeader(title: "This Week", shortcut: "W") { createTask(in: .thisWeek) }
                    bigThree
                    VStack(spacing: 8) {
                        ForEach(store.selectedWeek?.thisWeekTasks ?? []) { task in
                            SharedTaskCard(
                                title: Binding(
                                    get: { task.title },
                                    set: { store.updateThisWeekTaskTitle(task.id, title: $0) }
                                ),
                                placeholder: "Task",
                                isSelected: focusedTask == .thisWeek(task.id),
                                isChecked: false,
                                checkIcon: "checkmark.circle.fill",
                                uncheckedIcon: "circle",
                                onToggle: nil,
                                renameFocus: $focusedRenameField,
                                focusID: .thisWeek(task.id)
                            ) {
                                ForEach(Weekday.allCases) { day in Button("Move to \(day.rawValue)") { store.moveThisWeekTask(task.id, to: day) } }
                                Divider()
                                Button("Push to Next Week") { store.pushThisWeekTaskToNextWeek(task.id) }
                                Button(role: .destructive) { store.deleteThisWeekTask(task.id) } label: { Text("Delete") }
                            }
                            .focusable()
                            .focused($focusedTask, equals: .thisWeek(task.id))
                            .onTapGesture { focusedTask = .thisWeek(task.id) }
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
                    SharedSectionHeader(title: "Tasks", shortcut: "N") { createTask(in: .day(store.selectedDay)) }
                    if let habits = store.selectedDayPlan?.habits, !habits.isEmpty {
                        habitsView(habits)
                    }
                    ForEach(store.selectedDayPlan?.tasks ?? []) { task in
                        SharedTaskCard(
                            title: Binding(
                                get: { task.title },
                                set: { store.updateDayTaskTitle(task.id, title: $0) }
                            ),
                            placeholder: "Task",
                            isSelected: focusedTask == .day(task.id),
                            isChecked: task.isDone,
                            checkIcon: "checkmark.circle.fill",
                            uncheckedIcon: "circle",
                            onToggle: { store.toggleDayTask(task.id) },
                            renameFocus: $focusedRenameField,
                            focusID: .day(task.id)
                        ) {
                            Button(role: .destructive) { store.deleteDayTask(task.id) } label: { Text("Delete") }
                        }
                        .focusable()
                        .focused($focusedTask, equals: .day(task.id))
                        .onTapGesture { focusedTask = .day(task.id) }
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
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
                .padding(12)
            }
            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                handleThisWeekDrop(providers)
            }
        }
    }

    private func habitsView(_ habits: [TodoTask]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(habits) { habit in
                    Button { store.toggleHabit(habit.id) } label: {
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
                    .focusable()
                    .focused($focusedTask, equals: .habit(habit.id))
                }
            }
        }
    }

    private var bigThree: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Big Three").font(.system(size: 13, weight: .bold)).opacity(0.85)
            ForEach(0..<3, id: \.self) { index in
                let task = store.selectedWeek?.bigThree[safe: index]
                HStack(spacing: 7) {
                    Button { store.toggleBigThree(index: index) } label: {
                        Image(systemName: task?.isDone == true ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task?.isDone == true ? "Mark not done" : "Mark done")
                    Group {
                        if focusedRenameField == .bigThree(index) {
                            TextField("Big task \(index + 1)", text: Binding(get: { store.selectedWeek?.bigThree[safe: index]?.title ?? "" }, set: { store.updateBigThree(index: index, title: $0) }))
                                .textFieldStyle(.plain)
                                .focused($focusedRenameField, equals: .bigThree(index))
                                .onSubmit { focusedRenameField = nil }
                        } else {
                            Text((task?.title.isEmpty == false ? task?.title : "Big task \(index + 1)") ?? "Big task \(index + 1)")
                                .foregroundStyle(task?.title.isEmpty == false ? .primary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .strikethrough(task?.isDone == true)
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 8).fill(focusedTask == .bigThree(index) ? TasktarrasqueStyle.activeControlBackground : TasktarrasqueStyle.editorBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(focusedTask == .bigThree(index) ? TasktarrasqueStyle.activeControlStroke : Color.clear))
                .focusable()
                .focused($focusedTask, equals: .bigThree(index))
                .onTapGesture { focusedTask = .bigThree(index) }
            }
        }
    }

    private func createTask(in target: TaskTarget) {
        guard let task = store.addTask(to: target) else { return }
        let focus: FocusedTask
        switch target {
        case .thisWeek:
            focus = .thisWeek(task.id)
        case .day:
            focus = .day(task.id)
        }
        focusedTask = focus
        DispatchQueue.main.async {
            focusedRenameField = focus
        }
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

    private func moveFocus(_ direction: MoveCommandDirection) {
        guard let focusedTask else {
            self.focusedTask = focusOrder().first
            return
        }

        switch direction {
        case .up:
            moveFocusVertically(from: focusedTask, offset: -1)
        case .down:
            moveFocusVertically(from: focusedTask, offset: 1)
        case .left:
            moveFocusHorizontally(from: focusedTask, toRightColumn: false)
        case .right:
            moveFocusHorizontally(from: focusedTask, toRightColumn: true)
        @unknown default:
            break
        }
    }

    private func moveFocusVertically(from current: FocusedTask, offset: Int) {
        let items = focusColumn(containing: current)
        guard !items.isEmpty, let index = items.firstIndex(of: current) else { return }
        focusedTask = items[max(0, min(index + offset, items.count - 1))]
    }

    private func moveFocusHorizontally(from current: FocusedTask, toRightColumn: Bool) {
        let source = focusColumn(containing: current)
        let target = toRightColumn ? rightColumnFocusOrder() : leftColumnFocusOrder()
        guard !target.isEmpty else { return }
        let sourceIndex = source.firstIndex(of: current) ?? 0
        focusedTask = target[min(sourceIndex, target.count - 1)]
    }

    private func focusColumn(containing item: FocusedTask) -> [FocusedTask] {
        switch item {
        case .bigThree, .thisWeek:
            leftColumnFocusOrder()
        case .habit, .day:
            rightColumnFocusOrder()
        }
    }

    private func deleteFocusedTask() {
        guard let focusedTask else { return }
        // Choose the neighbor to focus before the list shrinks, so focus lands
        // on an adjacent task rather than jumping to the top of the panel.
        let nextFocus = neighborFocus(of: focusedTask)
        switch focusedTask {
        case .thisWeek(let id): store.deleteThisWeekTask(id)
        case .day(let id): store.deleteDayTask(id)
        case .habit, .bigThree: return
        }
        self.focusedTask = nextFocus ?? focusOrder().first
    }

    /// The item that should receive focus after `item` is deleted: the next
    /// item in the same column, or the previous one if it was last.
    private func neighborFocus(of item: FocusedTask) -> FocusedTask? {
        let column = focusColumn(containing: item)
        guard let index = column.firstIndex(of: item) else { return nil }
        if index + 1 < column.count { return column[index + 1] }
        if index - 1 >= 0 { return column[index - 1] }
        return nil
    }

    /// Enters rename mode only for items that have an editable text field.
    /// Habits are toggle-only and have no rename field, so renaming them would
    /// leave an invisible, dead rename state.
    private func beginRenamingFocusedTask() {
        guard let focusedTask else { return }
        switch focusedTask {
        case .thisWeek, .day, .bigThree:
            focusedRenameField = focusedTask
        case .habit:
            return
        }
    }

    private func toggleFocusedTask() {
        guard let focusedTask else { return }
        switch focusedTask {
        case .day(let id): store.toggleDayTask(id)
        case .habit(let id): store.toggleHabit(id)
        case .bigThree(let index): store.toggleBigThree(index: index)
        case .thisWeek: return
        }
    }

    private func moveFocusedTaskByKeyboard(offset: Int) {
        guard let focusedTask else { return }
        switch focusedTask {
        case .thisWeek(let id): store.moveThisWeekTaskByKeyboard(id, offset: offset)
        case .day(let id): store.moveDayTaskByKeyboard(id, offset: offset)
        case .habit, .bigThree: return
        }
    }

    private func moveFocusedTaskSideways(toDay: Bool) {
        guard let focusedTask else { return }
        switch (focusedTask, toDay) {
        case (.thisWeek(let id), true):
            store.moveThisWeekTask(id, to: store.selectedDay)
            refocusAfterMove(.day(id))
        case (.day(let id), false):
            store.moveDayTaskToThisWeek(id)
            refocusAfterMove(.thisWeek(id))
        default:
            return
        }
    }

    private func refocusAfterMove(_ target: FocusedTask) {
        focusedRenameField = nil
        focusedTask = nil
        DispatchQueue.main.async {
            focusedTask = target
        }
    }

    private func focusOrder() -> [FocusedTask] {
        leftColumnFocusOrder() + rightColumnFocusOrder()
    }

    private func validateFocusAfterSelectionChange() {
        focusedRenameField = nil
        guard let focusedTask else { return }
        if !focusOrder().contains(focusedTask) {
            self.focusedTask = focusOrder().first
        }
    }

    private func leftColumnFocusOrder() -> [FocusedTask] {
        let bigThree = [0, 1, 2].map { FocusedTask.bigThree($0) }
        let thisWeek = (store.selectedWeek?.thisWeekTasks ?? []).map { FocusedTask.thisWeek($0.id) }
        return bigThree + thisWeek
    }

    private func rightColumnFocusOrder() -> [FocusedTask] {
        let habits = (store.selectedDayPlan?.habits ?? []).map { FocusedTask.habit($0.id) }
        let day = (store.selectedDayPlan?.tasks ?? []).map { FocusedTask.day($0.id) }
        return habits + day
    }

    private func deleteWeekConfirmation(_ week: WeekPlan) -> some View {
        let taskCount = week.days.reduce(0) { $0 + $1.tasks.count } + week.thisWeekTasks.count
        return ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { weekPendingDeletion = nil }
            VStack(alignment: .leading, spacing: 14) {
                Text("Delete this week?")
                    .font(.system(size: 17, weight: .bold))
                Text("\(week.title) and its \(taskCount) task\(taskCount == 1 ? "" : "s") will be permanently deleted. This cannot be undone.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { weekPendingDeletion = nil }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .glassPill(cornerRadius: 8)
                    Button("Delete Week") {
                        store.deleteWeek(week.id)
                        weekPendingDeletion = nil
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

    private func errorBanner(_ text: String) -> some View { VStack { Text(text).font(.system(size: 11)).padding(8).background(Color.red.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).padding(10); Spacer() } }
}

enum FocusedTask: Hashable {
    case bigThree(Int)
    case thisWeek(UUID)
    case habit(UUID)
    case day(UUID)
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
