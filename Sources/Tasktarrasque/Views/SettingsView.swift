import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var store: TaskStore
    @AppStorage(SettingsKey.popoverSize) private var popoverRaw = PopoverSize.default.rawValue
    @AppStorage(SettingsKey.pinned) private var pinned = false
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(.system(size: 22, weight: .bold))
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .glassPill(cornerRadius: 8)
            }
            Toggle("Keep popover pinned above other windows", isOn: $pinned)
            Picker("Popover Size", selection: $popoverRaw) { ForEach(PopoverSize.allCases) { Text($0.label).tag($0.rawValue) } }
            Button("Reveal data in Finder") { store.revealNotesInFinder() }.buttonStyle(.plain).glassPill(cornerRadius: 8)
            Text("Tasktarrasque stores weeks locally as JSON in Application Support. Old weeks remain saved unless you delete the data file manually.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TasktarrasqueStyle.panelMaterial)
        .onExitCommand(perform: onClose)
    }
}
