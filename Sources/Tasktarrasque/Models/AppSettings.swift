import SwiftUI

/// Keys used with @AppStorage so the strings live in one place.
enum SettingsKey {
    static let popoverSize = "popoverSize"
    static let pinned = "pinned"
}

/// Popover dimensions.
enum PopoverSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var dimensions: CGSize {
        switch self {
        case .small: CGSize(width: 560, height: 460)
        case .medium: CGSize(width: 680, height: 560)
        case .large: CGSize(width: 820, height: 640)
        }
    }

    /// The single default used when no preference is saved. Every place that
    /// resolves the popover size must use this so the AppKit window and the
    /// SwiftUI content agree on first launch.
    static let `default`: PopoverSize = .large

    /// Resolves the currently saved popover size, falling back to the default.
    static var saved: PopoverSize {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.popoverSize)
        return raw.flatMap(PopoverSize.init(rawValue:)) ?? .default
    }
}
