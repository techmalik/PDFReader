import AppKit
import PDFKit

/// The markup tools on the Markup bar (⇧⌘A).
enum MarkupTool: Int, CaseIterable {
    case highlight, underline, strikethrough, pen, note, eraser

    var title: String {
        switch self {
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .pen: return "Pen"
        case .note: return "Note"
        case .eraser: return "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .pen: return "pencil.tip"
        case .note: return "note.text"
        case .eraser: return "eraser"
        }
    }

    var help: String {
        switch self {
        case .highlight: return "Highlight: drag across text. On scanned pages or pictures, drag to draw a marker stroke."
        case .underline: return "Underline: drag across text"
        case .strikethrough: return "Strikethrough: drag across text"
        case .pen: return "Pen: draw freehand on the page"
        case .note: return "Note: click where you want a note"
        case .eraser: return "Eraser: click or drag over a highlight, drawing or note to remove it"
        }
    }

    /// Text tools mark up selected text; the PDF annotation subtype they create.
    var textMarkupType: PDFAnnotationSubtype? {
        switch self {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikethrough: return .strikeOut
        default: return nil
        }
    }

    var usesThickness: Bool { self == .pen || self == .highlight }
}

/// The current tool, colour and thickness, remembered between launches and shared by all windows.
enum MarkupSettings {
    static let didChange = Notification.Name("MarkupSettingsDidChange")

    struct Swatch {
        let name: String
        let color: NSColor
    }

    static let palette: [Swatch] = [
        Swatch(name: "Yellow", color: NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1)),
        Swatch(name: "Green", color: NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)),
        Swatch(name: "Blue", color: NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)),
        Swatch(name: "Pink", color: NSColor(srgbRed: 1.00, green: 0.18, blue: 0.57, alpha: 1)),
        Swatch(name: "Red", color: NSColor(srgbRed: 0.90, green: 0.13, blue: 0.10, alpha: 1)),
        Swatch(name: "Black", color: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)),
    ]

    static let thicknessNames = ["Thin", "Medium", "Thick"]
    private static let penWidths: [CGFloat] = [1.5, 3, 6]
    private static let markerWidths: [CGFloat] = [8, 14, 22]

    private static let toolKey = "markupTool"
    private static let colorKey = "markupColor"
    private static let thicknessKey = "markupThickness"

    static var tool: MarkupTool {
        get { MarkupTool(rawValue: UserDefaults.standard.integer(forKey: toolKey)) ?? .highlight }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: toolKey); post() }
    }

    static var colorIndex: Int {
        get { min(max(UserDefaults.standard.integer(forKey: colorKey), 0), palette.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: colorKey); post() }
    }

    static var thicknessIndex: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: thicknessKey) as? Int ?? 1
            return min(max(stored, 0), thicknessNames.count - 1)
        }
        set { UserDefaults.standard.set(newValue, forKey: thicknessKey); post() }
    }

    static var color: NSColor { palette[colorIndex].color }

    /// Stroke width in page points for freehand drawing with the given tool.
    static func strokeWidth(for tool: MarkupTool) -> CGFloat {
        tool == .highlight ? markerWidths[thicknessIndex] : penWidths[thicknessIndex]
    }

    /// Colour used for a freehand stroke: the marker is see-through so text stays readable.
    static func strokeColor(for tool: MarkupTool) -> NSColor {
        tool == .highlight ? color.withAlphaComponent(0.4) : color
    }

    private static func post() { NotificationCenter.default.post(name: didChange, object: nil) }
}

extension PDFAnnotation {
    /// Highlights, underlines, strikethroughs, drawings and notes: things the Markup tools make
    /// and the eraser may remove. Links, form fields and signatures are left alone.
    var isMarkup: Bool {
        guard !(self is SignatureAnnotation) else { return false }
        let kind = (type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return ["highlight", "underline", "strikeout", "squiggly", "ink", "text", "freetext"].contains(kind)
    }

    var isNote: Bool {
        (type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "text"
    }

    var isInk: Bool {
        (type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "ink"
    }

    var markupName: String {
        switch (type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() {
        case "highlight": return "Highlight"
        case "underline": return "Underline"
        case "strikeout": return "Strikethrough"
        case "ink": return "Drawing"
        case "text": return "Note"
        default: return "Markup"
        }
    }
}
