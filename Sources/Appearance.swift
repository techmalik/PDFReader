import AppKit
import CoreImage

/// Dark mode. Two independent settings, both remembered between launches:
/// - App appearance (View ▸ Appearance): follow macOS, or force Light or Dark for PDFReader's windows.
/// - Page colours (View ▸ Page Colors): show pages as they are, always dark (inverted, hues kept),
///   or dark only while the app is in dark mode. This only changes the screen; printing and saved
///   files are untouched.
enum Appearance {
    enum Mode: Int, CaseIterable {
        case system, light, dark
        var title: String { ["Use System Setting", "Light", "Dark"][rawValue] }
    }

    enum PageColors: Int, CaseIterable {
        case normal, dark, matchAppearance
        var title: String { ["Normal", "Dark Pages", "Dark Pages in Dark Mode"][rawValue] }
    }

    static let didChange = Notification.Name("PDFReaderAppearanceDidChange")
    private static let modeKey = "appearanceMode"
    private static let pageColorsKey = "pageColors"

    static var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: modeKey)) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            apply()
        }
    }

    static var pageColors: PageColors {
        get { PageColors(rawValue: UserDefaults.standard.integer(forKey: pageColorsKey)) ?? .normal }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: pageColorsKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Applies the app appearance. Call once at launch and whenever it changes.
    static func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Whether pages should be shown dark in a view with this effective appearance.
    static func wantsDarkPages(for appearance: NSAppearance) -> Bool {
        switch pageColors {
        case .normal: return false
        case .dark: return true
        case .matchAppearance: return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    /// Invert brightness, then rotate hue back so colours (links, highlights, photos) keep their hue.
    static func darkPageFilters() -> [CIFilter] {
        guard let invert = CIFilter(name: "CIColorInvert"), let hue = CIFilter(name: "CIHueAdjust") else { return [] }
        hue.setValue(Double.pi, forKey: kCIInputAngleKey)
        return [invert, hue]
    }
}
