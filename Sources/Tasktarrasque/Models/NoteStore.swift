import SwiftUI
import AppKit
import os

@MainActor
final class TaskStore: ObservableObject {
    enum SaveState: Equatable {
        case saved(Date)
        case saving
        case failed(String)

        var label: String {
            switch self {
            case .saved: "Saved"
            case .saving: "Saving…"
            case .failed: "Save failed"
            }
        }
    }

    @Published var weeks: [WeekPlan] = []
    @Published var selectedWeekID: UUID?
    @Published var selectedDay: Weekday = .monday
    @Published var template = WeeklyTemplate()
    @Published var persistenceError: String?
    @Published var saveState: SaveState = .saved(Date())

    let directoryURL: URL
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.tasktarrasque.app", category: "persistence")
    private var saveTask: Task<Void, Never>?

    private struct Persisted: Codable {
        var version: Int = 1
        var weeks: [WeekPlan]
        var selectedWeekID: UUID?
        var selectedDay: Weekday
        var template: WeeklyTemplate
    }

    convenience init() {
        let fileManager = FileManager.default
        let directory: URL
        do {
            let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            directory = base.appendingPathComponent("Tasktarrasque", isDirectory: true)
        } catch {
            let fallback = fileManager.temporaryDirectory.appendingPathComponent("Tasktarrasque", isDirectory: true)
            self.init(directoryURL: fallback, startupError: "Application Support could not be opened. Tasks are using temporary storage for this launch. \(error.localizedDescription)")
            return
        }
        self.init(directoryURL: directory)
    }

