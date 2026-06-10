import AppKit
import SwiftUI

@main
struct ScreenshotRenderer {
    @MainActor
    static func main() throws {
        let outputPath = CommandLine.arguments.dropFirst().first ?? "docs/screenshots"
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.set(PopoverSize.large.rawValue, forKey: SettingsKey.popoverSize)

        let store = sampleStore()
        let controller = AppController(store: store)
        if let selectedTask = sampleSelectedTask(in: store) {
            controller.selectTaskItem(selectedTask)
        }

        try render(
            ContentView()
                .environmentObject(store)
                .environmentObject(controller),
            size: PopoverSize.large.dimensions,
            to: outputDirectory.appendingPathComponent("tasktarrasque-week.png")
        )

        controller.showTemplate()
        controller.selectTemplateItem(store.template.dailyHabits.first.map { .habit($0.id) } ?? .habit(UUID()))

        try render(
            ContentView()
                .environmentObject(store)
                .environmentObject(controller),
            size: PopoverSize.large.dimensions,
            to: outputDirectory.appendingPathComponent("tasktarrasque-template.png")
        )
    }

    @MainActor
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let content = view
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.orderFront(nil)
        window.display()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ScreenshotError.renderFailed(url.lastPathComponent)
        }
        representation.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        window.orderOut(nil)

        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.renderFailed(url.lastPathComponent)
        }

        try png.write(to: url)
    }

    @MainActor
    private static func sampleStore() -> TaskStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasktarrasqueScreenshots-\(UUID().uuidString)", isDirectory: true)
        let store = TaskStore(directoryURL: directory)

        let weekID = UUID(uuidString: "55555555-5555-4555-8555-555555555555") ?? UUID()
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 8)) ?? Date()
        let habits = [
            TodoTask(id: UUID(), title: "Morning review", isDone: true),
            TodoTask(id: UUID(), title: "Inbox zero"),
            TodoTask(id: UUID(), title: "Walk outside", isDone: true),
            TodoTask(id: UUID(), title: "Read 20 pages")
        ]
        let days = Weekday.allCases.map { weekday in
            DayPlan(
                weekday: weekday,
                habits: habits,
                tasks: sampleTasks(for: weekday)
            )
        }

        store.weeks = [
            WeekPlan(
                id: weekID,
                startDate: startDate,
                thisWeekTasks: [
                    TodoTask(id: UUID(), title: "Draft launch checklist"),
                    TodoTask(id: UUID(), title: "Review design notes"),
                    TodoTask(id: UUID(), title: "Schedule stakeholder update")
                ],
                bigThree: [
                    TodoTask(id: UUID(), title: "Ship menu bar workflow", isDone: true),
                    TodoTask(id: UUID(), title: "Tighten keyboard navigation"),
                    TodoTask(id: UUID(), title: "Write release notes")
                ],
                days: days
            )
        ]
        store.selectedWeekID = weekID
        store.selectedDay = .wednesday
        store.template = WeeklyTemplate(
            thisWeekTasks: [
                TodoTask(id: UUID(), title: "Review backlog"),
                TodoTask(id: UUID(), title: "Prepare weekly plan")
            ],
            dailyHabits: [
                TodoTask(id: UUID(), title: "Morning review"),
                TodoTask(id: UUID(), title: "Inbox zero"),
                TodoTask(id: UUID(), title: "Walk outside")
            ],
            days: Weekday.allCases.map { weekday in
                DayPlan(
                    weekday: weekday,
                    tasks: templateTasks(for: weekday)
                )
            }
        )
        store.persistenceError = nil
        return store
    }

    private static func sampleTasks(for weekday: Weekday) -> [TodoTask] {
        switch weekday {
        case .monday:
            [
                TodoTask(id: UUID(), title: "Plan sprint", isDone: true),
                TodoTask(id: UUID(), title: "Triage bug reports", isDone: true)
            ]
        case .tuesday:
            [
                TodoTask(id: UUID(), title: "Refactor shortcuts"),
                TodoTask(id: UUID(), title: "Sync with design")
            ]
        case .wednesday:
            [
                TodoTask(id: UUID(), title: "Audit template flow", isDone: true),
                TodoTask(id: UUID(), title: "Write regression tests"),
                TodoTask(id: UUID(), title: "Package installed build")
            ]
        case .thursday:
            [
                TodoTask(id: UUID(), title: "Polish README screenshots")
            ]
        case .friday:
            [
                TodoTask(id: UUID(), title: "Cut local release"),
                TodoTask(id: UUID(), title: "Back up task data")
            ]
        case .saturday:
            [
                TodoTask(id: UUID(), title: "Review personal admin")
            ]
        case .sunday:
            [
                TodoTask(id: UUID(), title: "Plan next week")
            ]
        }
    }

    private static func templateTasks(for weekday: Weekday) -> [TodoTask] {
        switch weekday {
        case .monday:
            [TodoTask(id: UUID(), title: "Set weekly priorities")]
        case .tuesday:
            [TodoTask(id: UUID(), title: "Project review")]
        case .wednesday:
            [
                TodoTask(id: UUID(), title: "Midweek audit"),
                TodoTask(id: UUID(), title: "Update roadmap")
            ]
        case .thursday:
            [TodoTask(id: UUID(), title: "Follow up with stakeholders")]
        case .friday:
            [TodoTask(id: UUID(), title: "Weekly wrap-up")]
        case .saturday:
            [TodoTask(id: UUID(), title: "Personal reset")]
        case .sunday:
            [TodoTask(id: UUID(), title: "Prepare next week")]
        }
    }

    @MainActor
    private static func sampleSelectedTask(in store: TaskStore) -> TaskItemAddress? {
        guard let week = store.selectedWeek,
              let task = store.selectedDayPlan?.tasks.first else { return nil }
        return .dayTask(weekID: week.id, weekday: store.selectedDay, taskID: task.id)
    }
}

enum ScreenshotError: Error {
    case renderFailed(String)
}
