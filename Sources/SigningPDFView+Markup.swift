import AppKit
import PDFKit

/// Highlight, underline, strikethrough, pen, notes and eraser on the PDF view.
/// Everything is a standard PDF annotation, so it is saved into the file and shows in other apps.
extension SigningPDFView {

    // MARK: - Mouse

    func markupMouseDown(with event: NSEvent, at viewPoint: CGPoint) {
        guard let tool = markupTool, let page = page(for: viewPoint, nearest: false) else { return }
        window?.makeFirstResponder(self)
        let point = convert(viewPoint, to: page)

        switch tool {
        case .highlight, .underline, .strikethrough:
            if hasText(near: point, on: page) {
                textMarkupInProgress = true
                super.mouseDown(with: event) // PDFKit selects the text as you drag
                // PDFView tracks the drag itself and usually returns only once the button is up,
                // in which case mouseUp never reaches us: finish here.
                if NSEvent.pressedMouseButtons & 1 == 0 { finishTextMarkup() }
            } else if tool == .highlight {
                beginStroke(on: page, at: point, tool: .highlight)
            } else {
                NSSound.beep()
            }
        case .pen:
            beginStroke(on: page, at: point, tool: .pen)
        case .note:
            if let note = markupAnnotation(at: viewPoint)?.annotation, note.isNote {
                editNote(note)
            } else {
                addNote(on: page, at: point)
            }
        case .eraser:
            erasing = true
            erase(at: viewPoint)
        }
    }

