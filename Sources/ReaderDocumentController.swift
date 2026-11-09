import AppKit

/// Keeps PDFReader's own list of recently opened PDFs.
///
/// AppKit's built-in list follows System Settings ▸ Desktop & Dock ▸ "Recent documents, apps,
/// and servers". When that is set to None, macOS records nothing, so File ▸ Open Recent and the
/// Recent PDFs window would stay empty. This list is stored in PDFReader's own preferences instead.
final class ReaderDocumentController: NSDocumentController {
    static let recentsDidChange = Notification.Name("PDFReaderRecentsDidChange")
    private static let key = "recentPDFs"
    private static let limit = 20

    override var maximumRecentDocumentCount: Int { Self.limit }

    override init() {
        super.init()
        seedFromReadingPositionsIfNeeded()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    /// First run with this list: start it from the PDFs PDFReader already remembers a page for,
    /// most recently used first, so people upgrading don't see an empty list.
    private func seedFromReadingPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.key) == nil,
              let positions = defaults.dictionary(forKey: "lastPageByFile") else { return }
        let fm = FileManager.default
        let paths = positions.keys
            .filter { fm.fileExists(atPath: $0) && !$0.hasPrefix("/private/tmp/") }
            .map { path -> (String, Date) in
                let url = URL(fileURLWithPath: path)
                let date = (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate ?? .distantPast
                return (path, date)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        defaults.set(Array(paths.prefix(Self.limit)), forKey: Self.key)
    }

    override var recentDocumentURLs: [URL] {
        (UserDefaults.standard.stringArray(forKey: Self.key) ?? []).map { URL(fileURLWithPath: $0) }
    }

    override func noteNewRecentDocumentURL(_ url: URL) {
        guard url.isFileURL else { return }
        let path = url.standardizedFileURL.path
        var paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(Self.limit)), forKey: Self.key)
        NotificationCenter.default.post(name: Self.recentsDidChange, object: nil)
        super.noteNewRecentDocumentURL(url) // keeps the Dock menu in step when macOS records recents
    }

    override func clearRecentDocuments(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: Self.key)
        super.clearRecentDocuments(sender)
        NotificationCenter.default.post(name: Self.recentsDidChange, object: nil)
    }
}
