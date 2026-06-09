import AppKit
import SwiftUI

enum AppRoute: Equatable {
    case main
    case template
    case settings
    case shortcuts
}

enum SelectionDirection {
    case up
    case down
    case left
    case right
}

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var route: AppRoute = .main
    @Published var selectedTaskItem: TaskItemAddress?
    @Published var taskEditSession: TaskEditSession?
    @Published var weekPendingDeletion: WeekPlan?
    @Published var templateDraft: WeeklyTemplate
    @Published var templateSelectedDay: Weekday
    @Published var selectedTemplateItem: TemplateItemAddress?
    @Published var templateEditSession: TemplateEditSession?

    let store: TaskStore

    init(store: TaskStore) {
        self.store = store
        self.templateDraft = store.template
        self.templateSelectedDay = store.selectedDay
        validateMainSelection()
    }

    var canUseMainCommands: Bool {
        route == .main && weekPendingDeletion == nil && taskEditSession == nil
    }

    var canUseTemplateCommands: Bool {
        route == .template && templateEditSession == nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        guard !isEditingTextInKeyWindow else { return false }

        switch event.keyCode {
        case 36:
            return handleReturnKey()
        case 53:
            return handleEscapeKey()
        case 51, 117:
            return handleDeleteKey()
        case 123:
            return handleArrowKey(.left, shifted: event.modifierFlags.contains(.shift))
        case 124:
            return handleArrowKey(.right, shifted: event.modifierFlags.contains(.shift))
        case 125:
            return handleArrowKey(.down, shifted: event.modifierFlags.contains(.shift))
        case 126:
            return handleArrowKey(.up, shifted: event.modifierFlags.contains(.shift))
        default:
            break
        }

        let character = event.charactersIgnoringModifiers?.lowercased()
        let shiftedCharacter = event.characters?.lowercased()
        if shiftedCharacter == "?" || (character == "/" && event.modifierFlags.contains(.shift)) {
            guard route != .template else { return false }
            showShortcuts()
            return true
        }

        switch route {
        case .main:
            guard canUseMainCommands else { return false }
            switch character {
            case "n":
                createTaskInSelectedDay()
                return true
            case "w":
                createThisWeekTask()
                return true
            case "d":
                toggleSelectedTaskItem()
                return true
            case "r":
                beginRenamingSelectedTaskItem()
                return true
            default:
                return false
            }
        case .template:
            guard canUseTemplateCommands else { return false }
            switch character {
            case "h":
                beginNewTemplateItem(in: .habit)
                return true
            case "w":
                beginNewTemplateItem(in: .thisWeek)
                return true
            case "n":
                beginNewTemplateItem(in: .day(templateSelectedDay))
                return true
            case "r":
                beginRenamingSelectedTemplateItem()
                return true
            default:
                return false
            }
        case .settings, .shortcuts:
            return false
        }
    }

    // MARK: - Routes

    func showTemplate() {
        commitTaskEdit()
        weekPendingDeletion = nil
        templateDraft = store.template
        templateSelectedDay = store.selectedDay
        selectedTemplateItem = nil
        templateEditSession = nil
        route = .template
        validateTemplateSelection()
    }

    func saveTemplateAndReturnToMain() {
        commitTemplateEdit()
        store.updateTemplate(templateDraft)
        route = .main
        validateMainSelection()
    }

    func cancelTemplateAndReturnToMain() {
        templateEditSession = nil
        templateDraft = store.template
        route = .main
        validateMainSelection()
    }

    func showSettings() {
        commitTaskEdit()
        weekPendingDeletion = nil
        route = .settings
    }

    func showShortcuts() {
        commitTaskEdit()
        weekPendingDeletion = nil
        route = .shortcuts
    }

    func returnToMain() {
        if route == .template {
            cancelTemplateAndReturnToMain()
        } else {
            route = .main
            validateMainSelection()
        }
    }

    func resetForPopoverClose() {
        commitTaskEdit()
        templateEditSession = nil
        templateDraft = store.template
        weekPendingDeletion = nil
        route = .main
        validateMainSelection()
    }

    // MARK: - Weeks and Days

    func selectWeek(_ id: UUID) {
        store.selectWeek(id)
        validateMainSelection()
    }

    func selectDay(_ day: Weekday) {
        store.selectDay(day)
        validateMainSelection()
    }

    func createNewWeek() {
        store.createNewWeek()
        validateMainSelection()
    }

    func requestDeleteSelectedWeek() {
        weekPendingDeletion = store.selectedWeek
    }

    func cancelWeekDeletion() {
        weekPendingDeletion = nil
    }

    func confirmWeekDeletion() {
        guard let week = weekPendingDeletion else { return }
        store.deleteWeek(week.id)
        weekPendingDeletion = nil
        validateMainSelection()
    }

    // MARK: - Main Tasks

    func selectTaskItem(_ item: TaskItemAddress) {
        selectedTaskItem = item
    }

    func beginTaskEdit(_ item: TaskItemAddress, fallbackTitle: String = "") {
        guard item.isEditable else { return }
        selectedTaskItem = item
        let currentTitle = store.title(for: item) ?? fallbackTitle
        taskEditSession = TaskEditSession(
            target: item,
            originalTitle: currentTitle,
            draftTitle: currentTitle,
            mode: .existing
        )
    }

    func beginRenamingSelectedTaskItem() {
        guard let selectedTaskItem,
              selectedTaskItem.isEditable,
              let title = store.title(for: selectedTaskItem) else { return }
        taskEditSession = TaskEditSession(
            target: selectedTaskItem,
            originalTitle: title,
            draftTitle: title,
            mode: .existing
        )
    }

    func createThisWeekTask() {
        guard let weekID = store.selectedWeek?.id else { return }
        beginNewTask(in: .thisWeek(weekID: weekID))
    }

    func createTaskInSelectedDay() {
        guard let weekID = store.selectedWeek?.id else { return }
        beginNewTask(in: .dayTask(weekID: weekID, weekday: store.selectedDay))
    }

    func updateTaskEditDraft(_ title: String) {
        taskEditSession?.draftTitle = title
    }

    func commitTaskEdit() {
        guard let taskEditSession else { return }
        let title = taskEditSession.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        switch taskEditSession.mode {
        case .existing:
            store.updateTitle(for: taskEditSession.target, title: taskEditSession.draftTitle)
            selectedTaskItem = taskEditSession.target
        case .new(let target):
            if !title.isEmpty, let taskID = taskEditSession.target.taskID {
                _ = store.addTask(id: taskID, title: title, to: target)
                selectedTaskItem = taskEditSession.target
            } else {
                selectedTaskItem = nil
            }
        }

        self.taskEditSession = nil
        validateMainSelection()
    }

    func cancelTaskEdit() {
        taskEditSession = nil
        validateMainSelection()
    }

    func deleteTaskItem(_ item: TaskItemAddress) {
        guard item.isDeletable else { return }
        if taskEditSession?.target == item {
            cancelTaskEdit()
            return
        }
        let nextSelection = neighborSelection(of: item)
        store.deleteItem(item)
        selectedTaskItem = nextSelection ?? mainSelectionOrder().first
    }

    func deleteSelectedTaskItem() {
        guard let selectedTaskItem else { return }
        deleteTaskItem(selectedTaskItem)
    }

    func toggleSelectedTaskItem() {
        guard let selectedTaskItem else { return }
        store.toggleItem(selectedTaskItem)
    }

    func moveSelection(_ direction: SelectionDirection) {
        switch route {
        case .main:
            moveMainSelection(direction)
        case .template:
            moveTemplateSelection(direction)
        case .settings, .shortcuts:
            break
        }
    }

    func moveSelectedItemByKeyboard(offset: Int) {
        switch route {
        case .main:
            moveSelectedTaskByKeyboard(offset: offset)
        case .template:
            moveSelectedTemplateItem(offset: offset)
        case .settings, .shortcuts:
            break
        }
    }

    func moveSelectedTaskSideways(toDay: Bool) {
        guard let selectedTaskItem else { return }
        switch (selectedTaskItem, toDay) {
        case (.thisWeek(let weekID, let taskID), true):
            guard store.selectedWeekID == weekID else { return }
            store.moveThisWeekTask(taskID, to: store.selectedDay)
            selectTaskItem(.dayTask(weekID: weekID, weekday: store.selectedDay, taskID: taskID))
        case (.dayTask(let weekID, let weekday, let taskID), false):
            guard store.selectedWeekID == weekID, store.selectedDay == weekday else { return }
            store.moveDayTaskToThisWeek(taskID)
            selectTaskItem(.thisWeek(weekID: weekID, taskID: taskID))
        default:
            return
        }
        validateMainSelection()
    }

    func pendingNewThisWeekAddress(for weekID: UUID) -> TaskItemAddress? {
        guard let taskEditSession,
              case .new(.thisWeek(let pendingWeekID)) = taskEditSession.mode,
              pendingWeekID == weekID else { return nil }
        return taskEditSession.target
    }

    func pendingNewDayTaskAddress(weekID: UUID, weekday: Weekday) -> TaskItemAddress? {
        guard let taskEditSession,
              case .new(.dayTask(let pendingWeekID, let pendingWeekday)) = taskEditSession.mode,
              pendingWeekID == weekID,
              pendingWeekday == weekday else { return nil }
        return taskEditSession.target
    }

    func validateMainSelection() {
        let visibleItems = mainSelectionOrder()

        if let taskEditSession, !visibleItems.contains(taskEditSession.target) {
            self.taskEditSession = nil
        }

        guard let selectedTaskItem else {
            self.selectedTaskItem = visibleItems.first
            return
        }

        if !visibleItems.contains(selectedTaskItem) {
            self.selectedTaskItem = visibleItems.first
        }
    }

    func mainSelectionOrder() -> [TaskItemAddress] {
        leftColumnSelectionOrder() + rightColumnSelectionOrder()
    }

    // MARK: - Template

    func selectTemplateDay(_ day: Weekday) {
        templateSelectedDay = day
        validateTemplateSelection()
    }

    func selectTemplateItem(_ item: TemplateItemAddress) {
        selectedTemplateItem = item
    }

    func beginTemplateEdit(_ item: TemplateItemAddress, fallbackTitle: String = "") {
        selectedTemplateItem = item
        let currentTitle = templateTitle(for: item) ?? fallbackTitle
        templateEditSession = TemplateEditSession(
            target: item,
            originalTitle: currentTitle,
            draftTitle: currentTitle,
            mode: .existing
        )
    }

    func beginRenamingSelectedTemplateItem() {
        guard let selectedTemplateItem,
              let title = templateTitle(for: selectedTemplateItem) else { return }
        templateEditSession = TemplateEditSession(
            target: selectedTemplateItem,
            originalTitle: title,
            draftTitle: title,
            mode: .existing
        )
    }

    func beginNewTemplateItem(in target: TemplateCreationTarget) {
        let taskID = UUID()
        let address = target.address(taskID: taskID)
        selectedTemplateItem = address
        templateEditSession = TemplateEditSession(
            target: address,
            originalTitle: "",
            draftTitle: "",
            mode: .new(target)
        )
    }

    func updateTemplateEditDraft(_ title: String) {
        templateEditSession?.draftTitle = title
    }

    func commitTemplateEdit() {
        guard let templateEditSession else { return }
        let trimmedTitle = templateEditSession.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        switch templateEditSession.mode {
        case .existing:
            updateTemplateTitle(for: templateEditSession.target, title: templateEditSession.draftTitle)
        case .new(let target):
            if !trimmedTitle.isEmpty, let id = templateEditSession.target.itemID {
                appendTemplateItem(id: id, title: trimmedTitle, to: target)
            }
        }

        selectedTemplateItem = templateEditSession.target
        self.templateEditSession = nil
        validateTemplateSelection()
    }

    func cancelTemplateEdit() {
        templateEditSession = nil
        validateTemplateSelection()
    }

    func removeTemplateItem(_ item: TemplateItemAddress) {
        switch item {
        case .habit(let id):
            templateDraft.dailyHabits.removeAll { $0.id == id }
        case .thisWeek(let id):
            templateDraft.thisWeekTasks.removeAll { $0.id == id }
        case .day(let weekday, let id):
            guard let dayIndex = templateDraft.days.firstIndex(where: { $0.weekday == weekday }) else { return }
            templateDraft.days[dayIndex].tasks.removeAll { $0.id == id }
        }
        validateTemplateSelection()
    }

    func deleteSelectedTemplateItem() {
        guard let selectedTemplateItem else { return }
        if templateEditSession?.target == selectedTemplateItem {
            cancelTemplateEdit()
        } else {
            removeTemplateItem(selectedTemplateItem)
        }
    }

    func moveSelectedTemplateItem(offset: Int) {
        guard let selectedTemplateItem else { return }
        switch selectedTemplateItem {
        case .habit(let id):
            moveTemplateItem(id, offset: offset, in: &templateDraft.dailyHabits)
        case .thisWeek(let id):
            moveTemplateItem(id, offset: offset, in: &templateDraft.thisWeekTasks)
        case .day(let day, let id):
            guard let index = templateDraft.days.firstIndex(where: { $0.weekday == day }) else { return }
            moveTemplateItem(id, offset: offset, in: &templateDraft.days[index].tasks)
        }
        validateTemplateSelection()
    }

    func pendingNewTemplateAddress(for list: TemplateListKind) -> TemplateItemAddress? {
        guard let templateEditSession else { return nil }
        switch (templateEditSession.mode, list) {
        case (.new(.habit), .habits),
             (.new(.thisWeek), .thisWeek):
            return templateEditSession.target
        case (.new(.day(let pendingDay)), .day(let listDay)) where pendingDay == listDay:
            return templateEditSession.target
        default:
            return nil
        }
    }

    func validateTemplateSelection() {
        let visibleItems = templateSelectionOrder()

        if let templateEditSession, !visibleItems.contains(templateEditSession.target) {
            self.templateEditSession = nil
        }

        guard let selectedTemplateItem else {
            self.selectedTemplateItem = visibleItems.first
            return
        }

        if !visibleItems.contains(selectedTemplateItem) {
            self.selectedTemplateItem = visibleItems.first
        }
    }

    func templateSelectionOrder() -> [TemplateItemAddress] {
        templateLeftColumnOrder() + templateRightColumnOrder()
    }

    func templateTitle(for address: TemplateItemAddress) -> String? {
        switch address {
        case .habit(let id):
            templateDraft.dailyHabits.first { $0.id == id }?.title
        case .thisWeek(let id):
            templateDraft.thisWeekTasks.first { $0.id == id }?.title
        case .day(let weekday, let id):
            templateDraft.days.first { $0.weekday == weekday }?.tasks.first { $0.id == id }?.title
        }
    }

    // MARK: - Keyboard Internals

    private func handleReturnKey() -> Bool {
        if weekPendingDeletion != nil {
            confirmWeekDeletion()
            return true
        }

        switch route {
        case .main:
            if taskEditSession != nil {
                commitTaskEdit()
            } else {
                beginRenamingSelectedTaskItem()
            }
            return true
        case .template:
            if templateEditSession != nil {
                commitTemplateEdit()
            } else {
                beginRenamingSelectedTemplateItem()
            }
            return true
        case .settings, .shortcuts:
            return false
        }
    }

    private var isEditingTextInKeyWindow: Bool {
        NSApplication.shared.keyWindow?.firstResponder is NSTextView
    }

    private func handleEscapeKey() -> Bool {
        if weekPendingDeletion != nil {
            cancelWeekDeletion()
            return true
        }

        switch route {
        case .main:
            if taskEditSession != nil {
                cancelTaskEdit()
            } else if selectedTaskItem != nil {
                selectedTaskItem = nil
            } else {
                return false
            }
            return true
        case .template:
            if templateEditSession != nil {
                cancelTemplateEdit()
            } else {
                cancelTemplateAndReturnToMain()
            }
            return true
        case .settings, .shortcuts:
            returnToMain()
            return true
        }
    }

    private func handleDeleteKey() -> Bool {
        if weekPendingDeletion != nil { return false }
        switch route {
        case .main:
            guard canUseMainCommands else { return false }
            deleteSelectedTaskItem()
            return true
        case .template:
            guard canUseTemplateCommands else { return false }
            deleteSelectedTemplateItem()
            return true
        case .settings, .shortcuts:
            return false
        }
    }

    private func handleArrowKey(_ direction: SelectionDirection, shifted: Bool) -> Bool {
        guard weekPendingDeletion == nil else { return false }

        if shifted {
            switch (route, direction) {
            case (.main, .up):
                guard canUseMainCommands else { return false }
                moveSelectedTaskByKeyboard(offset: -1)
                return true
            case (.main, .down):
                guard canUseMainCommands else { return false }
                moveSelectedTaskByKeyboard(offset: 1)
                return true
            case (.main, .left):
                guard canUseMainCommands else { return false }
                moveSelectedTaskSideways(toDay: false)
                return true
            case (.main, .right):
                guard canUseMainCommands else { return false }
                moveSelectedTaskSideways(toDay: true)
                return true
            case (.template, .up):
                guard canUseTemplateCommands else { return false }
                moveSelectedTemplateItem(offset: -1)
                return true
            case (.template, .down):
                guard canUseTemplateCommands else { return false }
                moveSelectedTemplateItem(offset: 1)
                return true
            default:
                return false
            }
        }

        switch route {
        case .main:
            guard canUseMainCommands else { return false }
            moveMainSelection(direction)
            return true
        case .template:
            guard canUseTemplateCommands else { return false }
            moveTemplateSelection(direction)
            return true
        case .settings, .shortcuts:
            return false
        }
    }

    // MARK: - Main Selection Internals

    private func beginNewTask(in target: TaskCreationTarget) {
        let taskID = UUID()
        let address = target.address(taskID: taskID)
        selectedTaskItem = address
        taskEditSession = TaskEditSession(
            target: address,
            originalTitle: "",
            draftTitle: "",
            mode: .new(target)
        )
    }

    private func moveMainSelection(_ direction: SelectionDirection) {
        guard let selectedTaskItem else {
            self.selectedTaskItem = mainSelectionOrder().first
            return
        }

        switch direction {
        case .up:
            moveMainSelectionVertically(from: selectedTaskItem, offset: -1)
        case .down:
            moveMainSelectionVertically(from: selectedTaskItem, offset: 1)
        case .left:
            moveMainSelectionHorizontally(from: selectedTaskItem, toRightColumn: false)
        case .right:
            moveMainSelectionHorizontally(from: selectedTaskItem, toRightColumn: true)
        }
    }

    private func moveMainSelectionVertically(from current: TaskItemAddress, offset: Int) {
        let items = mainSelectionColumn(containing: current)
        guard !items.isEmpty, let index = items.firstIndex(of: current) else { return }
        selectedTaskItem = items[max(0, min(index + offset, items.count - 1))]
    }

    private func moveMainSelectionHorizontally(from current: TaskItemAddress, toRightColumn: Bool) {
        let source = mainSelectionColumn(containing: current)
        let target = toRightColumn ? rightColumnSelectionOrder() : leftColumnSelectionOrder()
        guard !target.isEmpty else { return }
        let sourceIndex = source.firstIndex(of: current) ?? 0
        selectedTaskItem = target[min(sourceIndex, target.count - 1)]
    }

    private func mainSelectionColumn(containing item: TaskItemAddress) -> [TaskItemAddress] {
        switch item {
        case .bigThree, .thisWeek:
            leftColumnSelectionOrder()
        case .habit, .dayTask:
            rightColumnSelectionOrder()
        }
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

    private func neighborSelection(of item: TaskItemAddress) -> TaskItemAddress? {
        let column = mainSelectionColumn(containing: item)
        guard let index = column.firstIndex(of: item) else { return nil }
        if index + 1 < column.count { return column[index + 1] }
        if index - 1 >= 0 { return column[index - 1] }
        return nil
    }

    private func moveSelectedTaskByKeyboard(offset: Int) {
        guard let selectedTaskItem else { return }
        switch selectedTaskItem {
        case .thisWeek(let weekID, let taskID):
            guard store.selectedWeekID == weekID else { return }
            store.moveThisWeekTaskByKeyboard(taskID, offset: offset)
        case .dayTask(let weekID, let weekday, let taskID):
            guard store.selectedWeekID == weekID, store.selectedDay == weekday else { return }
            store.moveDayTaskByKeyboard(taskID, offset: offset)
        case .habit, .bigThree:
            return
        }
        validateMainSelection()
    }

    // MARK: - Template Selection Internals

    private func moveTemplateSelection(_ direction: SelectionDirection) {
        guard let selectedTemplateItem else {
            self.selectedTemplateItem = templateSelectionOrder().first
            return
        }

        switch direction {
        case .up:
            moveTemplateSelectionVertically(from: selectedTemplateItem, offset: -1)
        case .down:
            moveTemplateSelectionVertically(from: selectedTemplateItem, offset: 1)
        case .left:
            moveTemplateSelectionHorizontally(toRightColumn: false)
        case .right:
            moveTemplateSelectionHorizontally(toRightColumn: true)
        }
    }

    private func moveTemplateSelectionVertically(from current: TemplateItemAddress, offset: Int) {
        let items = templateColumn(containing: current)
        guard let index = items.firstIndex(of: current), !items.isEmpty else { return }
        selectedTemplateItem = items[max(0, min(index + offset, items.count - 1))]
    }

    private func moveTemplateSelectionHorizontally(toRightColumn: Bool) {
        let target = toRightColumn ? templateRightColumnOrder() : templateLeftColumnOrder()
        guard !target.isEmpty else { return }
        selectedTemplateItem = target.first
    }

    private func templateColumn(containing item: TemplateItemAddress) -> [TemplateItemAddress] {
        switch item {
        case .habit, .thisWeek:
            templateLeftColumnOrder()
        case .day:
            templateRightColumnOrder()
        }
    }

    private func templateLeftColumnOrder() -> [TemplateItemAddress] {
        var items = templateDraft.dailyHabits.map { TemplateItemAddress.habit($0.id) } +
            templateDraft.thisWeekTasks.map { TemplateItemAddress.thisWeek($0.id) }
        if let pendingHabit = pendingNewTemplateAddress(for: .habits) {
            items.append(pendingHabit)
        }
        if let pendingThisWeek = pendingNewTemplateAddress(for: .thisWeek) {
            items.append(pendingThisWeek)
        }
        return items
    }

    private func templateRightColumnOrder() -> [TemplateItemAddress] {
        guard let index = templateDraft.days.firstIndex(where: { $0.weekday == templateSelectedDay }) else { return [] }
        var items = templateDraft.days[index].tasks.map { TemplateItemAddress.day(templateSelectedDay, $0.id) }
        if let pending = pendingNewTemplateAddress(for: .day(templateSelectedDay)) {
            items.append(pending)
        }
        return items
    }

    func updateTemplateTitle(for address: TemplateItemAddress, title: String) {
        switch address {
        case .habit(let id):
            guard let index = templateDraft.dailyHabits.firstIndex(where: { $0.id == id }) else { return }
            templateDraft.dailyHabits[index].title = title
        case .thisWeek(let id):
            guard let index = templateDraft.thisWeekTasks.firstIndex(where: { $0.id == id }) else { return }
            templateDraft.thisWeekTasks[index].title = title
        case .day(let weekday, let id):
            guard let dayIndex = templateDraft.days.firstIndex(where: { $0.weekday == weekday }),
                  let taskIndex = templateDraft.days[dayIndex].tasks.firstIndex(where: { $0.id == id }) else { return }
            templateDraft.days[dayIndex].tasks[taskIndex].title = title
        }
    }

    private func appendTemplateItem(id: UUID, title: String, to target: TemplateCreationTarget) {
        let item = TodoTask(id: id, title: title)
        switch target {
        case .habit:
            templateDraft.dailyHabits.append(item)
        case .thisWeek:
            templateDraft.thisWeekTasks.append(item)
        case .day(let day):
            guard let index = templateDraft.days.firstIndex(where: { $0.weekday == day }) else { return }
            templateDraft.days[index].tasks.append(item)
        }
    }

    private func moveTemplateItem(_ id: UUID, offset: Int, in tasks: inout [TodoTask]) {
        guard let source = tasks.firstIndex(where: { $0.id == id }) else { return }
        let target = max(0, min(source + offset, tasks.count - 1))
        guard source != target else { return }
        let item = tasks.remove(at: source)
        tasks.insert(item, at: target)
    }
}
