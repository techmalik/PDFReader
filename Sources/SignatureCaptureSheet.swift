import AppKit

/// A drawing surface for a signature. Draw with the mouse, or click-and-drag on the trackpad.
/// In trackpad mode the trackpad surface maps directly onto the canvas (like Preview):
/// just touch and write with one finger, then press any key or click Done to finish.
final class SignatureCanvasView: NSView {
    var inkColor: NSColor = .black { didSet { needsDisplay = true } }
    var onChange: (() -> Void)?
    var onTrackpadModeChange: ((Bool) -> Void)?

    private(set) var strokes: [[CGPoint]] = []
    private var activeTouch: NSObjectProtocol?
    private(set) var isTrackpadMode = false

    static let lineWidth: CGFloat = 2.6
    var isEmpty: Bool { strokes.isEmpty }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func clear() {
        strokes = []
        needsDisplay = true
        onChange?()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        layer?.borderColor = (isTrackpadMode ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = isTrackpadMode ? 2 : 1

        // Signing line and hint
        let baseline = bounds.minY + bounds.height * 0.28
        NSColor(white: 0.82, alpha: 1).setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX + 24, y: baseline))
        line.line(to: NSPoint(x: bounds.maxX - 24, y: baseline))
        line.lineWidth = 1
        line.stroke()
        let mark = NSAttributedString(string: "✕", attributes: [.foregroundColor: NSColor(white: 0.7, alpha: 1),
                                                                 .font: NSFont.systemFont(ofSize: 14)])
        mark.draw(at: NSPoint(x: bounds.minX + 26, y: baseline + 4))
        if strokes.isEmpty {
            let hint = isTrackpadMode ? "Write on the trackpad with one finger. Press any key when done."
                                      : "Sign here with your mouse or trackpad"
            let text = NSAttributedString(string: hint, attributes: [
                .foregroundColor: NSColor(white: 0.62, alpha: 1), .font: NSFont.systemFont(ofSize: 13)])
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY + 10))
        }

        inkColor.setStroke()
        for stroke in strokes {
            let path = Self.smoothPath(stroke)
            path.lineWidth = Self.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    /// Quadratic smoothing through stroke midpoints. A single point becomes a dot.
    static func smoothPath(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.line(to: CGPoint(x: first.x + 0.1, y: first.y))
            return path
        }
        if points.count == 2 {
            path.line(to: points[1])
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.curve(to: mid, controlPoint1: points[i], controlPoint2: points[i])
        }
        path.line(to: points[points.count - 1])
        return path
    }

    // MARK: - Mouse / click-drag input

    override func mouseDown(with event: NSEvent) {
        guard !isTrackpadMode else { return }
        strokes.append([convert(event.locationInWindow, from: nil)])
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isTrackpadMode, !strokes.isEmpty else { return }
        appendPoint(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard !isTrackpadMode else { return }
        onChange?()
    }

    private func appendPoint(_ point: CGPoint) {
        guard var stroke = strokes.popLast() else { return }
        if let last = stroke.last, hypot(last.x - point.x, last.y - point.y) < 0.8 {
            strokes.append(stroke)
            return
        }
        stroke.append(point)
        strokes.append(stroke)
        needsDisplay = true
    }

    // MARK: - Trackpad mode (absolute finger position)

    func setTrackpadMode(_ on: Bool) {
        guard on != isTrackpadMode, let window = window else { return }
        isTrackpadMode = on
        activeTouch = nil
        if on {
            window.makeFirstResponder(self)
            // Park the cursor over the canvas and freeze it there, so touches keep coming to this view.
            let centre = window.convertPoint(toScreen: convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil))
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: centre.x, y: primaryHeight - centre.y))
            CGAssociateMouseAndMouseCursorPosition(0)
            NSCursor.hide()
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
        }
        needsDisplay = true
        onTrackpadModeChange?(on)
    }

    private func canvasPoint(for touch: NSTouch) -> CGPoint {
        // Map the trackpad onto the canvas, preserving the trackpad's aspect ratio and centring it.
        let device = touch.deviceSize
        let aspect = device.width > 0 && device.height > 0 ? device.width / device.height : 1.6
        var target = bounds.insetBy(dx: 12, dy: 12)
        if target.width / target.height > aspect {
            let w = target.height * aspect
            target = NSRect(x: target.midX - w / 2, y: target.minY, width: w, height: target.height)
        } else {
            let h = target.width / aspect
            target = NSRect(x: target.minX, y: target.midY - h / 2, width: target.width, height: h)
        }
        let p = touch.normalizedPosition // origin bottom-left, 0…1
        return CGPoint(x: target.minX + p.x * target.width, y: target.minY + p.y * target.height)
    }

    override func touchesBegan(with event: NSEvent) {
        guard isTrackpadMode, activeTouch == nil,
              let touch = event.touches(matching: .began, in: self).first else { return }
        activeTouch = touch.identity
        strokes.append([canvasPoint(for: touch)])
        needsDisplay = true
    }

    override func touchesMoved(with event: NSEvent) {
        guard isTrackpadMode, let active = activeTouch,
              let touch = event.touches(matching: .moved, in: self).first(where: { $0.identity.isEqual(active) })
        else { return }
        appendPoint(canvasPoint(for: touch))
    }

    override func touchesEnded(with event: NSEvent) {
        guard isTrackpadMode, let active = activeTouch,
              event.touches(matching: [.ended, .cancelled], in: self).contains(where: { $0.identity.isEqual(active) })
        else { return }
        activeTouch = nil
        onChange?()
    }

    override func touchesCancelled(with event: NSEvent) { touchesEnded(with: event) }

    override func keyDown(with event: NSEvent) {
        if isTrackpadMode { setTrackpadMode(false) } else { super.keyDown(with: event) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if isTrackpadMode { setTrackpadMode(false) }
        if let old = window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: old)
        }
        if let newWindow = newWindow {
            // Never leave the cursor frozen if the user switches away.
            NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey(_:)),
                                                   name: NSWindow.didResignKeyNotification, object: newWindow)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func windowResignedKey(_ notification: Notification) { setTrackpadMode(false) }

    // MARK: - Export

    /// The signature as a transparent PNG cropped to the ink, rendered at 4× for crisp printing.
    func pngData() -> Data? {
        guard !strokes.isEmpty else { return nil }
        let paths = strokes.map(Self.smoothPath)
        var box = paths.reduce(NSRect.null) { $0.union($1.bounds) }
        box = box.insetBy(dx: -Self.lineWidth * 2, dy: -Self.lineWidth * 2)
        box.size.width = max(box.width, 8)
        box.size.height = max(box.height, 8)
        let scale: CGFloat = 4
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(box.width * scale),
                                         pixelsHigh: Int(box.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = box.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform()
        transform.translateX(by: -box.minX, yBy: -box.minY)
        transform.concat()
        inkColor.setStroke()
        for path in paths {
            path.lineWidth = Self.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// Sheet for drawing a new signature and saving it to the signature library.
final class SignatureCaptureSheet: NSWindowController {
    private let canvas = SignatureCanvasView(frame: NSRect(x: 0, y: 0, width: 560, height: 220))
    private let saveButton = NSButton(title: "Save Signature", target: nil, action: nil)
    private let trackpadButton = NSButton(title: "Use Trackpad", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var completion: ((Data?) -> Void)?

    private let inks: [(String, NSColor)] = [
        ("Black", .black),
        ("Blue", NSColor(srgbRed: 0.08, green: 0.22, blue: 0.62, alpha: 1)),
        ("Dark Grey", NSColor(white: 0.25, alpha: 1)),
    ]

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 320),
                            styleMask: [.titled], backing: .buffered, defer: true)
        panel.title = "New Signature"
        super.init(window: panel)
        build(in: panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func begin(for parent: NSWindow, completion: @escaping (Data?) -> Void) {
        guard let sheet = window else { return }
        self.completion = completion
        parent.beginSheet(sheet)
        sheet.makeFirstResponder(canvas)
    }

    private func build(in panel: NSPanel) {
        let title = NSTextField(labelWithString: "Draw your signature")
        title.font = .boldSystemFont(ofSize: 13)
        let help = NSTextField(wrappingLabelWithString:
            "Click and drag to sign with the mouse or trackpad. Or click “Use Trackpad” and write on the trackpad with one finger, the way you would on paper; press any key when you’re done.")
        help.textColor = .secondaryLabelColor
        help.preferredMaxLayoutWidth = 560

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.widthAnchor.constraint(equalToConstant: 560).isActive = true
        canvas.heightAnchor.constraint(equalToConstant: 220).isActive = true
        canvas.onChange = { [weak self] in self?.updateButtons() }
        canvas.onTrackpadModeChange = { [weak self] on in
            self?.trackpadButton.title = on ? "Done" : "Use Trackpad"
            self?.trackpadButton.keyEquivalent = on ? "\r" : ""
            self?.saveButton.keyEquivalent = on ? "" : "\r"
            self?.cancelButton.keyEquivalent = on ? "" : "\u{1b}" // in trackpad mode every key just ends drawing
            self?.updateButtons()
        }

        let inkPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        inkPopup.addItems(withTitles: inks.map(\.0))
        inkPopup.target = self
        inkPopup.action = #selector(inkChanged(_:))

        trackpadButton.target = self
        trackpadButton.action = #selector(toggleTrackpad(_:))
        trackpadButton.image = NSImage(systemSymbolName: "rectangle.and.hand.point.up.left", accessibilityDescription: nil)
        trackpadButton.imagePosition = .imageLeading
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearCanvas(_:)))

        let toolRow = NSStackView(views: [NSTextField(labelWithString: "Ink:"), inkPopup, NSView(), trackpadButton, clear])
        toolRow.spacing = 8
        toolRow.setHuggingPriority(.defaultLow, for: .horizontal)

        let cancel = cancelButton
        cancel.target = self
        cancel.action = #selector(cancel(_:))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [NSView(), cancel, saveButton])
        buttonRow.spacing = 12

        let stack = NSStackView(views: [title, help, canvas, toolRow, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolRow.widthAnchor.constraint(equalTo: canvas.widthAnchor).isActive = true
        buttonRow.widthAnchor.constraint(equalTo: canvas.widthAnchor).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        panel.contentView = content
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(content.fittingSize)
        updateButtons()
    }

    private func updateButtons() {
        saveButton.isEnabled = !canvas.isEmpty && !canvas.isTrackpadMode
    }

    @objc private func inkChanged(_ sender: NSPopUpButton) {
        canvas.inkColor = inks[max(0, sender.indexOfSelectedItem)].1
    }

    @objc private func toggleTrackpad(_ sender: Any?) { canvas.setTrackpadMode(!canvas.isTrackpadMode) }
    @objc private func clearCanvas(_ sender: Any?) { canvas.clear() }
    @objc private func cancel(_ sender: Any?) { finish(nil) }
    @objc private func save(_ sender: Any?) { finish(canvas.pngData()) }

    private func finish(_ data: Data?) {
        canvas.setTrackpadMode(false)
        if let sheet = window { sheet.sheetParent?.endSheet(sheet) }
        completion?(data)
        completion = nil
    }
}
