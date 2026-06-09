import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var controller: AppController
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.default.rawValue
    @State private var draggedThisWeekTaskID: UUID?
    @State private var draggedDayTaskID: UUID?

    private var popoverSize: CGSize { (PopoverSize(rawValue: popoverRaw) ?? .default).dimensions }

    var body: some View {
        ZStack {
            TasktarrasqueStyle.panelMaterial
            routeContent
            if controller.route == .main, let week = controller.weekPendingDeletion {
                deleteWeekConfirmation(week).zIndex(3)
            }
            if let persistenceError = store.persistenceError {
                errorBanner(persistenceError)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: store.selectedWeekID) { _, _ in controller.validateMainSelection() }
        .onChange(of: store.selectedDay) { _, _ in controller.validateMainSelection() }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: TasktarrasqueStyle.panelCornerRadius, style: .continuous))
        .overlay(TasktarrasqueStyle.panelBorder)
    }

    @ViewBuilder
    private var routeContent: some View {
        switch controller.route {
        case .main:
            VStack(spacing: 0) {
                header
                TasktarrasqueStyle.divider
                weekTabs
                TasktarrasqueStyle.divider
                mainBody
                TasktarrasqueStyle.divider
                BottomBar(
                    onTemplate: { controller.showTemplate() },
                    onShortcuts: { controller.showShortcuts() },
                    onSettings: { controller.showSettings() }
                )
            }
        case .template:
            TemplateSheet()
        case .settings:
            SettingsSheet(onClose: { controller.returnToMain() })
        case .shortcuts:
            KeyboardShortcutsSheet(onClose: { controller.returnToMain() })
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Week", selection: Binding(get: { store.selectedWeekID ?? store.weeks.first?.id ?? UUID() }, set: { controller.selectWeek($0) })) {
                ForEach(store.weeks) { week in Text(week.pickerTitle).tag(week.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 270)
            Button { controller.createNewWeek() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("New Week")
                }
            }
            .buttonStyle(.plain)
            .glassPill(cornerRadius: 8)
            .help("Create the next week")
            .accessibilityLabel("Create new week")
            Button { controller.requestDeleteSelectedWeek() } label: {
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
                Button { controller.selectDay(day) } label: {
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
                    SharedSectionHeader(title: "This Week", shortcut: "W") { controller.createThisWeekTask() }
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
                                            controller.selectDay(day)
                                            controller.selectTaskItem(.dayTask(weekID: week.id, weekday: day, taskID: task.id))
                                            controller.validateMainSelection()
                                        }
                                    }
                                    Divider()
                                    Button("Push to Next Week") {
                                        store.pushThisWeekTaskToNextWeek(task.id)
                                        controller.validateMainSelection()
                                    }
                                    Button(role: .destructive) {
                                        controller.deleteTaskItem(address)
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
                                        controller.cancelTaskEdit()
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
                    SharedSectionHeader(title: "Tasks", shortcut: "N") { controller.createTaskInSelectedDay() }
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
                                    controller.deleteTaskItem(address)
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
                                    controller.cancelTaskEdit()
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
                        controller.selectTaskItem(address)
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
                            .stroke(controller.selectedTaskItem == address ? TasktarrasqueStyle.activeControlStroke : Color.clear)
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
                            controller.selectTaskItem(address)
                            store.toggleItem(address)
                        } label: {
                            Image(systemName: task?.isDone == true ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task?.isDone == true ? "Mark not done" : "Mark done")
                        Group {
                            if controller.taskEditSession?.target == address {
                                FirstResponderTextField(
                                    text: editTitleBinding(for: address, currentTitle: task?.title ?? ""),
                                    placeholder: "Big task \(index + 1)",
                                    isFirstResponder: true
                                ) {
                                    controller.commitTaskEdit()
                                } onCancel: {
                                    controller.cancelTaskEdit()
                                }
                                .frame(height: 18)
                            } else {
                                Text((task?.title.isEmpty == false ? task?.title : "Big task \(index + 1)") ?? "Big task \(index + 1)")
                                    .foregroundStyle(task?.title.isEmpty == false ? .primary : .secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        controller.selectTaskItem(address)
                                    }
                                    .onTapGesture(count: 2) {
                                        beginEditing(address, currentTitle: task?.title ?? "")
                                    }
                            }
                        }
                        .strikethrough(task?.isDone == true)
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(controller.selectedTaskItem == address ? TasktarrasqueStyle.activeControlBackground : TasktarrasqueStyle.editorBackground))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(controller.selectedTaskItem == address ? TasktarrasqueStyle.activeControlStroke : Color.clear))
                    .onTapGesture { controller.selectTaskItem(address) }
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
            isSelected: controller.selectedTaskItem == address,
            isEditing: controller.taskEditSession?.target == address,
            isChecked: isChecked,
            checkIcon: "checkmark.circle.fill",
            uncheckedIcon: "circle",
            onToggle: onToggle.map { action in
                {
                    controller.selectTaskItem(address)
                    action()
                }
            },
            onSelect: { controller.selectTaskItem(address) },
            onBeginEdit: { beginEditing(address, currentTitle: title) },
            onCommitEdit: { controller.commitTaskEdit() },
            onCancelEdit: { controller.cancelTaskEdit() },
            menu: menu
        )
    }

    private func editTitleBinding(for address: TaskItemAddress, currentTitle: String) -> Binding<String> {
        Binding(
            get: {
                if controller.taskEditSession?.target == address {
                    return controller.taskEditSession?.draftTitle ?? currentTitle
                }
                return currentTitle
            },
            set: { newTitle in
                if controller.taskEditSession?.target == address {
                    controller.updateTaskEditDraft(newTitle)
                } else {
                    store.updateTitle(for: address, title: newTitle)
                }
            }
        )
    }

    private func beginEditing(_ address: TaskItemAddress, currentTitle: String) {
        controller.beginTaskEdit(address, fallbackTitle: currentTitle)
    }

    private func pendingNewThisWeekAddress(for weekID: UUID) -> TaskItemAddress? {
        controller.pendingNewThisWeekAddress(for: weekID)
    }

    private func pendingNewDayTaskAddress(weekID: UUID, weekday: Weekday) -> TaskItemAddress? {
        controller.pendingNewDayTaskAddress(weekID: weekID, weekday: weekday)
    }

    private func handleThisWeekDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let rawID = object as? String,
                  let taskID = UUID(uuidString: rawID) else { return }
            Task { @MainActor in
                store.moveThisWeekTask(taskID, to: store.selectedDay)
                if let weekID = store.selectedWeekID {
                    controller.selectTaskItem(.dayTask(weekID: weekID, weekday: store.selectedDay, taskID: taskID))
                }
                controller.validateMainSelection()
            }
        }
        return true
    }

    private func deleteWeekConfirmation(_ week: WeekPlan) -> some View {
        let taskCount = week.days.reduce(0) { $0 + $1.tasks.count } + week.thisWeekTasks.count
        return ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { controller.cancelWeekDeletion() }
            VStack(alignment: .leading, spacing: 14) {
                Text("Delete this week?")
                    .font(.system(size: 17, weight: .bold))
                Text("\(week.title) and its \(taskCount) task\(taskCount == 1 ? "" : "s") will be permanently deleted. This cannot be undone.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { controller.cancelWeekDeletion() }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .glassPill(cornerRadius: 8)
                    Button("Delete Week") {
                        controller.confirmWeekDeletion()
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
