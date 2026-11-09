import AppKit
import PDFKit

/// A PDF document. Its properties can be edited and signatures added, then saved back to the file.
/// The class name is referenced from Info.plist (NSDocumentClass).
@objc(PDFReaderDocument)
final class PDFReaderDocument: NSDocument {
    private(set) var pdf: PDFDocument?

    override class var autosavesInPlace: Bool { false }

    /// Renames and moves change the file's name and location, which the Info pane shows.
    override var fileURL: URL? {
        didSet { notifyInfoChanged() }
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            completionHandler(error)
            self?.notifyInfoChanged()
        }
    }

    private func notifyInfoChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.windowControllers.compactMap { $0 as? ReaderWindowController }.forEach { $0.documentInfoChanged() }
        }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        // Load the bytes rather than PDFDocument(url:) so saving over the same file is safe:
        // the in-memory copy never depends on the file that NSDocument replaces when it saves.
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let document = PDFDocument(data: data) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
                NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” couldn’t be opened.",
                NSLocalizedRecoverySuggestionErrorKey: "The file may be damaged or may not be a PDF.",
            ])
        }
        if document.isLocked && !Self.unlock(document, name: url.lastPathComponent) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        }
        pdf = document
    }

    // MARK: - Saving

    /// Why this PDF can't be changed, or nil if it can.
    var editingBlockedReason: String? {
        guard let pdf = pdf else { return "The document isn’t loaded." }
        if pdf.isEncrypted {
            return "This PDF is password protected or encrypted. Saving changes would remove that protection, so PDFReader leaves it unchanged."
        }
        if !pdf.allowsDocumentChanges && !pdf.allowsCommenting {
            return "The document’s author doesn’t allow changes to this PDF."
        }
        return nil
    }

    override func write(to url: URL, ofType typeName: String) throws {
        guard let pdf = pdf else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
        }
        if let reason = editingBlockedReason {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
                NSLocalizedDescriptionKey: "“\(displayName ?? "This PDF")” can’t be saved.",
                NSLocalizedRecoverySuggestionErrorKey: reason,
            ])
        }
        windowControllers.compactMap { $0 as? ReaderWindowController }.forEach { $0.prepareForSave() }
        var attributes = pdf.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.modificationDateAttribute] = Date()
        pdf.documentAttributes = attributes
        guard pdf.write(to: url) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
                NSLocalizedDescriptionKey: "“\(displayName ?? "This PDF")” couldn’t be saved.",
            ])
        }
    }

    override func makeWindowControllers() {
        guard let pdf = pdf else { return }
        addWindowController(ReaderWindowController(pdf: pdf, fileURL: fileURL))
    }

    // MARK: - Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let pdf = pdf else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
        }
        guard pdf.allowsPrinting else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [
                NSLocalizedDescriptionKey: "This PDF doesn’t allow printing.",
                NSLocalizedRecoverySuggestionErrorKey: "The document’s author has restricted printing.",
            ])
        }
        let info = (printInfo.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        for (key, value) in printSettings {
            info.dictionary().setObject(value, forKey: key.rawValue as NSString)
        }
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo: [
                NSLocalizedDescriptionKey: "This PDF couldn’t be prepared for printing.",
            ])
        }
        operation.jobTitle = displayName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([
            .showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation,
            .showsScaling, .showsPreview, .showsPageSetupAccessory,
        ])
        return operation
    }

    // MARK: - Password-protected PDFs

    private static func unlock(_ document: PDFDocument, name: String) -> Bool {
        var message = "Enter the password to open this PDF."
        while document.isLocked {
            let alert = NSAlert()
            alert.messageText = "“\(name)” is password protected"
            alert.informativeText = message
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            alert.accessoryView = field
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            if !document.unlock(withPassword: field.stringValue) {
                message = "That password is incorrect. Try again."
            }
        }
        return true
    }
}
