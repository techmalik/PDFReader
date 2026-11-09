import AppKit
import PDFKit

/// File ▸ Properties… : edit the file name and the PDF's metadata (title, author, subject,
/// keywords, creator). Saving renames the file if needed and writes the metadata into it.
final class PropertiesSheet: NSWindowController {
    private let pdfDocument: PDFReaderDocument
    private let pdf: PDFDocument

    private let nameField = NSTextField()
    private let titleField = NSTextField()
    private let authorField = NSTextField()
    private let subjectField = NSTextField()
    private let keywordsField = NSTextField()
    private let creatorField = NSTextField()

    private var onClose: (() -> Void)?

    init(document: PDFReaderDocument, pdf: PDFDocument) {
        self.pdfDocument = document
        self.pdf = pdf
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                            styleMask: [.titled], backing: .buffered, defer: true)
        panel.title = "Properties"
        super.init(window: panel)
        buildContent(in: panel)
        load()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func begin(for parent: NSWindow, onClose: @escaping () -> Void) {
        guard let sheet = window else { return }
        self.onClose = onClose
        parent.beginSheet(sheet)
    }

    // MARK: - Layout

    private func buildContent(in panel: NSPanel) {
        let attrs = pdf.documentAttributes ?? [:]
        let editable: [(String, NSTextField, String)] = [
            ("File name:", nameField, "File name"),
            ("Title:", titleField, "No title"),
            ("Author:", authorField, "No author"),
            ("Subject:", subjectField, "No subject"),
            ("Keywords:", keywordsField, "Separate keywords with commas"),
            ("Creator:", creatorField, "Application that created the content"),
        ]
        var rows: [[NSView]] = editable.map { label, field, placeholder in
            field.placeholderString = placeholder
            field.lineBreakMode = .byTruncatingTail
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.widthAnchor.constraint(equalToConstant: 340).isActive = true
            return [rightLabel(label), field]
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        func dateText(_ key: PDFDocumentAttribute) -> String {
            (attrs[key] as? Date).map(formatter.string(from:)) ?? "—"
        }
        var sizeText = "—"
        if let url = pdfDocument.fileURL,
           let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            sizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        let info: [(String, String)] = [
            ("Producer:", (attrs[PDFDocumentAttribute.producerAttribute] as? String) ?? "—"),
            ("Created:", dateText(.creationDateAttribute)),
            ("Modified:", dateText(.modificationDateAttribute)),
            ("Pages:", "\(pdf.pageCount)"),
            ("PDF version:", "\(pdf.majorVersion).\(pdf.minorVersion)"),
            ("File size:", sizeText),
            ("Location:", pdfDocument.fileURL?.deletingLastPathComponent().path ?? "—"),
        ]
        rows.append([NSView(), NSView()])
        rows += info.map { label, value in
            let field = NSTextField(labelWithString: value)
            field.textColor = .secondaryLabelColor
            field.isSelectable = true
            field.lineBreakMode = .byTruncatingMiddle
            field.toolTip = value
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true
            return [rightLabel(label), field]
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.row(at: editable.count).height = 6

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, save])
        buttons.spacing = 12

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        panel.contentView = content
        panel.initialFirstResponder = titleField

        if let reason = pdfDocument.editingBlockedReason {
            for (_, field, _) in editable { field.isEditable = false }
            save.isEnabled = false
            save.toolTip = reason
            let note = NSTextField(wrappingLabelWithString: reason)
            note.textColor = .systemOrange
            note.preferredMaxLayoutWidth = 470
            stack.insertArrangedSubview(note, at: 1)
        }
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(content.fittingSize)
    }

    private func rightLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    private func load() {
        let attrs = pdf.documentAttributes ?? [:]
        nameField.stringValue = pdfDocument.fileURL?.deletingPathExtension().lastPathComponent ?? pdfDocument.displayName
        titleField.stringValue = attrs[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        authorField.stringValue = attrs[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        subjectField.stringValue = attrs[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        creatorField.stringValue = attrs[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
        if let list = attrs[PDFDocumentAttribute.keywordsAttribute] as? [Any] {
            keywordsField.stringValue = list.map { "\($0)" }.joined(separator: ", ")
        } else if let text = attrs[PDFDocumentAttribute.keywordsAttribute] as? String {
            keywordsField.stringValue = text
        }
    }

    // MARK: - Actions

    @objc private func cancel(_ sender: Any?) { close(sender) }

    private func close(_ sender: Any?) {
        guard let sheet = window else { return }
        sheet.sheetParent?.endSheet(sheet)
        onClose?()
        onClose = nil
    }

    @objc private func save(_ sender: Any?) {
        window?.makeFirstResponder(nil) // commit the field being edited

        // Validate the new file name before changing anything.
        var newURL: URL?
        if let url = pdfDocument.fileURL {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentName = url.deletingPathExtension().lastPathComponent
            if name != currentName {
                if name.isEmpty || name.contains("/") || name.contains(":") || name.hasPrefix(".") {
                    showError("“\(name)” isn’t a valid file name.",
                              "Use a name that isn’t empty, doesn’t start with a dot, and has no “/” or “:”.")
                    return
                }
                let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "pdf" : url.pathExtension)
                let sameFileDifferentCase = candidate.path.lowercased() == url.path.lowercased()
                if FileManager.default.fileExists(atPath: candidate.path) && !sameFileDifferentCase {
                    showError("A file named “\(candidate.lastPathComponent)” already exists in this folder.",
                              "Choose a different name.")
                    return
                }
                newURL = candidate
            }
        }

        // Metadata
        var attrs = pdf.documentAttributes ?? [:]
        func set(_ key: PDFDocumentAttribute, _ field: NSTextField) {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            attrs[key] = value.isEmpty ? nil : value
        }
        set(.titleAttribute, titleField)
        set(.authorAttribute, authorField)
        set(.subjectAttribute, subjectField)
        set(.creatorAttribute, creatorField)
        let keywords = keywordsField.stringValue.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        attrs[PDFDocumentAttribute.keywordsAttribute] = keywords.isEmpty ? nil : keywords
        let metadataChanged = !NSDictionary(dictionary: attrs).isEqual(to: pdf.documentAttributes ?? [:])
        if metadataChanged {
            attrs.removeValue(forKey: "AAPL:Keywords") // PDFKit's private copy would override the new keywords
            pdf.documentAttributes = attrs
            pdfDocument.updateChangeCount(.changeDone)
        }

        // Close the sheet first, then save. Saving starts its own file access, so it must not begin
        // inside the rename's file access (AppKit aborts if it does).
        let document = pdfDocument
        let finish: () -> Void = { [weak self] in
            self?.close(nil)
            if metadataChanged || document.isDocumentEdited {
                document.save(nil)
            }
        }

        if let newURL = newURL {
            pdfDocument.move(to: newURL) { [weak self] error in
                // The completion handler runs while the rename still holds the document's file
                // access; continue on the next turn of the run loop, once it has been released.
                DispatchQueue.main.async {
                    if let error = error {
                        if let sheet = self?.window {
                            sheet.presentError(error, modalFor: sheet, delegate: nil, didPresent: nil, contextInfo: nil)
                        }
                        return
                    }
                    finish()
                }
            }
        } else {
            finish()
        }
    }

    private func showError(_ message: String, _ info: String) {
        guard let sheet = window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        alert.beginSheetModal(for: sheet)
    }
}
