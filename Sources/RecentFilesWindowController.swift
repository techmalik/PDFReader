import AppKit
import QuickLookThumbnailing

/// Start window listing recently opened PDFs (the same list as File ▸ Open Recent).
final class RecentFilesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No recent PDFs yet. Click “Open PDF…” to get started.")
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear List", target: nil, action: nil)
    private var urls: [URL] = []
    private var thumbnails: [URL: NSImage] = [:]
    private let cellID = NSUserInterfaceItemIdentifier("RecentCell")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Recent PDFs"
        window.minSize = NSSize(width: 420, height: 320)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(in: window)
        window.center()
        window.setFrameAutosaveName("PDFReaderRecentWindow")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.makeFirstResponder(tableView)
    }

    // MARK: - UI

    private func buildContent(in window: NSWindow) {
        let content = NSView()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: "PDFReader")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Open a PDF, or pick one you’ve viewed recently.")
        subtitle.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 52
        tableView.style = .inset
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelected(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let openOther = NSButton(title: "Open PDF…", target: nil, action: #selector(NSDocumentController.openDocument(_:)))
        openButton.target = self
        openButton.action = #selector(openSelected(_:))
        openButton.keyEquivalent = "\r"
        clearButton.target = self
        clearButton.action = #selector(clearList(_:))

        for v in [icon, title, subtitle, scroll, emptyLabel, clearButton, openOther, openButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.bottomAnchor.constraint(equalTo: icon.centerYAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: openButton.topAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),

            clearButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            clearButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            openButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            openButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            openOther.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -10),
            openOther.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
        ])

        window.contentView = content
    }

    private func reload() {
        let fm = FileManager.default
        urls = NSDocumentController.shared.recentDocumentURLs.filter { fm.fileExists(atPath: $0.path) }
        tableView.reloadData()
        if !urls.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        emptyLabel.isHidden = !urls.isEmpty
        clearButton.isEnabled = !urls.isEmpty
        updateOpenButton()
        for url in urls where thumbnails[url] == nil { loadThumbnail(for: url) }
    }

    private func updateOpenButton() {
        openButton.isEnabled = tableView.selectedRow >= 0
    }

    private func loadThumbnail(for url: URL) {
        let scale = window?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 36, height: 44),
                                                   scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.thumbnails[url] = image
                if let row = self.urls.firstIndex(of: url) {
                    self.tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func openSelected(_ sender: Any?) {
        let row = (sender as? NSTableView)?.clickedRow ?? -1
        let index = row >= 0 ? row : tableView.selectedRow
        guard urls.indices.contains(index) else { return }
        AppDelegate.open(urls[index])
        window?.close()
    }

    @objc private func clearList(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
        reload()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { urls.count }

    func tableViewSelectionDidChange(_ notification: Notification) { updateOpenButton() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: cellID, owner: self) as? RecentFileCell) ?? {
            let c = RecentFileCell()
            c.identifier = cellID
            return c
        }()
        let url = urls[row]
        cell.nameLabel.stringValue = url.lastPathComponent
        cell.pathLabel.stringValue = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        cell.iconView.image = thumbnails[url] ?? NSWorkspace.shared.icon(forFile: url.path)
        cell.toolTip = url.path
        return cell
    }
}

private final class RecentFileCell: NSTableCellView {
    let iconView = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let pathLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        for v in [iconView, nameLabel, pathLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 0),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
        ])
        textField = nameLabel
        imageView = iconView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
