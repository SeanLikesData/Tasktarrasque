import Foundation

enum TaskItemAddress: Hashable {
    case bigThree(weekID: UUID, index: Int)
    case thisWeek(weekID: UUID, taskID: UUID)
    case habit(weekID: UUID, weekday: Weekday, habitID: UUID)
    case dayTask(weekID: UUID, weekday: Weekday, taskID: UUID)

    var weekID: UUID {
        switch self {
        case .bigThree(let weekID, _),
             .thisWeek(let weekID, _),
             .habit(let weekID, _, _),
             .dayTask(let weekID, _, _):
            weekID
        }
    }

    var isEditable: Bool {
        switch self {
        case .bigThree, .thisWeek, .dayTask:
            true
        case .habit:
            false
        }
    }

    var isDeletable: Bool {
        switch self {
        case .thisWeek, .dayTask:
            true
        case .bigThree, .habit:
            false
        }
    }
}

enum TaskCreationTarget: Hashable {
    case thisWeek(weekID: UUID)
    case dayTask(weekID: UUID, weekday: Weekday)

    var weekID: UUID {
        switch self {
        case .thisWeek(let weekID),
             .dayTask(let weekID, _):
            weekID
        }
    }

    func address(taskID: UUID) -> TaskItemAddress {
        switch self {
        case .thisWeek(let weekID):
            .thisWeek(weekID: weekID, taskID: taskID)
        case .dayTask(let weekID, let weekday):
            .dayTask(weekID: weekID, weekday: weekday, taskID: taskID)
        }
    }
}

struct TaskEditSession: Equatable {
    enum Mode: Equatable {
        case existing
        case new(TaskCreationTarget)
    }

    var target: TaskItemAddress
    var originalTitle: String
    var draftTitle: String
    var mode: Mode
}

enum ActiveSheet: Equatable {
    case settings
    case template
    case shortcuts
}

@MainActor
final class TaskInteractionModel: ObservableObject {
    @Published var selectedItem: TaskItemAddress?
    @Published var editSession: TaskEditSession?
    @Published var activeSheet: ActiveSheet?
    @Published var weekPendingDeletion: WeekPlan?

    var canUseMainShortcuts: Bool {
        activeSheet == nil && weekPendingDeletion == nil && editSession == nil
    }

    func select(_ item: TaskItemAddress) {
        selectedItem = item
    }

    func beginEdit(_ item: TaskItemAddress, currentTitle: String) {
        guard item.isEditable else { return }
        selectedItem = item
        editSession = TaskEditSession(
            target: item,
            originalTitle: currentTitle,
            draftTitle: currentTitle,
            mode: .existing
        )
    }

    func beginNewTask(in target: TaskCreationTarget) {
        let taskID = UUID()
        let address = target.address(taskID: taskID)
        selectedItem = address
        editSession = TaskEditSession(
            target: address,
            originalTitle: "",
            draftTitle: "",
            mode: .new(target)
        )
    }

    func updateDraftTitle(_ title: String) {
        editSession?.draftTitle = title
    }

    func commitEdit(using store: TaskStore) {
        guard let editSession else { return }
        let title = editSession.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        switch editSession.mode {
        case .existing:
            store.updateTitle(for: editSession.target, title: editSession.draftTitle)
            selectedItem = editSession.target
        case .new(let target):
            if !title.isEmpty, let taskID = editSession.target.taskID {
                _ = store.addTask(id: taskID, title: title, to: target)
                selectedItem = editSession.target
            } else {
                selectedItem = nil
            }
        }

        self.editSession = nil
    }

    func cancelEdit() {
        editSession = nil
    }

    func closeTransientState(committingWith store: TaskStore) {
        commitEdit(using: store)
        activeSheet = nil
        weekPendingDeletion = nil
    }

    func validateVisibleItems(_ visibleItems: [TaskItemAddress]) {
        if let editSession, !visibleItems.contains(editSession.target) {
            self.editSession = nil
        }

        guard let selectedItem else {
            self.selectedItem = visibleItems.first
            return
        }

        if !visibleItems.contains(selectedItem) {
            self.selectedItem = visibleItems.first
        }
    }
}

enum TemplateItemAddress: Hashable {
    case habit(UUID)
    case thisWeek(UUID)
    case day(Weekday, UUID)

    var isDayItem: Bool {
        if case .day = self { return true }
        return false
    }
}

enum TemplateCreationTarget: Hashable {
    case habit
    case thisWeek
    case day(Weekday)

    func address(taskID: UUID) -> TemplateItemAddress {
        switch self {
        case .habit:
            .habit(taskID)
        case .thisWeek:
            .thisWeek(taskID)
        case .day(let weekday):
            .day(weekday, taskID)
        }
    }
}

struct TemplateEditSession: Equatable {
    enum Mode: Equatable {
        case existing
        case new(TemplateCreationTarget)
    }

    var target: TemplateItemAddress
    var originalTitle: String
    var draftTitle: String
    var mode: Mode
}

@MainActor
final class TemplateInteractionModel: ObservableObject {
    @Published var selectedItem: TemplateItemAddress?
    @Published var editSession: TemplateEditSession?

    var canUseShortcuts: Bool { editSession == nil }

    func select(_ item: TemplateItemAddress) {
        selectedItem = item
    }

    func beginEdit(_ item: TemplateItemAddress, currentTitle: String) {
        selectedItem = item
        editSession = TemplateEditSession(
            target: item,
            originalTitle: currentTitle,
            draftTitle: currentTitle,
            mode: .existing
        )
    }

    func beginNewItem(in target: TemplateCreationTarget) {
        let taskID = UUID()
        let address = target.address(taskID: taskID)
        selectedItem = address
        editSession = TemplateEditSession(
            target: address,
            originalTitle: "",
            draftTitle: "",
            mode: .new(target)
        )
    }

    func updateDraftTitle(_ title: String) {
        editSession?.draftTitle = title
    }

    func cancelEdit() {
        editSession = nil
    }

    func validateVisibleItems(_ visibleItems: [TemplateItemAddress]) {
        if let editSession, !visibleItems.contains(editSession.target) {
            self.editSession = nil
        }

        guard let selectedItem else {
            self.selectedItem = visibleItems.first
            return
        }

        if !visibleItems.contains(selectedItem) {
            self.selectedItem = visibleItems.first
        }
    }
}

extension TaskItemAddress {
    fileprivate var taskID: UUID? {
        switch self {
        case .thisWeek(_, let taskID),
             .dayTask(_, _, let taskID):
            taskID
        case .habit(_, _, let habitID):
            habitID
        case .bigThree:
            nil
        }
    }
}