    init(directoryURL: URL, startupError: String? = nil) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("weeks.json")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let startupError { persistenceError = startupError }
        load()
        if weeks.isEmpty { createNewWeek() }
        if selectedWeekID == nil || !weeks.contains(where: { $0.id == selectedWeekID }) {
            selectedWeekID = weeks.last?.id
        }
    }

    var selectedWeek: WeekPlan? {
        guard let selectedWeekID else { return nil }
        return weeks.first { $0.id == selectedWeekID }
    }

    var selectedWeekIndex: Int? {
        guard let selectedWeekID else { return nil }
        return weeks.firstIndex { $0.id == selectedWeekID }
    }

    var selectedDayPlan: DayPlan? {
        selectedWeek?.days.first { $0.weekday == selectedDay }
    }

    func selectWeek(_ id: UUID) {
        selectedWeekID = id
        saveNow()
    }

    @discardableResult
    func createNewWeek() -> WeekPlan {
        let start = mondayStart(for: Date())
        let nextStart: Date
        if let latest = weeks.map(\.startDate).max(), latest >= start {
            nextStart = Calendar.current.date(byAdding: .day, value: 7, to: latest) ?? start
        } else {
            nextStart = start
        }
        var week = WeekPlan(startDate: nextStart)
        week.thisWeekTasks = template.thisWeekTasks.map { TodoTask(title: $0.title) }
        week.bigThree = normalizedBigThree([])
        week.days = template.days.map { day in
            DayPlan(
                weekday: day.weekday,
                habits: template.dailyHabits.map { TodoTask(title: $0.title) },
                tasks: day.tasks.map { TodoTask(title: $0.title) }
            )
        }
        weeks.append(week)
        selectedWeekID = week.id
        selectedDay = .monday
        saveNow()
        return week
    }

    @discardableResult
    func addTask(title: String = "", to target: TaskTarget) -> TodoTask? {
        guard let weekIndex = selectedWeekIndex else { return nil }
        let task = TodoTask(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        switch target {
        case .thisWeek:
            weeks[weekIndex].thisWeekTasks.append(task)
        case .day(let weekday):
            guard let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == weekday }) else { return nil }
            weeks[weekIndex].days[dayIndex].tasks.append(task)
        }
        saveNow()
        return task
    }

    func toggleDayTask(_ taskID: UUID) {
        guard let weekIndex = selectedWeekIndex,
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == selectedDay }),
              let taskIndex = weeks[weekIndex].days[dayIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        weeks[weekIndex].days[dayIndex].tasks[taskIndex].isDone.toggle()
        saveNow()
    }

    func toggleHabit(_ habitID: UUID) {
        guard let weekIndex = selectedWeekIndex,
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == selectedDay }),
              let habitIndex = weeks[weekIndex].days[dayIndex].habits.firstIndex(where: { $0.id == habitID }) else { return }
        weeks[weekIndex].days[dayIndex].habits[habitIndex].isDone.toggle()
        saveNow()
    }

    func deleteDayTask(_ taskID: UUID) {
        guard let weekIndex = selectedWeekIndex,
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == selectedDay }) else { return }
        weeks[weekIndex].days[dayIndex].tasks.removeAll { $0.id == taskID }
        saveNow()
    }

    func deleteThisWeekTask(_ taskID: UUID) {
        guard let weekIndex = selectedWeekIndex else { return }
        weeks[weekIndex].thisWeekTasks.removeAll { $0.id == taskID }
        saveNow()
    }

    func updateThisWeekTaskTitle(_ taskID: UUID, title: String) {
        guard let weekIndex = selectedWeekIndex,
              let taskIndex = weeks[weekIndex].thisWeekTasks.firstIndex(where: { $0.id == taskID }) else { return }
        weeks[weekIndex].thisWeekTasks[taskIndex].title = title
        scheduleSave()
    }

    func updateDayTaskTitle(_ taskID: UUID, title: String) {
        guard let weekIndex = selectedWeekIndex,
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == selectedDay }),
              let taskIndex = weeks[weekIndex].days[dayIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        weeks[weekIndex].days[dayIndex].tasks[taskIndex].title = title
        scheduleSave()
    }

    func moveThisWeekTask(_ taskID: UUID, to weekday: Weekday) {
        guard let weekIndex = selectedWeekIndex,
              let sourceIndex = weeks[weekIndex].thisWeekTasks.firstIndex(where: { $0.id == taskID }),
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == weekday }) else { return }
        let task = weeks[weekIndex].thisWeekTasks.remove(at: sourceIndex)
        weeks[weekIndex].days[dayIndex].tasks.append(task)
        saveNow()
    }

    func reorderThisWeekTask(_ draggedID: UUID, before targetID: UUID) {
        guard let weekIndex = selectedWeekIndex,
              draggedID != targetID,
              let sourceIndex = weeks[weekIndex].thisWeekTasks.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = weeks[weekIndex].thisWeekTasks.firstIndex(where: { $0.id == targetID }) else { return }
        let task = weeks[weekIndex].thisWeekTasks.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        weeks[weekIndex].thisWeekTasks.insert(task, at: max(0, min(adjustedTargetIndex, weeks[weekIndex].thisWeekTasks.count)))
        saveNow()
    }

    func reorderDayTask(_ draggedID: UUID, before targetID: UUID) {
        guard let weekIndex = selectedWeekIndex,
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == selectedDay }),
              draggedID != targetID,
              let sourceIndex = weeks[weekIndex].days[dayIndex].tasks.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = weeks[weekIndex].days[dayIndex].tasks.firstIndex(where: { $0.id == targetID }) else { return }
        let task = weeks[weekIndex].days[dayIndex].tasks.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        weeks[weekIndex].days[dayIndex].tasks.insert(task, at: max(0, min(adjustedTargetIndex, weeks[weekIndex].days[dayIndex].tasks.count)))
        saveNow()
    }

    func moveThisWeekTaskByKeyboard(_ taskID: UUID, offset: Int) {
        guard let weekIndex = selectedWeekIndex,
              let sourceIndex = weeks[weekIndex].thisWeekTasks.firstIndex(where: { $0.id == taskID }) else { return }
        let targetIndex = max(0, min(sourceIndex + offset, weeks[weekIndex].thisWeekTasks.count - 1))
        guard sourceIndex != targetIndex else { return }
        let task = weeks[weekIndex].thisWeekTasks.remove(at: sourceIndex)
        weeks[weekIndex].thisWeekTasks.insert(task, at: targetIndex)
        saveNow()
    }

    func moveDayTaskByKeyboard(_ taskID: UUID, offset: Int) {
        guard let weekIndex = selectedWeekIndex,
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == selectedDay }),
              let sourceIndex = weeks[weekIndex].days[dayIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let targetIndex = max(0, min(sourceIndex + offset, weeks[weekIndex].days[dayIndex].tasks.count - 1))
        guard sourceIndex != targetIndex else { return }
        let task = weeks[weekIndex].days[dayIndex].tasks.remove(at: sourceIndex)
        weeks[weekIndex].days[dayIndex].tasks.insert(task, at: targetIndex)
        saveNow()
    }

    func moveDayTaskToThisWeek(_ taskID: UUID) {
        guard let weekIndex = selectedWeekIndex,
              let dayIndex = weeks[weekIndex].days.firstIndex(where: { $0.weekday == selectedDay }),
              let taskIndex = weeks[weekIndex].days[dayIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var task = weeks[weekIndex].days[dayIndex].tasks.remove(at: taskIndex)
        // This Week items have no done state, so a task moved back loses its
        // completion. Day-to-day and This Week-to-day moves preserve it.
        task.isDone = false
        weeks[weekIndex].thisWeekTasks.append(task)
        saveNow()
    }

    func pushThisWeekTaskToNextWeek(_ taskID: UUID) {
        guard let weekIndex = selectedWeekIndex,
              let sourceIndex = weeks[weekIndex].thisWeekTasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = weeks[weekIndex].thisWeekTasks.remove(at: sourceIndex)
        let nextStart = Calendar.current.date(byAdding: .day, value: 7, to: weeks[weekIndex].startDate) ?? Date()
        let nextIndex = ensureWeek(starting: nextStart)
        weeks[nextIndex].thisWeekTasks.append(TodoTask(title: task.title, isDone: false))
        saveNow()
    }

    func updateBigThree(index: Int, title: String) {
        guard let weekIndex = selectedWeekIndex, index >= 0, index < 3 else { return }
        weeks[weekIndex].bigThree = normalizedBigThree(weeks[weekIndex].bigThree)
        weeks[weekIndex].bigThree[index].title = title
        scheduleSave()
    }

    func toggleBigThree(index: Int) {
        guard let weekIndex = selectedWeekIndex, index >= 0, index < 3 else { return }
        weeks[weekIndex].bigThree = normalizedBigThree(weeks[weekIndex].bigThree)
        weeks[weekIndex].bigThree[index].isDone.toggle()
        saveNow()
    }

    func updateTemplate(_ newTemplate: WeeklyTemplate) {
        template = newTemplate
        saveNow()
    }

    func flushPendingSave() { saveNow() }
    func revealNotesInFinder() { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }

    private func ensureWeek(starting startDate: Date) -> Int {
        let start = mondayStart(for: startDate)
        if let index = weeks.firstIndex(where: { Calendar.current.isDate($0.startDate, inSameDayAs: start) }) { return index }
        var week = WeekPlan(startDate: start)
        week.days = template.days.map {
            DayPlan(
                weekday: $0.weekday,
                habits: template.dailyHabits.map { TodoTask(title: $0.title) },
                tasks: $0.tasks.map { TodoTask(title: $0.title) }
            )
        }
        week.bigThree = normalizedBigThree([])
        weeks.append(week)
        weeks.sort { $0.startDate < $1.startDate }
        return weeks.firstIndex { Calendar.current.isDate($0.startDate, inSameDayAs: start) } ?? (weeks.count - 1)
    }

    private func mondayStart(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func normalizedBigThree(_ tasks: [TodoTask]) -> [TodoTask] {
        var result = Array(tasks.prefix(3))
        while result.count < 3 { result.append(TodoTask(title: "")) }
        return result
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(Persisted.self, from: data)
            weeks = decoded.weeks.sorted { $0.startDate < $1.startDate }
            selectedWeekID = decoded.selectedWeekID
            selectedDay = decoded.selectedDay
            template = decoded.template
        } catch {
            logger.error("Failed to load weeks: \(error.localizedDescription, privacy: .public)")
            persistenceError = "The weeks file could not be read. \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        saveState = .saving
        do {
            let snapshot = Persisted(weeks: weeks, selectedWeekID: selectedWeekID, selectedDay: selectedDay, template: template)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
            saveState = .saved(Date())
            persistenceError = nil
        } catch {
            let message = "Tasks could not be saved. \(error.localizedDescription)"
            persistenceError = message
            saveState = .failed(message)
        }
    }
}

enum TaskTarget {
    case thisWeek
    case day(Weekday)
}
