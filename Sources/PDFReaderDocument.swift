import AppKit
import PDFKit

/// A read-only PDF document. The class name is referenced from Info.plist (NSDocumentClass).
@objc(PDFReaderDocument)
final class PDFReaderDocument: NSDocument {
    private(set) var pdf: PDFDocument?

    override class var autosavesInPlace: Bool { false }

    override func read(from url: URL, ofType typeName: String) throws {
        guard let document = PDFDocument(url: url) else {
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

    override func data(ofType typeName: String) throws -> Data {
        throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError)
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
