import AppKit
import PDFKit

/// A signature placed on a page. It's a stamp annotation whose appearance is the signature image;
/// PDFKit writes that drawing into the file when the document is saved, so other PDF apps show it too.
final class SignatureAnnotation: PDFAnnotation {
    private(set) var signatureImage: CGImage?

    convenience init(image: CGImage, bounds: CGRect) {
        self.init(bounds: bounds, forType: .stamp, withProperties: nil)
        signatureImage = image
        contents = "Signature"
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let image = signatureImage else { return }
        context.saveGState()
        // Keep the signature upright on rotated pages.
        let rotation = CGFloat(page?.rotation ?? 0)
        let quarterTurned = Int(rotation) % 180 != 0
        let drawSize = quarterTurned ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: rotation * .pi / 180)
        let rect = CGRect(x: -drawSize.width / 2, y: -drawSize.height / 2, width: drawSize.width, height: drawSize.height)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }
}

/// PDFView that lets you move, resize and delete placed signatures.
/// Drag a signature to move it, drag its bottom-right corner to resize it,
/// and press Delete (or right-click ▸ Delete Signature) to remove it.
final class SigningPDFView: PDFView {
    private(set) var selectedSignature: SignatureAnnotation? {
        didSet {
            updateSelectionOverlay()
        }
    }

    /// Dashed frame and resize handle drawn above the page (never part of the PDF).
    private let selectionOverlay = SelectionOverlayView()

    // MARK: Markup state (logic in SigningPDFView+Markup.swift)

