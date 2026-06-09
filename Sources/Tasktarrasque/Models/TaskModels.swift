import Foundation

enum Weekday: String, Codable, CaseIterable, Identifiable {
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case sunday = "Sunday"

    var id: String { rawValue }
    var shortName: String { String(rawValue.prefix(3)) }
}

struct TodoTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

struct DayPlan: Identifiable, Codable, Equatable {
    var weekday: Weekday
    var habits: [TodoTask] = []
    var tasks: [TodoTask] = []
    var id: Weekday { weekday }

    var completedCount: Int { (habits + tasks).filter(\.isDone).count }
    var totalCount: Int { habits.count + tasks.count }
    var scoreText: String { "\(completedCount)/\(totalCount)" }

    init(weekday: Weekday, habits: [TodoTask] = [], tasks: [TodoTask] = []) {
        self.weekday = weekday
        self.habits = habits
        self.tasks = tasks
    }

    enum CodingKeys: String, CodingKey {
        case weekday
        case habits
        case tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try container.decode(Weekday.self, forKey: .weekday)
        habits = try container.decodeIfPresent([TodoTask].self, forKey: .habits) ?? []
        tasks = try container.decodeIfPresent([TodoTask].self, forKey: .tasks) ?? []
    }
}

struct WeekPlan: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startDate: Date
    var thisWeekTasks: [TodoTask] = []
    var bigThree: [TodoTask] = [
        TodoTask(title: ""),
        TodoTask(title: ""),
        TodoTask(title: "")
    ]
    var days: [DayPlan] = Weekday.allCases.map { DayPlan(weekday: $0) }

    init(
        id: UUID = UUID(),
        startDate: Date,
        thisWeekTasks: [TodoTask] = [],
        bigThree: [TodoTask] = [],
        days: [DayPlan] = Weekday.allCases.map { DayPlan(weekday: $0) }
    ) {
        self.id = id
        self.startDate = startDate
        self.thisWeekTasks = thisWeekTasks
        self.bigThree = Self.normalizedBigThree(bigThree)
        self.days = Self.normalizedDays(days)
    }

    /// A Big Three slot counts toward the score only when it has a title.
    /// An empty slot is ignored even if its checkmark was toggled, so the
    /// completed count can never exceed the total count.
    private var scoredBigThree: [TodoTask] {
        bigThree.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var completedCount: Int {
        days.map(\.completedCount).reduce(0, +) + scoredBigThree.filter(\.isDone).count
    }

    var totalCount: Int {
        days.map(\.totalCount).reduce(0, +) + scoredBigThree.count
    }

    var scoreText: String { "\(completedCount)/\(totalCount)" }

    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Week of \(formatter.string(from: startDate))"
    }

    var pickerTitle: String { "\(title)  •  \(scoreText)" }

    enum CodingKeys: String, CodingKey {
        case id
        case startDate
        case thisWeekTasks
        case bigThree
        case days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startDate = try container.decode(Date.self, forKey: .startDate)
        thisWeekTasks = try container.decodeIfPresent([TodoTask].self, forKey: .thisWeekTasks) ?? []
        bigThree = Self.normalizedBigThree(try container.decodeIfPresent([TodoTask].self, forKey: .bigThree) ?? [])
        days = Self.normalizedDays(try container.decodeIfPresent([DayPlan].self, forKey: .days) ?? [])
    }

    private static func normalizedBigThree(_ tasks: [TodoTask]) -> [TodoTask] {
        var result = Array(tasks.prefix(3))
        while result.count < 3 { result.append(TodoTask(title: "")) }
        return result
    }

    private static func normalizedDays(_ days: [DayPlan]) -> [DayPlan] {
        Weekday.allCases.map { weekday in
            days.first { $0.weekday == weekday } ?? DayPlan(weekday: weekday)
        }
    }
}

struct WeeklyTemplate: Codable, Equatable {
    var thisWeekTasks: [TodoTask] = []
    var dailyHabits: [TodoTask] = []
    var days: [DayPlan] = Weekday.allCases.map { DayPlan(weekday: $0) }

    // Big Three is set separately for each week, so the template does not
    // carry Big Three titles.
    enum CodingKeys: String, CodingKey {
        case thisWeekTasks
        case dailyHabits
        case days
    }

    init(thisWeekTasks: [TodoTask] = [], dailyHabits: [TodoTask] = [], days: [DayPlan] = Weekday.allCases.map { DayPlan(weekday: $0) }) {
        self.thisWeekTasks = thisWeekTasks
        self.dailyHabits = dailyHabits
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thisWeekTasks = try container.decodeIfPresent([TodoTask].self, forKey: .thisWeekTasks) ?? []
        dailyHabits = try container.decodeIfPresent([TodoTask].self, forKey: .dailyHabits) ?? []
        days = try container.decodeIfPresent([DayPlan].self, forKey: .days) ?? Weekday.allCases.map { DayPlan(weekday: $0) }
    }
}
