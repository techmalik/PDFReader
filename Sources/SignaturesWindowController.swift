import AppKit
import UniformTypeIdentifiers

/// Sign ▸ Manage Signatures… : the signature library. Up to five signatures, each drawn here or
/// imported from an image, kept for use in any PDF.
final class SignaturesWindowController: NSWindowController {
    static let shared = SignaturesWindowController()

    private let slotsStack = NSStackView()
    private let drawButton = NSButton(title: "Draw New…", target: nil, action: nil)
    private let importButton = NSButton(title: "Import Image…", target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private var captureSheet: SignatureCaptureSheet?

    /// Called with a signature when the user clicks "Place" next to it.
    var onPlace: ((SavedSignature) -> Void)?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Signatures"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build(in: window)
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged(_:)),
                                               name: SignatureStore.didChange, object: nil)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build(in window: NSWindow) {
        let intro = NSTextField(wrappingLabelWithString:
            "Save up to \(SignatureStore.maxCount) signatures. Draw one with your mouse or trackpad, or import a photo or scan of your signature on white paper.")
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = 580

        slotsStack.orientation = .vertical
        slotsStack.alignment = .leading
        slotsStack.spacing = 8

        drawButton.target = self
        drawButton.action = #selector(drawNew(_:))
        drawButton.image = NSImage(systemSymbolName: "signature", accessibilityDescription: nil)
        drawButton.imagePosition = .imageLeading
        importButton.target = self
        importButton.action = #selector(importImage(_:))
        importButton.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        importButton.imagePosition = .imageLeading
        countLabel.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [drawButton, importButton, NSView(), countLabel])
        buttons.spacing = 8

        let stack = NSStackView(views: [intro, slotsStack, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Wide enough for the drawing sheet, which attaches to this window.
        stack.widthAnchor.constraint(equalToConstant: 580).isActive = true
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
    }

    @objc private func storeChanged(_ notification: Notification) { reload() }

    private func reload() {
        slotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let store = SignatureStore.shared
        for (index, signature) in store.signatures.enumerated() {
            slotsStack.addArrangedSubview(row(for: signature, number: index + 1))
        }
        if store.signatures.isEmpty {
            let empty = NSTextField(labelWithString: "No saved signatures yet.")
            empty.textColor = .tertiaryLabelColor
            slotsStack.addArrangedSubview(empty)
        }
        drawButton.isEnabled = !store.isFull
        importButton.isEnabled = !store.isFull
        countLabel.stringValue = store.isFull ? "Library full (\(SignatureStore.maxCount) of \(SignatureStore.maxCount))"
                                              : "\(store.signatures.count) of \(SignatureStore.maxCount) saved"
        resizeToFit(minHeight: 0)
    }

    /// Fits the window to its content, keeping the top edge in place.
    private func resizeToFit(minHeight: CGFloat) {
        guard let window = window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        var size = content.fittingSize
        size.height = max(size.height, minHeight)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let top = window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: top - frame.height, width: frame.width, height: frame.height),
                        display: true)
    }

    private func row(for signature: SavedSignature, number: Int) -> NSView {
        let preview = NSImageView(image: signature.image)
        preview.imageScaling = .scaleProportionallyDown
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.white.cgColor
        preview.layer?.cornerRadius = 6
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor.separatorColor.cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 380).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let place = NSButton(title: "Place", target: self, action: #selector(placeSignature(_:)))
        place.identifier = NSUserInterfaceItemIdentifier(signature.id)
        place.toolTip = "Add this signature to the PDF you’re viewing"
        place.isEnabled = onPlace != nil

        let delete = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!,
                              target: self, action: #selector(deleteSignature(_:)))
        delete.identifier = NSUserInterfaceItemIdentifier(signature.id)
        delete.toolTip = "Delete this signature"
        delete.bezelStyle = .texturedRounded

        let number = NSTextField(labelWithString: "\(number).")
        number.textColor = .secondaryLabelColor
        let row = NSStackView(views: [number, preview, place, delete])
        row.spacing = 10
        return row
    }

    private func signature(for sender: NSButton) -> SavedSignature? {
        SignatureStore.shared.signatures.first { $0.id == sender.identifier?.rawValue }
    }

    @objc private func placeSignature(_ sender: NSButton) {
        guard let signature = signature(for: sender) else { return }
        onPlace?(signature)
    }

    @objc private func deleteSignature(_ sender: NSButton) {
        guard let signature = signature(for: sender), let window = window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this signature?"
        alert.informativeText = "It will be removed from your saved signatures. PDFs you’ve already signed keep it."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { SignatureStore.shared.remove(signature) }
        }
    }

    // MARK: - Adding

    /// Shows the library; optionally starts drawing a new signature straight away.
    func show(startDrawing: Bool = false) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        reload()
        if startDrawing { drawNew(nil) }
    }

    @objc func drawNew(_ sender: Any?) {
        guard let window = window, captureSheet == nil, !SignatureStore.shared.isFull else { return }
        let sheet = SignatureCaptureSheet()
        captureSheet = sheet
        // A sheet can't be taller than its window.
        resizeToFit(minHeight: (sheet.window?.frame.height ?? 0) + 40)
        sheet.begin(for: window) { [weak self] data in
            self?.captureSheet = nil
            self?.resizeToFit(minHeight: 0)
            guard let data = data else { return }
            self?.save(data)
        }
    }

    @objc func importImage(_ sender: Any?) {
        guard let window = window, !SignatureStore.shared.isFull else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo or scan of your signature. Dark ink on white paper works best."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard let image = NSImage(contentsOf: url), let png = SignatureImage.cleanedPNG(from: image) else {
                self?.showError("No signature found in “\(url.lastPathComponent)”.",
                                "Use an image with dark ink on a light, plain background.")
                return
            }
            self?.save(png)
        }
    }

    private func save(_ png: Data) {
        do {
            try SignatureStore.shared.add(pngData: png)
        } catch {
            window.map { $0.presentError(error, modalFor: $0, delegate: nil, didPresent: nil, contextInfo: nil) }
        }
    }

    private func showError(_ message: String, _ info: String) {
        guard let window = window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        alert.beginSheetModal(for: window)
    }

    func refreshPlaceButtons() { reload() }
}