    func markupMouseDragged(with event: NSEvent) {
        if textMarkupInProgress { super.mouseDragged(with: event); return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        if erasing { erase(at: viewPoint); return }
        guard let page = strokePage else { return }
        autoscroll(with: event)
        let box = page.bounds(for: .cropBox)
        var point = convert(viewPoint, to: page)
        point.x = min(max(point.x, box.minX), box.maxX)
        point.y = min(max(point.y, box.minY), box.maxY)
        if let last = strokePoints.last, hypot(point.x - last.x, point.y - last.y) < 0.6 / max(scaleFactor, 0.01) { return }
        strokePoints.append(point)
        updateStrokePreview()
    }

    func markupMouseUp(with event: NSEvent) {
        if textMarkupInProgress {
            super.mouseUp(with: event)
            finishTextMarkup()
            return
        }
        if erasing { erasing = false; return }
        finishStroke()
    }

    func markupCursor(for tool: MarkupTool, at viewPoint: CGPoint) -> NSCursor? {
        switch tool {
        case .pen: return .crosshair
        case .note: return markupAnnotation(at: viewPoint)?.annotation.isNote == true ? .pointingHand : .crosshair
        case .eraser: return markupAnnotation(at: viewPoint) != nil ? .pointingHand : .arrow
        case .highlight, .underline, .strikethrough:
            guard let page = page(for: viewPoint, nearest: false) else { return .arrow }
            if hasText(near: convert(viewPoint, to: page), on: page) { return .iBeam }
            return tool == .highlight ? .crosshair : .arrow
        }
    }

    /// Is there text at (or right next to) this point? Decides between marking text and drawing a marker stroke.
    private func hasText(near point: CGPoint, on page: PDFPage) -> Bool {
        let slop = 3 / max(scaleFactor, 0.01)
        for dx in [0, -slop, slop] {
            for dy in [0, -slop, slop] {
                let index = page.characterIndex(at: CGPoint(x: point.x + dx, y: point.y + dy))
                if index >= 0 && index != NSNotFound && index < page.numberOfCharacters { return true }
            }
        }
        return false
    }

    // MARK: - Text markup

    private func finishTextMarkup() {
        guard textMarkupInProgress else { return }
        textMarkupInProgress = false
        if let tool = markupTool, let type = tool.textMarkupType, let selection = currentSelection {
            markUp(selection, as: type, name: tool.title)
        }
        clearSelection()
    }

    private func markUp(_ selection: PDFSelection, as type: PDFAnnotationSubtype, name: String) {
        var added = 0
        for page in selection.pages {
            for rect in rowRects(of: selection, on: page) {
                let annotation = PDFAnnotation(bounds: rect, forType: type, withProperties: nil)
                annotation.color = MarkupSettings.color
                annotation.quadrilateralPoints = [
                    NSValue(point: NSPoint(x: 0, y: rect.height)), NSValue(point: NSPoint(x: rect.width, y: rect.height)),
                    NSValue(point: NSPoint(x: 0, y: 0)), NSValue(point: NSPoint(x: rect.width, y: 0)),
                ]
                addMarkup(annotation, to: page)
                added += 1
            }
        }
        if added > 0 { undoManager?.setActionName(name) }
    }

    /// One rectangle per row of selected text, built from the characters themselves. PDFKit's
    /// per-line bounds can span two rows when lines are tightly spaced, which would mark the wrong text.
    private func rowRects(of selection: PDFSelection, on page: PDFPage) -> [CGRect] {
        let text = (page.string ?? "") as NSString
        var rows: [CGRect] = []
        for i in 0..<selection.numberOfTextRanges(on: page) {
            let range = selection.range(at: i, on: page)
            guard range.location != NSNotFound else { continue }
            for index in range.location..<min(range.location + range.length, text.length) {
                if let scalar = UnicodeScalar(text.character(at: index)),
                   CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
                let box = page.characterBounds(at: index)
                guard box.width > 0, box.height > 0 else { continue }
                if let row = rows.firstIndex(where: { abs($0.midY - box.midY) < min($0.height, box.height) * 0.5 }) {
                    rows[row] = rows[row].union(box)
                } else {
                    rows.append(box)
                }
            }
        }
        if rows.isEmpty {
            // No character boxes (unusual fonts): fall back to PDFKit's line boxes.
            rows = selection.selectionsByLine().map { $0.bounds(for: page) }.filter { $0.width > 0.5 && $0.height > 0.5 }
        }
        return rows
    }

    // MARK: - Pen and marker strokes

    private func beginStroke(on page: PDFPage, at point: CGPoint, tool: MarkupTool) {
        strokePage = page
        strokeTool = tool
        strokePoints = [point]
        updateStrokePreview()
    }

    func cancelStroke() {
        strokePage = nil
        strokePoints = []
        strokePreview.path = nil
        strokePreview.isHidden = true
    }

    private func updateStrokePreview() {
        guard let page = strokePage, let first = strokePoints.first else { return }
        let path = NSBezierPath()
        path.move(to: convert(first, from: page))
        for point in strokePoints.dropFirst() { path.line(to: convert(point, from: page)) }
        if strokePoints.count == 1 { path.line(to: convert(first, from: page)) }
        path.lineWidth = MarkupSettings.strokeWidth(for: strokeTool) * scaleFactor
        path.lineCapStyle = strokeTool == .highlight ? .square : .round
        path.lineJoinStyle = .round
        strokePreview.drawsFlipped = isFlipped
        strokePreview.frame = bounds
        strokePreview.color = MarkupSettings.strokeColor(for: strokeTool)
        strokePreview.path = path
        strokePreview.isHidden = false
        if subviews.last !== strokePreview { addSubview(strokePreview, positioned: .above, relativeTo: nil) }
        strokePreview.needsDisplay = true
    }

    private func finishStroke() {
        defer { cancelStroke() }
        guard let page = strokePage, !strokePoints.isEmpty else { return }
        var points = strokePoints
        if points.count == 1 { points.append(CGPoint(x: points[0].x + 0.5, y: points[0].y)) } // a click makes a dot
        let width = MarkupSettings.strokeWidth(for: strokeTool)
        let xs = points.map(\.x), ys = points.map(\.y)
        let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .insetBy(dx: -width, dy: -width)

        // Ink paths are stored relative to the annotation's origin.
        let path = NSBezierPath()
        path.move(to: CGPoint(x: points[0].x - rect.minX, y: points[0].y - rect.minY))
        for point in points.dropFirst() { path.line(to: CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)) }
        path.lineWidth = width
        path.lineCapStyle = strokeTool == .highlight ? .square : .round
        path.lineJoinStyle = .round

        let annotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
        annotation.color = MarkupSettings.strokeColor(for: strokeTool)
        let border = PDFBorder()
        border.lineWidth = width
        annotation.border = border
        annotation.add(path)
        addMarkup(annotation, to: page)
        undoManager?.setActionName(strokeTool == .highlight ? "Marker" : "Drawing")
    }

