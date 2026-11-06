import AppKit
import PDFKit

/// One entry in the PDF's bookmark (outline) tree, copied out of PDFKit so the outline view has stable items.
final class OutlineNode {
    let title: String
    let destination: PDFDestination?
    let children: [OutlineNode]
    let startsExpanded: Bool

    init(_ outline: PDFOutline) {
        let label = outline.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = label.isEmpty ? "Untitled" : label
        destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
        children = (0..<outline.numberOfChildren).compactMap { outline.child(at: $0) }.map(OutlineNode.init)
        startsExpanded = outline.isOpen
    }
}

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private enum Mode: Int { case bookmarks = 0, pages = 1 }

    private weak var pdfView: PDFView?
    private let modePicker = NSSegmentedControl(labels: ["Bookmarks", "Pages"], trackingMode: .selectOne,
                                                target: nil, action: nil)
    private let outlineView = NSOutlineView()
    private let outlineScroll = NSScrollView()
    private let thumbnailView = PDFThumbnailView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "This PDF has no bookmarks.")
    private var roots: [OutlineNode] = []
    private let cellID = NSUserInterfaceItemIdentifier("OutlineCell")

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))

        modePicker.target = self
        modePicker.action = #selector(modeChanged(_:))
        modePicker.segmentDistribution = .fillEqually
        modePicker.controlSize = .regular

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.autoresizesOutlineColumn = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(outlineClicked(_:))

        outlineScroll.documentView = outlineView
        outlineScroll.hasVerticalScroller = true
        outlineScroll.autohidesScrollers = true
        outlineScroll.drawsBackground = false

        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 150, height: 190)
        thumbnailView.backgroundColor = .clear
        thumbnailView.labelFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        for v in [modePicker, outlineScroll, thumbnailView, emptyLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            modePicker.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            modePicker.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            modePicker.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            outlineScroll.topAnchor.constraint(equalTo: modePicker.bottomAnchor, constant: 8),
            outlineScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            outlineScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            outlineScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            thumbnailView.topAnchor.constraint(equalTo: modePicker.bottomAnchor, constant: 8),
            thumbnailView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            emptyLabel.centerYAnchor.constraint(equalTo: outlineScroll.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        view = container
    }

    /// Rebuilds the bookmark list from the current document.
    func reload() {
        _ = view  // make sure the views exist
        if let root = pdfView?.document?.outlineRoot {
            roots = (0..<root.numberOfChildren).compactMap { root.child(at: $0) }.map(OutlineNode.init)
        } else {
            roots = []
        }
        outlineView.reloadData()
        expandOpenNodes(roots)
        show(roots.isEmpty ? .pages : .bookmarks)
    }

    private func expandOpenNodes(_ nodes: [OutlineNode]) {
        for node in nodes where node.startsExpanded && !node.children.isEmpty {
            outlineView.expandItem(node)
            expandOpenNodes(node.children)
        }
    }

    private func show(_ mode: Mode) {
        modePicker.selectedSegment = mode.rawValue
        outlineScroll.isHidden = mode != .bookmarks
        emptyLabel.isHidden = mode != .bookmarks || !roots.isEmpty
        thumbnailView.isHidden = mode != .pages
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        show(Mode(rawValue: sender.selectedSegment) ?? .bookmarks)
    }

    // MARK: - Navigation

    @objc private func outlineClicked(_ sender: Any?) {
        navigate(to: outlineView.item(atRow: outlineView.clickedRow) as? OutlineNode)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        navigate(to: outlineView.item(atRow: outlineView.selectedRow) as? OutlineNode)
    }

    private func navigate(to node: OutlineNode?) {
        guard let destination = node?.destination else { return }
        pdfView?.go(to: destination)
    }

    // MARK: - Outline data source & delegate

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? OutlineNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? OutlineNode { return node.children[index] }
        return roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? OutlineNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = (outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView) ?? makeCell()
        let title = (item as? OutlineNode)?.title ?? ""
        cell.textField?.stringValue = title
        cell.toolTip = title
        return cell
    }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = cellID
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
