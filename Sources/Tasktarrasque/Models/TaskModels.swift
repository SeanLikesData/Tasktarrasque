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

    var completedCount: Int {
        days.map(\.completedCount).reduce(0, +) + bigThree.filter(\.isDone).count
    }

    var totalCount: Int {
        days.map(\.totalCount).reduce(0, +) + bigThree.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var scoreText: String { "\(completedCount)/\(totalCount)" }

    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Week of \(formatter.string(from: startDate))"
    }

    var pickerTitle: String { "\(title)  •  \(scoreText)" }
}

struct WeeklyTemplate: Codable, Equatable {
    var thisWeekTasks: [TodoTask] = []
    var bigThreeTitles: [String] = ["", "", ""]
    var dailyHabits: [TodoTask] = []
    var days: [DayPlan] = Weekday.allCases.map { DayPlan(weekday: $0) }

    enum CodingKeys: String, CodingKey {
        case thisWeekTasks
        case bigThreeTitles
        case dailyHabits
        case days
    }

    init(thisWeekTasks: [TodoTask] = [], bigThreeTitles: [String] = ["", "", ""], dailyHabits: [TodoTask] = [], days: [DayPlan] = Weekday.allCases.map { DayPlan(weekday: $0) }) {
        self.thisWeekTasks = thisWeekTasks
        self.bigThreeTitles = bigThreeTitles
        self.dailyHabits = dailyHabits
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thisWeekTasks = try container.decodeIfPresent([TodoTask].self, forKey: .thisWeekTasks) ?? []
        bigThreeTitles = try container.decodeIfPresent([String].self, forKey: .bigThreeTitles) ?? ["", "", ""]
        dailyHabits = try container.decodeIfPresent([TodoTask].self, forKey: .dailyHabits) ?? []
        days = try container.decodeIfPresent([DayPlan].self, forKey: .days) ?? Weekday.allCases.map { DayPlan(weekday: $0) }
    }
}
