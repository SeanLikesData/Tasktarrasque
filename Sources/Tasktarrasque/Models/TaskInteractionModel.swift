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

enum TemplateItemAddress: Hashable {
    case habit(UUID)
    case thisWeek(UUID)
    case day(Weekday, UUID)

    var isDayItem: Bool {
        if case .day = self { return true }
        return false
    }
}

enum TemplateListKind: Hashable {
    case habits
    case thisWeek
    case day(Weekday)
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

extension TaskItemAddress {
    var taskID: UUID? {
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

extension TemplateItemAddress {
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
