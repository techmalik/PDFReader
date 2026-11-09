import AppKit
import PDFKit

private extension NSToolbarItem.Identifier {
    static let readerZoomOut = NSToolbarItem.Identifier("pdfreader.zoomOut")
    static let readerZoomIn = NSToolbarItem.Identifier("pdfreader.zoomIn")
    static let readerPrint = NSToolbarItem.Identifier("pdfreader.print")
    static let readerSearch = NSToolbarItem.Identifier("pdfreader.search")
    static let readerSign = NSToolbarItem.Identifier("pdfreader.sign")
    static let readerProperties = NSToolbarItem.Identifier("pdfreader.properties")
    static let readerDarkPages = NSToolbarItem.Identifier("pdfreader.darkPages")
}

final class ReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation, NSMenuDelegate {
    let pdfView: SigningPDFView
    private let fileURL: URL?
    private let splitViewController = NSSplitViewController()
    private let sidebar: SidebarViewController
    private weak var searchItem: NSSearchToolbarItem?
    private let signMenu = NSMenu(title: "Sign")
    private var propertiesSheet: PropertiesSheet?

    /// The reader window the user is working in, for actions that come from other windows.
    static var frontmost: ReaderWindowController? {
        NSApp.orderedWindows.lazy.compactMap { $0.windowController as? ReaderWindowController }.first
    }

    private var searchResults: [PDFSelection] = []
    private var searchIndex = 0
    private var lastQuery = ""

    private static var cascadePoint = NSPoint.zero
    private static let lastPageKey = "lastPageByFile"