    /// The active markup tool, or nil when reading normally.
    var markupTool: MarkupTool? {
        didSet {
            if markupTool == nil { cancelStroke() }
            if oldValue != markupTool { window?.invalidateCursorRects(for: self) }
        }
    }
    /// Called when Escape is pressed while a markup tool is active.
    var onEscapeInMarkup: (() -> Void)?
    /// Live preview of a pen or marker stroke while it's being drawn.
    let strokePreview = StrokePreviewView()
    var strokePage: PDFPage?
    var strokePoints: [CGPoint] = [] // page space
    var strokeTool: MarkupTool = .pen
    var textMarkupInProgress = false
    var erasing = false
    private var observersInstalled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !observersInstalled else { return }
        observersInstalled = true
        selectionOverlay.isHidden = true
        addSubview(selectionOverlay, positioned: .above, relativeTo: nil)
        strokePreview.isHidden = true
        addSubview(strokePreview, positioned: .above, relativeTo: nil)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(viewGeometryChanged(_:)), name: .PDFViewScaleChanged, object: self)
        center.addObserver(self, selector: #selector(viewGeometryChanged(_:)), name: .PDFViewDisplayModeChanged, object: self)
        center.addObserver(self, selector: #selector(appearanceSettingsChanged(_:)), name: Appearance.didChange, object: nil)
        if let clip = documentView?.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(viewGeometryChanged(_:)),
                               name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func viewGeometryChanged(_ notification: Notification) { updateSelectionOverlay() }

    override func layout() {
        super.layout()
        strokePreview.frame = bounds
        updateSelectionOverlay()
        updatePageColors()
    }

    // MARK: - Dark pages

    private var showsDarkPages = false
    private weak var filteredView: NSView?

    @objc private func appearanceSettingsChanged(_ notification: Notification) { updatePageColors() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePageColors()
    }

    /// Inverts the pages on screen when dark pages are on. Only the page area is filtered,
    /// so the selection frame and the window chrome keep their normal colours.
    func updatePageColors() {
        guard let pages = documentView else { return }
        let dark = Appearance.wantsDarkPages(for: effectiveAppearance)
        guard dark != showsDarkPages || pages !== filteredView else { return }
        if let old = filteredView, old !== pages { old.contentFilters = [] }
        showsDarkPages = dark
        filteredView = pages
        pages.wantsLayer = true
        pages.layerUsesCoreImageFilters = true
        pages.contentFilters = dark ? Appearance.darkPageFilters() : []
        backgroundColor = dark ? NSColor(white: 0.12, alpha: 1) : NSColor.underPageBackgroundColor
    }

    private func updateSelectionOverlay() {
        guard let sig = selectedSignature, let page = sig.page else {
            selectionOverlay.isHidden = true
            return
        }
        let rect = convert(sig.bounds, from: page)
        let pad = SelectionOverlayView.padding
        selectionOverlay.frame = rect.insetBy(dx: -pad, dy: -pad)
        selectionOverlay.handleAtBottom = !isFlipped
        selectionOverlay.isHidden = false
        selectionOverlay.needsDisplay = true
        if selectionOverlay.superview === self, subviews.last !== selectionOverlay {
            addSubview(selectionOverlay, positioned: .above, relativeTo: nil)
        }
    }

    private enum DragMode { case move, resize }
    private var dragMode: DragMode?
    private var dragStartPoint = CGPoint.zero // page space
    private var dragStartBounds = CGRect.zero
    private var resizeAnchor = CGPoint.zero    // page space; the corner that stays put
    private var didDrag = false

    private static let handleSize: CGFloat = 14 // view points

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Placing

    /// Adds a signature in the middle of the visible part of the current page, selected and ready to move.
    func place(_ image: NSImage) {
        guard let page = currentPage,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let pageBox = page.bounds(for: .cropBox)
        var visible = convert(bounds, to: page).intersection(pageBox)
        if visible.isNull || visible.isEmpty { visible = pageBox }

        // Size as it will look on screen: ~170pt wide, at most 70pt tall, at most 60% of the visible width.
        let aspect = max(0.05, CGFloat(cg.width) / CGFloat(max(1, cg.height)))
        let quarterTurned = page.rotation % 180 != 0
        let visibleWidth = quarterTurned ? visible.height : visible.width
        var width = min(170, visibleWidth * 0.6)
        var height = width / aspect
        if height > 70 { height = 70; width = height * aspect }
        let size = quarterTurned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let rect = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)

        let annotation = SignatureAnnotation(image: cg, bounds: clamp(rect, to: pageBox))
        add(annotation, to: page)
        undoManager?.setActionName("Add Signature")
        selectedSignature = annotation
        window?.makeFirstResponder(self)
    }

    private func add(_ annotation: SignatureAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        annotationsChanged(on: page)
        undoManager?.registerUndo(withTarget: self) { view in
            view.remove(annotation)
        }
    }

    private func remove(_ annotation: SignatureAnnotation) {
        guard let page = annotation.page else { return }
        if selectedSignature === annotation { selectedSignature = nil }
        page.removeAnnotation(annotation)
        annotationsChanged(on: page)
        undoManager?.registerUndo(withTarget: self) { view in
            view.add(annotation, to: page)
        }
    }

    private func setBounds(_ rect: CGRect, of annotation: SignatureAnnotation, from old: CGRect) {
        annotation.bounds = rect
        if let page = annotation.page { annotationsChanged(on: page) }
        updateSelectionOverlay()
        undoManager?.registerUndo(withTarget: self) { view in
            view.setBounds(old, of: annotation, from: rect)
        }
    }

    /// Clears the selection frame so it isn't saved into the file.
    func deselectSignature() { selectedSignature = nil }

    var hasSelectedSignature: Bool { selectedSignature != nil }

    @objc func deleteSelectedSignature(_ sender: Any?) {
        guard let annotation = selectedSignature else { return }
        remove(annotation)
        undoManager?.setActionName("Delete Signature")
    }

    /// Edit ▸ Delete
    @objc func delete(_ sender: Any?) { deleteSelectedSignature(sender) }

    // MARK: - Hit testing

    private func signature(at viewPoint: CGPoint) -> (SignatureAnnotation, PDFPage)? {
        guard let page = page(for: viewPoint, nearest: false) else { return nil }
        let point = convert(viewPoint, to: page)
        let slop = Self.handleSize / max(scaleFactor, 0.01)
        // Topmost first; the selected one gets its resize-handle margin.
        for annotation in page.annotations.reversed() {
            guard let sig = annotation as? SignatureAnnotation else { continue }
            let area = sig === selectedSignature ? sig.bounds.insetBy(dx: -slop / 2, dy: -slop / 2) : sig.bounds
            if area.contains(point) { return (sig, page) }
        }
        return nil
    }

    /// The signature's corners as they appear on screen.
    private func visualCorners(of annotation: SignatureAnnotation, on page: PDFPage) -> (topLeft: CGPoint, bottomRight: CGPoint) {
        let rect = convert(annotation.bounds, from: page)
        let top = isFlipped ? rect.minY : rect.maxY
        let bottom = isFlipped ? rect.maxY : rect.minY
        return (CGPoint(x: rect.minX, y: top), CGPoint(x: rect.maxX, y: bottom))
    }

    private func isOnResizeHandle(_ viewPoint: CGPoint, of annotation: SignatureAnnotation, on page: PDFPage) -> Bool {
        guard annotation === selectedSignature else { return false }
        let corner = visualCorners(of: annotation, on: page).bottomRight
        return abs(viewPoint.x - corner.x) <= Self.handleSize && abs(viewPoint.y - corner.y) <= Self.handleSize
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(viewPoint) else { super.mouseDown(with: event); return }
        if markupTool != nil {
            selectedSignature = nil
            markupMouseDown(with: event, at: viewPoint)
            return
        }
        if event.clickCount == 2, openNote(at: viewPoint) { return }
        guard let (sig, page) = signature(at: viewPoint) else {
            selectedSignature = nil
            dragMode = nil
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        clearSelection()
        let resizing = isOnResizeHandle(viewPoint, of: sig, on: page)
        selectedSignature = sig
        dragMode = resizing ? .resize : .move
        dragStartPoint = convert(viewPoint, to: page)
        dragStartBounds = sig.bounds
        resizeAnchor = convert(visualCorners(of: sig, on: page).topLeft, to: page)
        didDrag = false
        (resizing ? NSCursor.crosshair : NSCursor.closedHand).set()
    }

    override func mouseDragged(with event: NSEvent) {
        if markupTool != nil { markupMouseDragged(with: event); return }
        guard let mode = dragMode, let sig = selectedSignature, let page = sig.page else {
            super.mouseDragged(with: event)
            return
        }
        autoscroll(with: event)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pageBox = page.bounds(for: .cropBox)
        didDrag = true
        switch mode {
        case .move:
            let point = convert(viewPoint, to: page)
            let moved = dragStartBounds.offsetBy(dx: point.x - dragStartPoint.x, dy: point.y - dragStartPoint.y)
            sig.bounds = clamp(moved, to: pageBox)
        case .resize:
            // Work on screen so the handle tracks the pointer on rotated pages too; keep the aspect ratio.
            let anchor = convert(resizeAnchor, from: page)
            let aspect = dragStartBounds.width / max(dragStartBounds.height, 0.01)
            let visualAspect = page.rotation % 180 != 0 ? 1 / aspect : aspect
            var width = max(24, abs(viewPoint.x - anchor.x))
            var height = width / visualAspect
            let minHeight: CGFloat = 10
            if height < minHeight { height = minHeight; width = height * visualAspect }
            let originY = isFlipped ? anchor.y : anchor.y - height
            let viewRect = CGRect(x: anchor.x, y: originY, width: width, height: height)
            let pageRect = convert(viewRect, to: page).standardized
            if pageBox.contains(pageRect) { sig.bounds = pageRect }
        }
        annotationsChanged(on: page)
        updateSelectionOverlay()
    }

    override func mouseUp(with event: NSEvent) {
        if markupTool != nil { markupMouseUp(with: event); return }
        guard let mode = dragMode, let sig = selectedSignature else {
            super.mouseUp(with: event)
            return
        }
        dragMode = nil
        if didDrag && sig.bounds != dragStartBounds {
            let final = sig.bounds
            sig.bounds = dragStartBounds
            setBounds(final, of: sig, from: dragStartBounds)
            undoManager?.setActionName(mode == .move ? "Move Signature" : "Resize Signature")
        }
        NSCursor.openHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let tool = markupTool {
            markupCursor(for: tool, at: viewPoint)?.set()
            return
        }
        if let (sig, page) = signature(at: viewPoint) {
            (isOnResizeHandle(viewPoint, of: sig, on: page) ? NSCursor.crosshair : NSCursor.openHand).set()
        }
    }

    override func keyDown(with event: NSEvent) {
        if markupTool != nil, event.keyCode == 53 { // Escape ends markup
            onEscapeInMarkup?()
            return
        }
        if selectedSignature != nil, let key = event.charactersIgnoringModifiers?.unicodeScalars.first {
            switch Int(key.value) {
            case NSDeleteCharacter, NSDeleteFunctionKey, NSBackspaceCharacter:
                deleteSelectedSignature(nil)
                return
            case 0x1b: // Escape
                selectedSignature = nil
                return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let (sig, _) = signature(at: viewPoint) else {
            return markupMenu(at: viewPoint) ?? super.menu(for: event)
        }
        selectedSignature = sig
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Delete Signature", action: #selector(deleteSelectedSignature(_:)), keyEquivalent: "")
        item.target = self
        return menu
    }

    private func clamp(_ rect: CGRect, to box: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(r.width, box.width)
        r.size.height = min(r.height, box.height)
        r.origin.x = min(max(r.minX, box.minX), box.maxX - r.width)
        r.origin.y = min(max(r.minY, box.minY), box.maxY - r.height)
        return r
    }
}

/// Selection frame for a placed signature. It lets clicks through to the PDF view.
final class SelectionOverlayView: NSView {
    static let padding: CGFloat = 4
    var handleAtBottom = true

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let frameRect = bounds.insetBy(dx: Self.padding - 1, dy: Self.padding - 1)
        let path = NSBezierPath(rect: frameRect)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        let r: CGFloat = 4.5
        let corner = NSPoint(x: frameRect.maxX, y: handleAtBottom ? frameRect.minY : frameRect.maxY)
        let handle = NSBezierPath(ovalIn: NSRect(x: corner.x - r, y: corner.y - r, width: r * 2, height: r * 2))
        NSColor.white.setFill()
        handle.fill()
        NSColor.controlAccentColor.setStroke()
        handle.lineWidth = 1.5
        handle.stroke()
    }
}

