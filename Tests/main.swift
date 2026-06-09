import Foundation

// Standalone test runner for Tasktarrasque's model logic. SwiftPM does not
// build on a Command-Line-Tools-only machine, so this is compiled directly
// with swiftc (see run-tests.sh) into an executable that exits non-zero when
// any assertion fails. It covers the pure model math and the TaskStore
// mutation, week-advancement, and persistence logic.

// MARK: - Tiny assertion harness

final class TestReporter {
    private(set) var failures: [String] = []
    private var currentName = ""

    func test(_ name: String, _ body: () -> Void) {
        currentName = name
        body()
    }

    func expect(_ condition: Bool, _ message: String) {
        if !condition { failures.append("[\(currentName)] \(message)") }
    }

    func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        if a != b { failures.append("[\(currentName)] \(message): \(a) != \(b)") }
    }
}

// MARK: - Helpers

@MainActor
func makeTempStore() -> (TaskStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("TasktarrasqueTests-\(UUID().uuidString)", isDirectory: true)
    return (TaskStore(directoryURL: dir), dir)
}

// MARK: - Tests

@MainActor
func runAll() -> Int {
    let r = TestReporter()

    r.test("fresh store creates one week starting on Monday") {
        let (store, _) = makeTempStore()
        r.expectEqual(store.weeks.count, 1, "expected one auto-created week")
        r.expectEqual(store.selectedDay, .monday, "default day should be Monday")
        r.expect(store.selectedWeek != nil, "a week should be selected")
        r.expectEqual(store.selectedWeek?.days.count, 7, "a week has seven days")
    }

    r.test("empty Big Three slot marked done never inflates the score") {
        var week = WeekPlan(startDate: Date())
        // Toggling an empty Big Three slot must not count toward the score.
        week.bigThree[0].isDone = true
        r.expectEqual(week.completedCount, 0, "empty done slot should not count completed")
        r.expectEqual(week.totalCount, 0, "empty slot should not count toward total")
        r.expectEqual(week.scoreText, "0/0", "empty week scores 0/0")

        week.bigThree[0].title = "Ship release"
        r.expectEqual(week.completedCount, 1, "titled done slot counts completed")
        r.expectEqual(week.totalCount, 1, "titled slot counts toward total")
    }

    r.test("DayPlan score sums habits and tasks") {
        let day = DayPlan(
            weekday: .monday,
            habits: [TodoTask(title: "Stretch", isDone: true)],
            tasks: [TodoTask(title: "A", isDone: true), TodoTask(title: "B")]
        )
        r.expectEqual(day.completedCount, 2, "two done items")
        r.expectEqual(day.totalCount, 3, "three total items")
        r.expectEqual(day.scoreText, "2/3", "score text")
    }

    r.test("addTask adds to the right bucket") {
        let (store, _) = makeTempStore()
        _ = store.addTask(title: "Week item", to: .thisWeek)
        _ = store.addTask(title: "Mon item", to: .day(.monday))
        r.expectEqual(store.selectedWeek?.thisWeekTasks.count, 1, "one This Week task")
        let monday = store.selectedWeek?.days.first { $0.weekday == .monday }
        r.expectEqual(monday?.tasks.count, 1, "one Monday task")
    }

    r.test("toggleDayTask flips completion") {
        let (store, _) = makeTempStore()
        let task = store.addTask(title: "Toggle me", to: .day(.monday))!
        store.toggleDayTask(task.id)
        let done = store.selectedWeek?.days.first { $0.weekday == .monday }?.tasks.first?.isDone
        r.expectEqual(done, true, "task should be done after toggle")
    }

    r.test("moveThisWeekTask relocates into the day list") {
        let (store, _) = makeTempStore()
        let task = store.addTask(title: "Move me", to: .thisWeek)!
        store.moveThisWeekTask(task.id, to: .monday)
        r.expectEqual(store.selectedWeek?.thisWeekTasks.count, 0, "This Week now empty")
        let monday = store.selectedWeek?.days.first { $0.weekday == .monday }
        r.expectEqual(monday?.tasks.count, 1, "Monday gained the task")
    }

    r.test("moveDayTaskToThisWeek clears completion") {
        let (store, _) = makeTempStore()
        let task = store.addTask(title: "Done task", to: .day(.monday))!
        store.toggleDayTask(task.id)
        store.moveDayTaskToThisWeek(task.id)
        let moved = store.selectedWeek?.thisWeekTasks.first
        r.expectEqual(moved?.isDone, false, "moved-back task should reset to not done")
    }

    r.test("reorderThisWeekTask moves a task before its target") {
        let (store, _) = makeTempStore()
        let a = store.addTask(title: "A", to: .thisWeek)!
        let b = store.addTask(title: "B", to: .thisWeek)!
        let c = store.addTask(title: "C", to: .thisWeek)!
        // Move C before A: expected order C, A, B.
        store.reorderThisWeekTask(c.id, before: a.id)
        let titles = store.selectedWeek?.thisWeekTasks.map(\.title)
        r.expectEqual(titles, ["C", "A", "B"], "C should land before A")
        _ = b
    }

    r.test("moveThisWeekTaskByKeyboard clamps at the edges") {
        let (store, _) = makeTempStore()
        let a = store.addTask(title: "A", to: .thisWeek)!
        _ = store.addTask(title: "B", to: .thisWeek)!
        store.moveThisWeekTaskByKeyboard(a.id, offset: -5) // already at top, no change
        r.expectEqual(store.selectedWeek?.thisWeekTasks.first?.title, "A", "A stays at top")
        store.moveThisWeekTaskByKeyboard(a.id, offset: 5) // move to bottom
        r.expectEqual(store.selectedWeek?.thisWeekTasks.last?.title, "A", "A moves to bottom")
    }

    r.test("pushThisWeekTaskToNextWeek creates the following week") {
        let (store, _) = makeTempStore()
        let task = store.addTask(title: "Next week item", to: .thisWeek)!
        let startBefore = store.selectedWeek!.startDate
        store.pushThisWeekTaskToNextWeek(task.id)
        r.expectEqual(store.weeks.count, 2, "a second week should exist")
        let sorted = store.weeks.sorted { $0.startDate < $1.startDate }
        let gap = Calendar.current.dateComponents([.day], from: startBefore, to: sorted[1].startDate).day
        r.expectEqual(gap, 7, "next week starts seven days later")
        r.expectEqual(sorted[1].thisWeekTasks.first?.title, "Next week item", "task landed in next week")
        r.expectEqual(sorted[0].thisWeekTasks.count, 0, "task left the current week")
    }

    r.test("deleteWeek removes it and selects a neighbor") {
        let (store, _) = makeTempStore()
        _ = store.createNewWeek() // now two weeks
        _ = store.createNewWeek() // now three weeks
        let middle = store.weeks.sorted { $0.startDate < $1.startDate }[1]
        store.deleteWeek(middle.id)
        r.expectEqual(store.weeks.count, 2, "one week removed")
        r.expect(!store.weeks.contains { $0.id == middle.id }, "the deleted week is gone")
        r.expect(store.selectedWeek != nil, "a week is still selected")
    }

    r.test("deleting the only week creates a fresh one") {
        let (store, _) = makeTempStore()
        let only = store.selectedWeek!
        store.deleteWeek(only.id)
        r.expectEqual(store.weeks.count, 1, "a replacement week exists")
        r.expect(store.weeks.first?.id != only.id, "the replacement is a new week")
        r.expect(store.selectedWeek != nil, "a week is selected")
    }

    r.test("createNewWeek advances seven days from the latest week") {
        let (store, _) = makeTempStore()
        let first = store.selectedWeek!.startDate
        let second = store.createNewWeek()
        let gap = Calendar.current.dateComponents([.day], from: first, to: second.startDate).day
        r.expectEqual(gap, 7, "new week is seven days after the latest")
    }

    r.test("data round-trips through disk") {
        let (store, dir) = makeTempStore()
        _ = store.addTask(title: "Persisted", to: .thisWeek)
        store.updateBigThree(index: 0, title: "Big goal")
        store.flushPendingSave()

        let reloaded = TaskStore(directoryURL: dir)
        r.expectEqual(reloaded.weeks.count, store.weeks.count, "week count survives reload")
        r.expectEqual(reloaded.selectedWeek?.thisWeekTasks.first?.title, "Persisted", "task survives reload")
        r.expectEqual(reloaded.selectedWeek?.bigThree.first?.title, "Big goal", "Big Three survives reload")
    }

    r.test("template decodes old data that still has bigThreeTitles") {
        // Older saves wrote a now-removed bigThreeTitles field; decoding must
        // ignore the unknown key rather than fail.
        let json = """
        {"thisWeekTasks":[],"bigThreeTitles":["x","y","z"],"dailyHabits":[{"id":"\(UUID().uuidString)","title":"Walk","isDone":false}],"days":[]}
        """.data(using: .utf8)!
        do {
            let template = try JSONDecoder().decode(WeeklyTemplate.self, from: json)
            r.expectEqual(template.dailyHabits.first?.title, "Walk", "habit decoded from old data")
        } catch {
            r.expect(false, "decoding old template threw: \(error)")
        }
    }

    if r.failures.isEmpty {
        print("All tests passed.")
        return 0
    } else {
        print("\(r.failures.count) failure(s):")
        for failure in r.failures { print("  - \(failure)") }
        return 1
    }
}

let status = MainActor.assumeIsolated { runAll() }
exit(Int32(status))