    init(pdf: PDFDocument, fileURL: URL?) {
        let view = SigningPDFView()
        pdfView = view
        self.fileURL = fileURL
        sidebar = SidebarViewController(pdfView: view)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(1100, screenFrame.width * 0.85), height: min(900, screenFrame.height * 0.9))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 400)
        window.toolbarStyle = .unified
        // Open each PDF as a tab in the existing window, regardless of the system "Prefer tabs" setting.
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "PDFReaderDocument"
        super.init(window: window)

        window.delegate = self
        configurePDFView(with: pdf)
        configureLayout(in: window, size: size)
        configureToolbar(in: window)

        window.center()
        Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)
        window.initialFirstResponder = pdfView

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: pdfView)
        sidebar.reload()
        restoreLastPage()
        updatePageSubtitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Setup

    private func configurePDFView(with pdf: PDFDocument) {
        pdfView.document = pdf
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.displayDirection = .vertical
    }

    private func configureLayout(in window: NSWindow, size: NSSize) {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true

        let content = NSViewController()
        pdfView.frame = NSRect(origin: .zero, size: size)
        content.view = pdfView
        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = 300

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)
        splitViewController.view.frame = NSRect(origin: .zero, size: size)
        window.contentViewController = splitViewController
        window.setContentSize(size)
    }

    private func configureToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "PDFReaderToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, .readerZoomOut, .readerZoomIn, .readerSign, .readerProperties, .readerDarkPages, .readerPrint, .readerSearch]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .readerZoomOut:
            return makeButtonItem(itemIdentifier, "Zoom Out", "minus.magnifyingglass", #selector(zoomOut(_:)))
        case .readerZoomIn:
            return makeButtonItem(itemIdentifier, "Zoom In", "plus.magnifyingglass", #selector(zoomIn(_:)))
        case .readerPrint:
            return makeButtonItem(itemIdentifier, "Print", "printer", #selector(printFromToolbar(_:)))
        case .readerDarkPages:
            return makeButtonItem(itemIdentifier, "Dark Pages", "moon", #selector(toggleDarkPages(_:)))
        case .readerProperties:
            return makeButtonItem(itemIdentifier, "Properties", "info.circle", #selector(showProperties(_:)))
        case .readerSign:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Sign"
            item.paletteLabel = "Sign"
            item.toolTip = "Add a signature"
            item.image = NSImage(systemSymbolName: "signature", accessibilityDescription: "Sign")
            item.showsIndicator = true
            signMenu.delegate = self
            item.menu = signMenu
            return item
        case .readerSearch:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Search"
            item.searchField.placeholderString = "Search"
            item.searchField.sendsWholeSearchString = true
            item.searchField.target = self
            item.searchField.action = #selector(searchFieldSubmitted(_:))
            searchItem = item
            return item
        default:
            return nil
        }
    }

    private func makeButtonItem(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String,
                                _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    @objc private func printFromToolbar(_ sender: Any?) {
        document?.printDocument(sender)
    }

    // MARK: - Sidebar & zoom (forwarded so they work whatever has keyboard focus)

    @objc func toggleSidebar(_ sender: Any?) { splitViewController.toggleSidebar(sender) }
    @objc func zoomIn(_ sender: Any?) { pdfView.zoomIn(sender) }
    @objc func zoomOut(_ sender: Any?) { pdfView.zoomOut(sender) }
    @objc func zoomActualSize(_ sender: Any?) { pdfView.autoScales = false; pdfView.scaleFactor = 1.0 }
    @objc func zoomToFit(_ sender: Any?) { pdfView.autoScales = true }

    @objc func setDisplayMode(_ sender: NSMenuItem) {
        guard let mode = PDFDisplayMode(rawValue: sender.tag) else { return }
        let page = pdfView.currentPage
        pdfView.displayMode = mode
        if let page = page { pdfView.go(to: page) }
    }

    // MARK: - Navigation

    @objc func goToPreviousPage(_ sender: Any?) { pdfView.goToPreviousPage(sender) }
    @objc func goToNextPage(_ sender: Any?) { pdfView.goToNextPage(sender) }
    @objc func goToFirstPage(_ sender: Any?) { pdfView.goToFirstPage(sender) }
    @objc func goToLastPage(_ sender: Any?) { pdfView.goToLastPage(sender) }
    @objc func goBack(_ sender: Any?) { pdfView.goBack(sender) }
    @objc func goForward(_ sender: Any?) { pdfView.goForward(sender) }

    @objc func goToPageNumber(_ sender: Any?) {
        guard let window = window, let doc = pdfView.document, doc.pageCount > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Page"
        alert.informativeText = "Enter a page number (1–\(doc.pageCount))."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let number = Int(field.stringValue.trimmingCharacters(in: .whitespaces)),
                  let page = doc.page(at: max(0, min(doc.pageCount - 1, number - 1))) else { return }
            self?.pdfView.go(to: page)
        }
    }

    @objc private func pageChanged(_ notification: Notification) {
        updatePageSubtitle()
    }

    private func updatePageSubtitle() {
        guard let doc = pdfView.document, let page = pdfView.currentPage else { return }
        window?.subtitle = "Page \(doc.index(for: page) + 1) of \(doc.pageCount)"
    }

    // MARK: - Search

    @objc func focusSearch(_ sender: Any?) {
        searchItem?.beginSearchInteraction()
    }

    @objc private func searchFieldSubmitted(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let doc = pdfView.document else {
            clearSearch()
            return
        }
        if query == lastQuery, !searchResults.isEmpty {
            stepSearch(by: 1)
            return
        }
        lastQuery = query
        searchResults = doc.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        searchIndex = 0
        if searchResults.isEmpty {
            pdfView.highlightedSelections = nil
            NSSound.beep()
            window?.subtitle = "No matches for “\(query)”"
        } else {
            showCurrentSearchResult()
        }
    }

    @objc func findNextMatch(_ sender: Any?) { stepSearch(by: 1) }
    @objc func findPreviousMatch(_ sender: Any?) { stepSearch(by: -1) }

    private func stepSearch(by delta: Int) {
        guard !searchResults.isEmpty else { focusSearch(nil); return }
        searchIndex = (searchIndex + delta + searchResults.count) % searchResults.count
        showCurrentSearchResult()
    }

    private func showCurrentSearchResult() {
        let selection = searchResults[searchIndex]
        pdfView.highlightedSelections = searchResults
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
        if let doc = pdfView.document, let page = selection.pages.first {
            window?.subtitle = "Match \(searchIndex + 1) of \(searchResults.count) · Page \(doc.index(for: page) + 1) of \(doc.pageCount)"
        }
    }

    private func clearSearch() {
        lastQuery = ""
        searchResults = []
        pdfView.highlightedSelections = nil
        pdfView.clearSelection()
        updatePageSubtitle()
    }

    // MARK: - Dark pages

    /// Quick switch between normal and dark pages (View ▸ Page Colors has all the options).
    @objc func toggleDarkPages(_ sender: Any?) {
        let showingDark = Appearance.wantsDarkPages(for: pdfView.effectiveAppearance)
        Appearance.pageColors = showingDark ? .normal : .dark
    }

    // MARK: - Properties

    private var readerDocument: PDFReaderDocument? { document as? PDFReaderDocument }

    @objc func showProperties(_ sender: Any?) {
        guard let window = window, let doc = readerDocument, let pdf = pdfView.document,
              propertiesSheet == nil, window.attachedSheet == nil else { return }
        let sheet = PropertiesSheet(document: doc, pdf: pdf)
        propertiesSheet = sheet
        sheet.begin(for: window) { [weak self] in self?.propertiesSheet = nil }
    }

    // MARK: - Signatures

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === signMenu else { return }
        menu.removeAllItems()
        let store = SignatureStore.shared
        if store.signatures.isEmpty {
            let empty = NSMenuItem(title: "No Saved Signatures", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for signature in store.signatures {
            let item = NSMenuItem(title: "", action: #selector(placeSavedSignature(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = signature.id
            item.image = Self.menuThumbnail(for: signature.image)
            item.toolTip = "Place this signature on the current page"
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let draw = menu.addItem(withTitle: "Draw New Signature…", action: #selector(drawNewSignature(_:)), keyEquivalent: "")
        draw.target = self
        let importItem = menu.addItem(withTitle: "Import Signature Image…", action: #selector(importSignature(_:)), keyEquivalent: "")
        importItem.target = self
        if store.isFull {
            draw.isEnabled = false
            importItem.isEnabled = false
            draw.toolTip = "You have \(SignatureStore.maxCount) saved signatures. Delete one in Manage Signatures to add another."
        }
        let manage = menu.addItem(withTitle: "Manage Signatures…", action: #selector(manageSignatures(_:)), keyEquivalent: "")
        manage.target = self
    }

    /// A white tile with the signature on it, so light ink stays visible in dark mode menus.
    private static func menuThumbnail(for image: NSImage) -> NSImage {
        let size = NSSize(width: 180, height: 44)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let inner = rect.insetBy(dx: 8, dy: 5)
            let scale = min(inner.width / max(image.size.width, 1), inner.height / max(image.size.height, 1))
            let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: inner.midX - drawn.width / 2, y: inner.midY - drawn.height / 2,
                                  width: drawn.width, height: drawn.height))
            return true
        }
    }

    @objc private func placeSavedSignature(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let signature = SignatureStore.shared.signatures.first(where: { $0.id == id }) else { return }
        place(signature)
    }

    /// Places a saved signature on the current page (if this PDF can be changed).
    func place(_ signature: SavedSignature) {
        if let reason = readerDocument?.editingBlockedReason {
            guard let window = window else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "This PDF can’t be signed"
            alert.informativeText = reason
            alert.beginSheetModal(for: window)
            return
        }
        window?.makeKeyAndOrderFront(nil)
        pdfView.place(signature.image)
    }

    @objc func drawNewSignature(_ sender: Any?) { SignaturesWindowController.shared.show(startDrawing: true) }
    @objc func manageSignatures(_ sender: Any?) { SignaturesWindowController.shared.show() }
    @objc func importSignature(_ sender: Any?) {
        SignaturesWindowController.shared.show()
        SignaturesWindowController.shared.importImage(nil)
    }

    /// Called by the document just before it writes the file.
    func prepareForSave() {
        pdfView.deselectSignature()
    }

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(setDisplayMode(_:)):
            menuItem.state = pdfView.displayMode.rawValue == menuItem.tag ? .on : .off
            return true
        case #selector(zoomIn(_:)): return pdfView.canZoomIn
        case #selector(zoomOut(_:)): return pdfView.canZoomOut
        case #selector(goToPreviousPage(_:)), #selector(goToFirstPage(_:)): return pdfView.canGoToPreviousPage
        case #selector(goToNextPage(_:)), #selector(goToLastPage(_:)): return pdfView.canGoToNextPage
        case #selector(goBack(_:)): return pdfView.canGoBack
        case #selector(goForward(_:)): return pdfView.canGoForward
        case #selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)): return !searchResults.isEmpty
        case #selector(showProperties(_:)): return propertiesSheet == nil
        case #selector(toggleSidebar(_:)):
            let collapsed = splitViewController.splitViewItems.first?.isCollapsed ?? false
            menuItem.title = collapsed ? "Show Sidebar" : "Hide Sidebar"
            return true
        default:
            return true
        }
    }

    // MARK: - Remember last page

    private func restoreLastPage() {
        guard let path = fileURL?.path,
              let saved = UserDefaults.standard.dictionary(forKey: Self.lastPageKey)?[path] as? Int,
              saved > 0, let page = pdfView.document?.page(at: saved) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.pdfView.go(to: page)
            self?.updatePageSubtitle()
        }
    }

    private func saveLastPage() {
        guard let path = fileURL?.path, let doc = pdfView.document, let page = pdfView.currentPage else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.lastPageKey) ?? [:]
        all[path] = doc.index(for: page)
        if all.count > 200 { all = [path: doc.index(for: page)] }
        UserDefaults.standard.set(all, forKey: Self.lastPageKey)
    }

    func windowWillClose(_ notification: Notification) {
        saveLastPage()
    }
}