    // MARK: - Notes

    private func addNote(on page: PDFPage, at point: CGPoint) {
        promptForNote(text: "", isNew: true) { [weak self] result in
            guard let self = self, case .save(let text) = result, !text.isEmpty else { return }
            let size: CGFloat = 22
            let box = page.bounds(for: .cropBox)
            let rect = CGRect(x: min(max(point.x - size / 2, box.minX), box.maxX - size),
                              y: min(max(point.y - size / 2, box.minY), box.maxY - size),
                              width: size, height: size)
            let note = PDFAnnotation(bounds: rect, forType: .text, withProperties: nil)
            note.iconType = .comment
            note.color = MarkupSettings.color
            note.contents = text
            self.addMarkup(note, to: page)
            self.undoManager?.setActionName("Add Note")
        }
    }

    /// Double-click a note (or click it with the Note tool) to read or edit it.
    func openNote(at viewPoint: CGPoint) -> Bool {
        guard let note = markupAnnotation(at: viewPoint)?.annotation, note.isNote else { return false }
        editNote(note)
        return true
    }

    private func editNote(_ note: PDFAnnotation) {
        promptForNote(text: note.contents ?? "", isNew: false) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .save(let text):
                if text.isEmpty { self.removeMarkup(note) } else { self.setContents(text, of: note) }
            case .delete:
                self.removeMarkup(note)
                self.undoManager?.setActionName("Delete Note")
            case .cancel:
                break
            }
        }
    }

    private enum NoteResult { case save(String), delete, cancel }

    private func promptForNote(text: String, isNew: Bool, completion: @escaping (NoteResult) -> Void) {
        guard let window = window else { return }
        let alert = NSAlert()
        alert.messageText = isNew ? "Add Note" : "Note"
        alert.informativeText = isNew ? "The note is saved in the PDF and shows as a note icon on the page." : ""
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.addButton(withTitle: isNew ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")
        if !isNew { alert.addButton(withTitle: "Delete").hasDestructiveAction = true }
        alert.window.initialFirstResponder = textView
        alert.beginSheetModal(for: window) { response in
            let typed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            switch response {
            case .alertFirstButtonReturn: completion(.save(typed))
            case .alertThirdButtonReturn: completion(.delete)
            default: completion(.cancel)
            }
        }
    }

    private func setContents(_ text: String, of note: PDFAnnotation) {
        let old = note.contents ?? ""
        guard old != text else { return }
        note.contents = text
        if let page = note.page { annotationsChanged(on: page) }
        undoManager?.registerUndo(withTarget: self) { view in view.setContents(old, of: note) }
        undoManager?.setActionName("Edit Note")
    }

    // MARK: - Eraser, context menu, colour

    /// The topmost markup under the pointer (ink is hit-tested along the stroke, not its whole box).
    func markupAnnotation(at viewPoint: CGPoint) -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard let page = page(for: viewPoint, nearest: false) else { return nil }
        let point = convert(viewPoint, to: page)
        let tolerance = 5 / max(scaleFactor, 0.01)
        for annotation in page.annotations.reversed() where annotation.isMarkup {
            if annotation.isInk {
                if inkStroke(annotation, passesWithin: tolerance, of: point) { return (annotation, page) }
            } else if annotation.bounds.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point) {
                return (annotation, page)
            }
        }
        return nil
    }

    private func inkStroke(_ annotation: PDFAnnotation, passesWithin tolerance: CGFloat, of point: CGPoint) -> Bool {
        let reach = tolerance + (annotation.border?.lineWidth ?? 1) / 2
        guard annotation.bounds.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
        let local = CGPoint(x: point.x - annotation.bounds.minX, y: point.y - annotation.bounds.minY)
        var previous: CGPoint?
        var points = [NSPoint](repeating: .zero, count: 3)
        for path in annotation.paths ?? [] {
            previous = nil
            for i in 0..<path.elementCount {
                let kind = path.element(at: i, associatedPoints: &points)
                let current = kind == .curveTo ? points[2] : points[0]
                if kind == .closePath { continue }
                if let p = previous, kind != .moveTo {
                    if distance(from: local, toSegment: p, current) <= reach { return true }
                } else if hypot(local.x - current.x, local.y - current.y) <= reach {
                    return true
                }
                previous = current
            }
        }
        return false
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func erase(at viewPoint: CGPoint) {
        guard let (annotation, _) = markupAnnotation(at: viewPoint) else { return }
        removeMarkup(annotation)
        undoManager?.setActionName("Erase")
    }

    func markupMenu(at viewPoint: CGPoint) -> NSMenu? {
        guard let (annotation, _) = markupAnnotation(at: viewPoint) else { return nil }
        let menu = NSMenu()
        if annotation.isNote {
            let edit = menu.addItem(withTitle: "Edit Note…", action: #selector(editNoteFromMenu(_:)), keyEquivalent: "")
            edit.target = self
            edit.representedObject = annotation
        }
        let colors = NSMenu()
        for (index, swatch) in MarkupSettings.palette.enumerated() {
            let item = colors.addItem(withTitle: swatch.name, action: #selector(recolorFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = annotation
            item.image = MarkupBar.swatchImage(swatch.color, diameter: 12)
        }
        menu.addItem(withTitle: "Color", action: nil, keyEquivalent: "").submenu = colors
        menu.addItem(.separator())
        let delete = menu.addItem(withTitle: "Delete \(annotation.markupName)", action: #selector(deleteMarkupFromMenu(_:)), keyEquivalent: "")
        delete.target = self
        delete.representedObject = annotation
        return menu
    }

    @objc private func editNoteFromMenu(_ sender: NSMenuItem) {
        if let note = sender.representedObject as? PDFAnnotation { editNote(note) }
    }

    @objc private func deleteMarkupFromMenu(_ sender: NSMenuItem) {
        guard let annotation = sender.representedObject as? PDFAnnotation else { return }
        removeMarkup(annotation)
        undoManager?.setActionName("Delete \(annotation.markupName)")
    }

    @objc private func recolorFromMenu(_ sender: NSMenuItem) {
        guard let annotation = sender.representedObject as? PDFAnnotation,
              MarkupSettings.palette.indices.contains(sender.tag) else { return }
        var color = MarkupSettings.palette[sender.tag].color
        if annotation.isInk, annotation.color.alphaComponent < 1 { color = color.withAlphaComponent(annotation.color.alphaComponent) }
        setColor(color, of: annotation)
        undoManager?.setActionName("Change Color")
    }

    private func setColor(_ color: NSColor, of annotation: PDFAnnotation) {
        let old = annotation.color
        annotation.color = color
        if let page = annotation.page { annotationsChanged(on: page) }
        undoManager?.registerUndo(withTarget: self) { view in view.setColor(old, of: annotation) }
    }

    // MARK: - Add / remove with undo

    func addMarkup(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        annotationsChanged(on: page)
        undoManager?.registerUndo(withTarget: self) { view in view.removeMarkup(annotation) }
    }

    func removeMarkup(_ annotation: PDFAnnotation) {
        guard let page = annotation.page else { return }
        page.removeAnnotation(annotation)
        annotationsChanged(on: page)
        undoManager?.registerUndo(withTarget: self) { view in view.addMarkup(annotation, to: page) }
    }
}

/// Draws the stroke being drawn, above the page. Lets clicks through to the PDF view.
final class StrokePreviewView: NSView {
    var path: NSBezierPath? { didSet { needsDisplay = true } }
    var color: NSColor = .black
    var drawsFlipped = false

    override var isFlipped: Bool { drawsFlipped }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let path = path else { return }
        color.setStroke()
        path.stroke()
    }
}
