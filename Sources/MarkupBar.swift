import AppKit

/// The bar shown above the page while marking up (Markup toolbar button, ⇧⌘A):
/// tool, colour and thickness on one row, plus Done.
final class MarkupBar: NSView {
    var onDone: (() -> Void)?
    var onToolChange: ((MarkupTool) -> Void)?

    private let tools = NSSegmentedControl()
    private let colors = NSSegmentedControl()
    private let thickness = NSSegmentedControl()
    private let hint = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        sync()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)),
                                               name: MarkupSettings.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 40) }

    private func build() {
        tools.segmentCount = MarkupTool.allCases.count
        tools.trackingMode = .selectOne
        for tool in MarkupTool.allCases {
            let image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title)
            tools.setImage(image, forSegment: tool.rawValue)
            if image == nil { tools.setLabel(tool.title, forSegment: tool.rawValue) }
            tools.setToolTip(tool.title, forSegment: tool.rawValue)
            tools.setWidth(34, forSegment: tool.rawValue)
        }
        tools.target = self
        tools.action = #selector(toolPicked(_:))
        tools.setAccessibilityLabel("Markup tool")

        colors.segmentCount = MarkupSettings.palette.count
        colors.trackingMode = .selectOne
        for (index, swatch) in MarkupSettings.palette.enumerated() {
            let swatchImage = Self.swatchImage(swatch.color, diameter: 14)
            swatchImage.accessibilityDescription = swatch.name
            colors.setImage(swatchImage, forSegment: index)
            colors.setToolTip(swatch.name, forSegment: index)
            colors.setWidth(28, forSegment: index)
        }
        colors.target = self
        colors.action = #selector(colorPicked(_:))
        colors.setAccessibilityLabel("Color")

        thickness.segmentCount = MarkupSettings.thicknessNames.count
        thickness.trackingMode = .selectOne
        for (index, name) in MarkupSettings.thicknessNames.enumerated() {
            let lineImage = Self.lineImage(width: [1.5, 3.5, 6.5][index])
            lineImage.accessibilityDescription = "\(name) line"
            thickness.setImage(lineImage, forSegment: index)
            thickness.setToolTip("\(name) line", forSegment: index)
            thickness.setWidth(34, forSegment: index)
        }
        thickness.target = self
        thickness.action = #selector(thicknessPicked(_:))
        thickness.setAccessibilityLabel("Thickness")

        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.lineBreakMode = .byTruncatingTail

        let done = NSButton(title: "Done", target: self, action: #selector(donePressed(_:)))
        done.bezelStyle = .rounded
        done.controlSize = .small
        done.toolTip = "Stop marking up (Esc)"

        let row = NSStackView(views: [tools, Self.divider(), colors, Self.divider(), thickness, hint, done])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        // Keep the controls pinned on the left; only the hint stretches or truncates,
        // so buttons never move when the hint text changes.
        for control in [tools, colors, thickness, done] {
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        hint.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        hint.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        row.spacing = 10
        row.setCustomSpacing(16, after: thickness)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    private func sync() {
        let tool = MarkupSettings.tool
        tools.selectedSegment = tool.rawValue
        colors.selectedSegment = MarkupSettings.colorIndex
        thickness.selectedSegment = MarkupSettings.thicknessIndex
        thickness.isEnabled = tool.usesThickness
        colors.isEnabled = tool != .eraser
        hint.stringValue = tool.help
    }

    @objc private func settingsChanged(_ notification: Notification) { sync() }

    @objc private func toolPicked(_ sender: NSSegmentedControl) {
        guard let tool = MarkupTool(rawValue: sender.selectedSegment) else { return }
        MarkupSettings.tool = tool
        onToolChange?(tool)
    }

    @objc private func colorPicked(_ sender: NSSegmentedControl) { MarkupSettings.colorIndex = sender.selectedSegment }
    @objc private func thicknessPicked(_ sender: NSSegmentedControl) { MarkupSettings.thicknessIndex = sender.selectedSegment }
    @objc private func donePressed(_ sender: Any?) { onDone?() }

    // MARK: - Images

    static func swatchImage(_ color: NSColor, diameter: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            color.setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            circle.lineWidth = 0.75
            circle.stroke()
            return true
        }
    }

    private static func lineImage(width: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { rect in
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 3, y: rect.midY))
            line.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY))
            line.lineWidth = width
            line.lineCapStyle = .round
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return box
    }
}
