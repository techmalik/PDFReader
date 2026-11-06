import AppKit
import PDFKit

private extension NSToolbarItem.Identifier {
    static let readerZoomOut = NSToolbarItem.Identifier("pdfreader.zoomOut")
    static let readerZoomIn = NSToolbarItem.Identifier("pdfreader.zoomIn")
    static let readerPrint = NSToolbarItem.Identifier("pdfreader.print")
    static let readerSearch = NSToolbarItem.Identifier("pdfreader.search")
}

final class ReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let pdfView: PDFView
    private let fileURL: URL?
    private let splitViewController = NSSplitViewController()
    private let sidebar: SidebarViewController
    private weak var searchItem: NSSearchToolbarItem?

    private var searchResults: [PDFSelection] = []
    private var searchIndex = 0
    private var lastQuery = ""

    private static var cascadePoint = NSPoint.zero
    private static let lastPageKey = "lastPageByFile"

    init(pdf: PDFDocument, fileURL: URL?) {
        let view = PDFView()
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
        [.toggleSidebar, .flexibleSpace, .readerZoomOut, .readerZoomIn, .readerPrint, .readerSearch]
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
