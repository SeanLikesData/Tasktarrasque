import SwiftUI

struct BottomBar: View {
    @EnvironmentObject private var store: TaskStore
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Text("\(store.weeks.count) saved week\(store.weeks.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(store.saveState.label)
                .font(.system(size: 11))
                .foregroundStyle(saveStatusColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassPill(cornerRadius: 8)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .glassPill(cornerRadius: 8)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var saveStatusColor: Color {
        if case .failed = store.saveState { return .red }
        return .secondary
    }
}
