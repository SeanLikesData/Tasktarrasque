import SwiftUI

struct BottomBar: View {
    @EnvironmentObject private var store: TaskStore
    let onTemplate: () -> Void
    let onShortcuts: () -> Void
    let onSettings: () -> Void

    /// Shared content height so the save-status pill, the Template button, and
    /// the icon buttons all line up to the same pill height.
    private let controlHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            Text("\(store.weeks.count) saved week\(store.weeks.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(store.saveState.label)
                .font(.system(size: 11))
                .foregroundStyle(saveStatusColor)
                .frame(height: controlHeight)
                .glassPill(cornerRadius: 8)

            Button(action: onTemplate) {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2")
                    Text("Template")
                }
                .font(.system(size: 11, weight: .medium))
                .frame(height: controlHeight)
            }
            .buttonStyle(.plain)
            .glassPill(cornerRadius: 8)
            .help("Edit the weekly template")
            .accessibilityLabel("Weekly template")

            iconButton("questionmark", help: "Keyboard shortcuts", accessibility: "Keyboard shortcuts", action: onShortcuts)
            iconButton("gearshape", help: "Settings", accessibility: "Settings", action: onSettings)
                .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func iconButton(_ systemName: String, help: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: controlHeight)
                .glassPill(cornerRadius: 8)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibility)
    }

    private var saveStatusColor: Color {
        if case .failed = store.saveState { return .red }
        return .secondary
    }
}
