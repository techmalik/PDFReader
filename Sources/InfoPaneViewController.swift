import AppKit
import PDFKit

/// The Info pane on the right of the reader window (ⓘ toolbar button, ⌥⌘I): file, document,
/// page and security details. Read-only; "Edit Properties…" opens the Properties sheet.
final class InfoPaneViewController: NSViewController {
    private weak var pdfView: PDFView?
    weak var document: PDFReaderDocument? { didSet { refresh() } }
    var onEdit: (() -> Void)?

    private let thumbnail = NSImageView()
    private let nameLabel = NSTextField(wrappingLabelWithString: "")
    private let kindLabel = NSTextField(labelWithString: "")
    private let pageHeading = NSTextField(labelWithString: "Page")
    private let stack = NSStackView()
    private var values: [Field: NSTextField] = [:]
    private var wrappingLabels: [NSTextField] = []
    private var thumbnailHeight: NSLayoutConstraint?

    private enum Field: CaseIterable {
        case title, author, subject, keywords, creator, producer, created, modified
        case pageSize, paper, orientation, allPages
        case fileName, fileSize, location, pageCount, version
        case encryption, printing, copying, changes
    }

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Layout

    override func loadView() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 20, right: 16)

        // Header: first-page thumbnail, file name, kind and size.
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.borderWidth = 1
        thumbnail.layer?.borderColor = NSColor.separatorColor.cgColor
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        let height = thumbnail.heightAnchor.constraint(equalToConstant: 140)
        height.isActive = true
        thumbnailHeight = height
        nameLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        nameLabel.isSelectable = true
        kindLabel.textColor = .secondaryLabelColor
        kindLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        wrappingLabels.append(nameLabel)
        stack.addArrangedSubview(thumbnail)
        stack.setCustomSpacing(12, after: thumbnail)
        stack.addArrangedSubview(nameLabel)
        stack.setCustomSpacing(2, after: nameLabel)
        stack.addArrangedSubview(kindLabel)

        addSection("Document", [
            (.title, "Title"), (.author, "Author"), (.subject, "Subject"), (.keywords, "Keywords"),
            (.creator, "Creator"), (.producer, "Producer"), (.created, "Created"), (.modified, "Modified"),
        ])
        addSection(pageHeading, [
            (.pageSize, "Page size"), (.paper, "Paper"), (.orientation, "Orientation"), (.allPages, "All pages"),
        ])
        addSection("File", [
            (.fileName, "Name"), (.fileSize, "Document size"), (.location, "Location"),
            (.pageCount, "Pages"), (.version, "PDF version"),
        ])
        addSection("Security", [
            (.encryption, "Encryption"), (.printing, "Printing"), (.copying, "Copying text"), (.changes, "Changes"),
        ])

        let edit = NSButton(title: "Edit Properties…", target: self, action: #selector(editProperties(_:)))
        edit.toolTip = "Rename the file or edit its title, author, subject, keywords and creator (⌘I)"
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(edit)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = documentView
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            documentView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        for view in stack.arrangedSubviews where view !== edit && view !== kindLabel {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        scroll.frame = container.bounds
        scroll.autoresizingMask = [.width, .height]
        container.addSubview(scroll)
        view = container
        refresh()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            thumbnail.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        // Wrapping labels need an explicit width to compute their height inside a scroll view.
        let width = max(80, view.bounds.width - 32)
        var changed = false
        for label in wrappingLabels where label.preferredMaxLayoutWidth != width {
            label.preferredMaxLayoutWidth = width
            changed = true
        }
        if changed { view.needsLayout = true }
    }

    private func addSection(_ title: String, _ fields: [(Field, String)]) {
        addSection(NSTextField(labelWithString: title), fields)
    }

    private func addSection(_ heading: NSTextField, _ fields: [(Field, String)]) {
        let rule = NSBox()
        rule.boxType = .separator
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(rule)
        heading.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        stack.addArrangedSubview(heading)
        for (field, caption) in fields {
            let captionLabel = NSTextField(labelWithString: caption)
            captionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            captionLabel.textColor = .secondaryLabelColor
            let value = NSTextField(wrappingLabelWithString: "—")
            value.isSelectable = true
            values[field] = value
            wrappingLabels.append(value)
            let row = NSStackView(views: [captionLabel, value])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 1
            stack.addArrangedSubview(row)
            value.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        }
    }

    // MARK: - Content

    /// Re-reads everything (after opening, saving, renaming or editing properties).
    func refresh() {
        guard isViewLoaded, let pdf = pdfView?.document else { return }
        let attrs = pdf.documentAttributes ?? [:]
        let url = document?.fileURL
        let resources = try? url?.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])

        let name = url?.lastPathComponent ?? document?.displayName ?? "Untitled"
        nameLabel.stringValue = name
        let size = resources?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        kindLabel.stringValue = ["PDF document", size].compactMap { $0 }.joined(separator: " · ")

        if let first = pdf.page(at: 0) {
            let image = first.thumbnail(of: NSSize(width: 456, height: 280), for: .cropBox)
            thumbnail.image = image
            let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1.4
            thumbnailHeight?.constant = min(140, max(60, 228 * aspect))
        }

        func text(_ key: PDFDocumentAttribute) -> String? {
            let value = (attrs[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        set(.title, text(.titleAttribute))
        set(.author, text(.authorAttribute))
        set(.subject, text(.subjectAttribute))
        if let list = attrs[PDFDocumentAttribute.keywordsAttribute] as? [Any] {
            set(.keywords, list.map { "\($0)" }.joined(separator: ", "))
        } else {
            set(.keywords, text(.keywordsAttribute))
        }
        set(.creator, text(.creatorAttribute))
        set(.producer, text(.producerAttribute))
        set(.created, Self.format((attrs[PDFDocumentAttribute.creationDateAttribute] as? Date) ?? resources?.creationDate))
        set(.modified, Self.format((attrs[PDFDocumentAttribute.modificationDateAttribute] as? Date)
                                    ?? resources?.contentModificationDate))

        set(.fileName, name)
        set(.fileSize, size.map { "\($0) (\(Self.bytes(resources?.fileSize ?? 0)) bytes)" })
        set(.location, url?.deletingLastPathComponent().path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
        set(.pageCount, "\(pdf.pageCount)")
        set(.version, "\(pdf.majorVersion).\(pdf.minorVersion)")

        set(.encryption, pdf.isEncrypted ? "Encrypted" : "None")
        set(.printing, pdf.allowsPrinting ? "Allowed" : "Not allowed")
        set(.copying, pdf.allowsCopying ? "Allowed" : "Not allowed")
        set(.changes, document?.editingBlockedReason == nil ? "Allowed" : "Not allowed")

        let sizes = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }.map(Self.displaySize)
        if let first = sizes.first {
            let uniform = sizes.allSatisfy { abs($0.width - first.width) < 1 && abs($0.height - first.height) < 1 }
            set(.allPages, uniform ? "Same size" : "Sizes vary")
        }
        refreshPage()
    }

    /// Updates the current-page details (called as the reader scrolls).
    func refreshPage() {
        guard isViewLoaded, let pdf = pdfView?.document, let page = pdfView?.currentPage else { return }
        pageHeading.stringValue = "Page \(pdf.index(for: page) + 1) of \(pdf.pageCount)"
        let size = Self.displaySize(page)
        set(.pageSize, Self.describe(size))
        set(.paper, Self.paperName(for: size) ?? "Custom")
        let orientation = abs(size.width - size.height) < 1 ? "Square" : (size.width > size.height ? "Landscape" : "Portrait")
        set(.orientation, page.rotation == 0 ? orientation : "\(orientation) (rotated \(page.rotation)°)")
    }

    private func set(_ field: Field, _ value: String?) {
        guard let label = values[field] else { return }
        let shown = value ?? "—"
        label.stringValue = shown
        label.textColor = value == nil ? .tertiaryLabelColor : .labelColor
        label.toolTip = value
    }

    @objc private func editProperties(_ sender: Any?) { onEdit?() }

    // MARK: - Formatting

    /// The page as it's shown: crop box size, with width and height swapped for 90°/270° rotation.
    private static func displaySize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox).size
        return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    private static func describe(_ size: CGSize) -> String {
        let inches = "\(number(size.width / 72, digits: 2)) × \(number(size.height / 72, digits: 2)) in"
        let mm = "\(number(size.width / 72 * 25.4, digits: 0)) × \(number(size.height / 72 * 25.4, digits: 0)) mm"
        let points = "\(number(size.width, digits: 0)) × \(number(size.height, digits: 0)) pt"
        let usesMetric: Bool
        if #available(macOS 13, *) { usesMetric = Locale.current.measurementSystem != .us }
        else { usesMetric = Locale.current.usesMetricSystem }
        return usesMetric ? "\(mm)\n\(inches) · \(points)" : "\(inches)\n\(mm) · \(points)"
    }

    private static let papers: [(String, CGFloat, CGFloat)] = [
        ("US Letter", 612, 792), ("US Legal", 612, 1008), ("Tabloid", 792, 1224), ("Executive", 522, 756),
        ("A3", 842, 1191), ("A4", 595, 842), ("A5", 420, 595), ("A6", 298, 420),
        ("B4", 709, 1001), ("B5", 499, 709), ("Envelope #10", 297, 684), ("Envelope DL", 312, 624),
    ]

    private static func paperName(for size: CGSize) -> String? {
        let short = min(size.width, size.height), long = max(size.width, size.height)
        return papers.first { abs($0.1 - short) <= 3 && abs($0.2 - long) <= 3 }?.0
    }

    private static func number(_ value: CGFloat, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: Double(value))) ?? "\(value)"
    }

    private static func bytes(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func format(_ date: Date?) -> String? { date.map(dateFormatter.string(from:)) }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
