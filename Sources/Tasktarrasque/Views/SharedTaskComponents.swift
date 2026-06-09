import SwiftUI
import AppKit

struct SharedSectionHeader: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 15, weight: .bold))
            Spacer()
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text(shortcut)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(TasktarrasqueStyle.controlBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TasktarrasqueStyle.controlStroke))
            }
            .buttonStyle(.plain)
            .help("Create new \(title.lowercased()) item")
        }
    }
}

struct SharedTaskCard<FocusValue: Hashable, MenuContent: View>: View {
    @Binding var title: String
    let placeholder: String
    let isSelected: Bool
    let isChecked: Bool
    let checkIcon: String
    let uncheckedIcon: String
    let onToggle: (() -> Void)?
    @Binding var renameFocus: FocusValue?
    let focusID: FocusValue
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let onToggle {
                    Button(action: onToggle) {
                        Image(systemName: isChecked ? checkIcon : uncheckedIcon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isChecked ? "Mark not done" : "Mark done")
                } else {
                    Image(systemName: uncheckedIcon)
                        .foregroundStyle(.secondary)
                        .opacity(0.45)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 16, height: 16)

            Group {
                if renameFocus == focusID {
                    FirstResponderTextField(
                        text: $title,
                        placeholder: placeholder,
                        isFirstResponder: true
                    ) {
                        renameFocus = nil
                    }
                    .frame(height: 18)
                } else {
                    Text(title.isEmpty ? placeholder : title)
                        .foregroundStyle(title.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { beginRename() }
                        .onTapGesture(count: 2) { beginRename() }
                }
            }
            .strikethrough(isChecked)
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Rename") { beginRename() }
                Divider()
                menu()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .accessibilityLabel("Task actions")
        }
        .font(.system(size: 13))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? TasktarrasqueStyle.activeControlBackground : TasktarrasqueStyle.controlBackground.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? TasktarrasqueStyle.activeControlStroke : TasktarrasqueStyle.controlStroke))
    }

    private func beginRename() {
        DispatchQueue.main.async {
            renameFocus = focusID
        }
    }
}

struct FirstResponderTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFirstResponder: Bool
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13)
        textField.textColor = .white
        textField.appearance = NSAppearance(named: .darkAqua)
        textField.delegate = context.coordinator
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            textField.stringValue = text
        }
        guard isFirstResponder else { return }
        DispatchQueue.main.async {
            guard textField.window?.firstResponder !== textField.currentEditor() else { return }
            textField.window?.makeFirstResponder(textField)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FirstResponderTextField

        init(parent: FirstResponderTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
            parent.onCommit()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }
}

struct FlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(for: subviews, proposedWidth: proposal.width ?? 0)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = rows(for: subviews, proposedWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, proposedWidth: CGFloat) -> [FlowRow] {
        let maxWidth = max(proposedWidth, 1)
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width
            if nextWidth > maxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [FlowItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(index: index, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }
        if !currentItems.isEmpty { rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight)) }
        return rows
    }

    private struct FlowRow { var items: [FlowItem]; var width: CGFloat; var height: CGFloat }
    private struct FlowItem { var index: Int; var size: CGSize }
}
