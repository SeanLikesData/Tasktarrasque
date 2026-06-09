import SwiftUI

/// Shared visual styling for the dark glass HUD. Tasktarrasque is a dark glass
/// panel by design: the background uses the dark `.hudWindow` material with
/// dark gradients, and the control colors are white-opacity highlights tuned
/// for that dark surface. The popover therefore forces a dark color scheme so
/// text and controls stay readable.
enum TasktarrasqueStyle {
    static let panelCornerRadius: CGFloat = 18

    static var panelMaterial: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 260
            )
        }
    }

    static var panelBorder: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.32),
                        Color.white.opacity(0.12),
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    static var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .overlay(Rectangle().fill(Color.black.opacity(0.12)).offset(y: 1))
    }

    static var verticalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1)
            .overlay(Rectangle().fill(Color.black.opacity(0.12)).offset(x: 1))
    }

    static let controlBackground = Color.white.opacity(0.10)
    static let controlHoverBackground = Color.white.opacity(0.16)
    static let activeControlBackground = Color.white.opacity(0.22)
    static let editorBackground = Color.black.opacity(0.14)
    static let controlStroke = Color.white.opacity(0.14)
    static let activeControlStroke = Color.white.opacity(0.28)
}

struct GlassPillModifier: ViewModifier {
    @State private var hovering = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(hovering ? TasktarrasqueStyle.controlHoverBackground : TasktarrasqueStyle.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(hovering ? TasktarrasqueStyle.activeControlStroke : TasktarrasqueStyle.controlStroke)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func glassPill(cornerRadius: CGFloat) -> some View {
        modifier(GlassPillModifier(cornerRadius: cornerRadius))
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
