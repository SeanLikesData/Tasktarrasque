import SwiftUI
import AppKit

struct KeyboardShortcutsSheet: View {
    let onClose: () -> Void

    private let shortcuts: [(String, String)] = [
        ("N", "Create a new task in the selected day. In the template panel, create a task for the selected day tab."),
        ("W", "Create a new task in This Week."),
        ("H", "Create a new daily habit in the template panel."),
        ("R", "Rename the selected item."),
        ("Return", "Rename the selected item. In rename mode, finish renaming."),
        ("D", "Mark the selected item done or not done."),
        ("Delete", "Delete the selected task."),
        ("Arrow keys", "Move selection between tasks."),
        ("Shift-Up", "Move the selected task up."),
        ("Shift-Down", "Move the selected task down."),
        ("Shift-Right", "Move a This Week task into the selected day."),
        ("Shift-Left", "Move a day task back to This Week."),
        ("?", "Show this keyboard shortcuts panel."),
        ("Escape", "Close panels or leave rename mode.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .glassPill(cornerRadius: 8)
            }

            VStack(spacing: 8) {
                ForEach(shortcuts, id: \.0) { shortcut, description in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(shortcut)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(TasktarrasqueStyle.controlBackground))
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            Spacer()
        }
        .padding(18)
        .background(TasktarrasqueStyle.panelMaterial)
        .focusable()
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
            }
        }
        .onExitCommand(perform: onClose)
    }
}
