# Contributing to PDFReader

Thanks for helping. PDFReader is a small native macOS app, created and maintained by
Malik Kabir ([techmaleek@gmail.com](mailto:techmaleek@gmail.com)).

## Build and run
```bash
bash install.sh --build          # compiles into ./build/PDFReader.app
open build/PDFReader.app
```
You only need Apple's Command Line Tools (`xcode-select --install`). There's no Xcode project and no
third-party dependencies; please keep it that way.

## Where things are
| File | What it does |
| --- | --- |
| `Sources/AppDelegate.swift` | App lifecycle, menus, About panel, default-app prompt |
| `Sources/PDFReaderDocument.swift` | Opening, saving and printing a PDF (`NSDocument`) |
| `Sources/ReaderWindowController.swift` | Reader window, toolbar, search, navigation |
| `Sources/SigningPDFView.swift` | The PDF view: placing, moving, resizing and deleting signatures |
| `Sources/SignatureStore.swift` | The saved-signature library (max 5) and image clean-up for imports |
| `Sources/SignatureCaptureSheet.swift` | Drawing a signature with the mouse or trackpad |
| `Sources/SignaturesWindowController.swift` | The signature library window (Sign ▸ Manage Signatures…) |
| `Sources/InfoPaneViewController.swift` | The Info pane on the right (document, page and file details) |
| `Sources/PropertiesSheet.swift` | File ▸ Properties (file name and PDF metadata) |
| `Sources/Appearance.swift` | Light/dark appearance and dark pages |
| `Sources/SidebarViewController.swift` | Bookmarks and page thumbnails |
| `Sources/RecentFilesWindowController.swift` | Recent PDFs window |

## Before opening a pull request
- It builds with `bash install.sh --build` and no new warnings.
- You tried the change in the app, in both light and dark mode.
- If you touched saving or signing: open the saved file in Preview (and ideally a browser) to check it.
- Keep PRs focused on one change, and describe what you tested.

## Reporting bugs
Open an issue with your macOS version, PDFReader version (PDFReader ▸ About), what you did, and what
happened. If a specific PDF triggers it and you can share it, attach it. Or email the address above.
