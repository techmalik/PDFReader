import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Who made PDFReader and where to reach them. Shown in the About panel and the Help menu.
enum Project {
    static let creator = "Malik Kabir"
    static let feedbackEmail = "techmaleek@gmail.com"
    static let repositoryURL = URL(string: "https://github.com/techmalik/PDFReader")!
    static let issuesURL = URL(string: "https://github.com/techmalik/PDFReader/issues")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// mailto: link with the app and macOS versions filled in, so feedback arrives with context.
    static var feedbackMailURL: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "PDFReader feedback (v\(version))"),
            URLQueryItem(name: "body", value: "\n\n—\nPDFReader \(version) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
        ]
        return components.url ?? URL(string: "mailto:\(feedbackEmail)")!
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var recentFilesWindow: RecentFilesWindowController?
    private let openRecentMenu = NSMenu(title: "Open Recent")
    private let didOfferDefaultKey = "didOfferToBecomeDefault"

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        Appearance.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SignaturesWindowController.shared.onPlace = { signature in
            guard let reader = ReaderWindowController.frontmost else { NSSound.beep(); return }
            reader.place(signature)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.offerToBecomeDefaultIfNeeded()
        }
    }

    /// Launched (or Dock icon clicked) with no PDF open: show the Recent PDFs window.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showRecentFiles(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Opening

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error = error as NSError?,
               !(error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) {
                NSApp.presentError(error)
            }
        }
    }

    @objc func showRecentFiles(_ sender: Any?) {
        if recentFilesWindow == nil { recentFilesWindow = RecentFilesWindowController() }
        recentFilesWindow?.showWindow(sender)
        recentFilesWindow?.window?.makeKeyAndOrderFront(sender)
    }

    // MARK: - About & feedback

    @objc func showAbout(_ sender: Any?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(string: "A lightweight, open-source PDF reader for macOS.\nCreated by \(Project.creator).\n\n", attributes: base)
        func link(_ text: String, _ url: URL) -> NSAttributedString {
            var attrs = base
            attrs[.link] = url
            return NSAttributedString(string: text, attributes: attrs)
        }
        credits.append(NSAttributedString(string: "Feedback: ", attributes: base))
        credits.append(link(Project.feedbackEmail, Project.feedbackMailURL))
        credits.append(NSAttributedString(string: "\nSource: ", attributes: base))
        credits.append(link("github.com/techmalik/PDFReader", Project.repositoryURL))
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "PDFReader",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func sendFeedback(_ sender: Any?) { NSWorkspace.shared.open(Project.feedbackMailURL) }
    @objc func openIssues(_ sender: Any?) { NSWorkspace.shared.open(Project.issuesURL) }
    @objc func openRepository(_ sender: Any?) { NSWorkspace.shared.open(Project.repositoryURL) }

    // MARK: - Appearance

    @objc func setAppearanceMode(_ sender: NSMenuItem) {
        Appearance.mode = Appearance.Mode(rawValue: sender.tag) ?? .system
    }

    @objc func setPageColors(_ sender: NSMenuItem) {
        Appearance.pageColors = Appearance.PageColors(rawValue: sender.tag) ?? .normal
    }

    @objc func showSignatures(_ sender: Any?) {
        SignaturesWindowController.shared.show()
    }

    @objc private func openRecentItem(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { AppDelegate.open(url) }
    }

    @objc private func clearRecents(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    // MARK: - Default PDF app

    private func isDefaultPDFApp() -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: .pdf),
              let id = Bundle(url: appURL)?.bundleIdentifier else { return false }
        return id == Bundle.main.bundleIdentifier
    }

    private func offerToBecomeDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !isDefaultPDFApp(), !defaults.bool(forKey: didOfferDefaultKey) else { return }
        defaults.set(true, forKey: didOfferDefaultKey)

        let alert = NSAlert()
        alert.messageText = "Make PDFReader your default PDF app?"
        alert.informativeText = "PDFs you double-click in Finder, Mail and elsewhere will open in PDFReader. You can change this later from the PDFReader menu."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            makeDefault(nil)
        }
    }

    @objc func makeDefault(_ sender: Any?) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .pdf) { error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if let error = error {
                    alert.alertStyle = .warning
                    alert.messageText = "Couldn’t make PDFReader the default PDF app"
                    alert.informativeText = error.localizedDescription +
                        "\n\nYou can also do it in Finder: select any PDF, choose File ▸ Get Info, pick PDFReader under “Open with”, then click “Change All…”."
                } else {
                    alert.messageText = "PDFReader is now your default PDF app"
                    alert.informativeText = "Double-clicking a PDF will open it in PDFReader."
                }
                alert.runModal()
            }
        }
    }

    // MARK: - Menu validation & Open Recent

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setAppearanceMode(_:)) {
            menuItem.state = menuItem.tag == Appearance.mode.rawValue ? .on : .off
            return true
        }
        if menuItem.action == #selector(setPageColors(_:)) {
            menuItem.state = menuItem.tag == Appearance.pageColors.rawValue ? .on : .off
            return true
        }
        if menuItem.action == #selector(makeDefault(_:)) {
            let isDefault = isDefaultPDFApp()
            menuItem.title = isDefault ? "PDFReader Is Your Default PDF App" : "Make PDFReader the Default PDF App"
            menuItem.state = isDefault ? .on : .off
            return !isDefault
        }
        if menuItem.action == #selector(clearRecents(_:)) {
            return !NSDocumentController.shared.recentDocumentURLs.isEmpty
        }
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === openRecentMenu else { return }
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent PDFs", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecents(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    // MARK: - Main menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // App menu
        let appMenu = NSMenu(title: "PDFReader")
        appMenu.addItem(withTitle: "About PDFReader", action: #selector(showAbout(_:)), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        let defaultItem = appMenu.addItem(withTitle: "Make PDFReader the Default PDF App", action: #selector(makeDefault(_:)), keyEquivalent: "")
        defaultItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PDFReader", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PDFReader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        // File
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recentItem = file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        openRecentMenu.delegate = self
        recentItem.submenu = openRecentMenu
        let recentWindow = file.addItem(withTitle: "Recent PDFs…", action: #selector(showRecentFiles(_:)), keyEquivalent: "o")
        recentWindow.keyEquivalentModifierMask = [.command, .shift]
        recentWindow.target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = file.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Revert to Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Properties…", action: #selector(ReaderWindowController.showProperties(_:)), keyEquivalent: "i")
        file.addItem(.separator())
        let pageSetup = file.addItem(withTitle: "Page Setup…", action: #selector(NSDocument.runPageLayout(_:)), keyEquivalent: "p")
        pageSetup.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Print…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        addSubmenu(file, to: main)

        // Edit
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find…", action: #selector(ReaderWindowController.focusSearch(_:)), keyEquivalent: "f")
        edit.addItem(withTitle: "Find Next", action: #selector(ReaderWindowController.findNextMatch(_:)), keyEquivalent: "g")
        let findPrev = edit.addItem(withTitle: "Find Previous", action: #selector(ReaderWindowController.findPreviousMatch(_:)), keyEquivalent: "g")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        addSubmenu(edit, to: main)

        // View
        let view = NSMenu(title: "View")
        let sidebar = view.addItem(withTitle: "Show/Hide Sidebar", action: #selector(ReaderWindowController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        let info = view.addItem(withTitle: "Show Info", action: #selector(ReaderWindowController.toggleInfoPane(_:)), keyEquivalent: "i")
        info.keyEquivalentModifierMask = [.command, .option]
        view.addItem(.separator())
        view.addItem(withTitle: "Actual Size", action: #selector(ReaderWindowController.zoomActualSize(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Zoom to Fit", action: #selector(ReaderWindowController.zoomToFit(_:)), keyEquivalent: "9")
        view.addItem(withTitle: "Zoom In", action: #selector(ReaderWindowController.zoomIn(_:)), keyEquivalent: "+")
        let zoomInAlt = view.addItem(withTitle: "Zoom In", action: #selector(ReaderWindowController.zoomIn(_:)), keyEquivalent: "=")
        zoomInAlt.isHidden = true
        zoomInAlt.allowsKeyEquivalentWhenHidden = true
        view.addItem(withTitle: "Zoom Out", action: #selector(ReaderWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(.separator())
        let modes: [(String, PDFDisplayMode)] = [
            ("Single Page", .singlePage),
            ("Continuous Scroll", .singlePageContinuous),
            ("Two Pages", .twoUp),
            ("Two Pages Continuous", .twoUpContinuous),
        ]
        for (title, mode) in modes {
            let item = view.addItem(withTitle: title, action: #selector(ReaderWindowController.setDisplayMode(_:)), keyEquivalent: "")
            item.tag = mode.rawValue
        }
        view.addItem(.separator())
        let appearanceMenu = NSMenu(title: "Appearance")
        for mode in Appearance.Mode.allCases {
            let item = appearanceMenu.addItem(withTitle: mode.title, action: #selector(setAppearanceMode(_:)), keyEquivalent: "")
            item.tag = mode.rawValue
            item.target = self
        }
        view.addItem(withTitle: "Appearance", action: nil, keyEquivalent: "").submenu = appearanceMenu
        let pageColorsMenu = NSMenu(title: "Page Colors")
        for colors in Appearance.PageColors.allCases {
            let item = pageColorsMenu.addItem(withTitle: colors.title, action: #selector(setPageColors(_:)), keyEquivalent: "")
            item.tag = colors.rawValue
            item.target = self
        }
        view.addItem(withTitle: "Page Colors", action: nil, keyEquivalent: "").submenu = pageColorsMenu
        let darkToggle = view.addItem(withTitle: "Toggle Dark Pages", action: #selector(ReaderWindowController.toggleDarkPages(_:)), keyEquivalent: "d")
        darkToggle.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(.separator())
        let fullScreen = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        addSubmenu(view, to: main)

        // Sign
        let sign = NSMenu(title: "Sign")
        sign.addItem(withTitle: "Draw New Signature…", action: #selector(ReaderWindowController.drawNewSignature(_:)), keyEquivalent: "")
        sign.addItem(withTitle: "Import Signature Image…", action: #selector(ReaderWindowController.importSignature(_:)), keyEquivalent: "")
        let manage = sign.addItem(withTitle: "Manage Signatures…", action: #selector(showSignatures(_:)), keyEquivalent: "")
        manage.target = self
        addSubmenu(sign, to: main)

        // Go
        let go = NSMenu(title: "Go")
        let prev = go.addItem(withTitle: "Previous Page", action: #selector(ReaderWindowController.goToPreviousPage(_:)), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        prev.keyEquivalentModifierMask = [.command, .option]
        let next = go.addItem(withTitle: "Next Page", action: #selector(ReaderWindowController.goToNextPage(_:)), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        next.keyEquivalentModifierMask = [.command, .option]
        go.addItem(withTitle: "First Page", action: #selector(ReaderWindowController.goToFirstPage(_:)), keyEquivalent: "")
        go.addItem(withTitle: "Last Page", action: #selector(ReaderWindowController.goToLastPage(_:)), keyEquivalent: "")
        go.addItem(withTitle: "Go to Page…", action: #selector(ReaderWindowController.goToPageNumber(_:)), keyEquivalent: "l")
        go.addItem(.separator())
        go.addItem(withTitle: "Back", action: #selector(ReaderWindowController.goBack(_:)), keyEquivalent: "[")
        go.addItem(withTitle: "Forward", action: #selector(ReaderWindowController.goForward(_:)), keyEquivalent: "]")
        addSubmenu(go, to: main)

        // Window
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        addSubmenu(window, to: main)
        NSApp.windowsMenu = window

        // Help
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Send Feedback…", action: #selector(sendFeedback(_:)), keyEquivalent: "").target = self
        help.addItem(withTitle: "Report an Issue on GitHub…", action: #selector(openIssues(_:)), keyEquivalent: "").target = self
        help.addItem(.separator())
        help.addItem(withTitle: "PDFReader on GitHub", action: #selector(openRepository(_:)), keyEquivalent: "").target = self
        addSubmenu(help, to: main)
        NSApp.helpMenu = help

        return main
    }

    private func addSubmenu(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
