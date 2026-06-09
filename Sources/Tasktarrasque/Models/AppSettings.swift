import SwiftUI

/// Keys used with @AppStorage so the strings live in one place.
enum SettingsKey {
    static let theme = "theme"
    static let fontSize = "fontSize"
    static let popoverSize = "popoverSize"
    static let pinned = "pinned"
    static let launchAtLogin = "launchAtLogin"
    static let markdownRendering = "markdownRendering"
}

/// Color scheme choice (Settings).
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "follow the system setting".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Editor font size.
enum FontSize: String, CaseIterable, Identifiable {
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

    var pointSize: CGFloat {
        switch self {
        case .small: 12
        case .medium: 14
        case .large: 17
        }
    }
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
