# PDFReader: a lightweight PDF reader for macOS

A small, fast, native PDF viewer that replaces Adobe Acrobat Reader for everyday reading.
It is built on Apple's PDFKit (the same engine Preview uses) and needs **macOS 12 Monterey or newer**.

## Features
- **View PDFs:** continuous scroll, single page, or two-page layouts, plus zoom and full screen
- **Select and copy text:** click and drag, ⌘C to copy, ⌘A to select all
- **Bookmarks sidebar:** the PDF's table of contents; click an entry to jump to it.
  Switch to **Pages** for page thumbnails. Toggle the sidebar with ⌃⌘S or the toolbar button.
- **Recent PDFs:** File ▸ Open Recent, a *Recent PDFs* window with thumbnails (⇧⌘O,
  also shown when you open PDFReader on its own), and the Dock icon's right-click menu
- **Print:** ⌘P or the printer toolbar button, with the standard macOS print dialog
  (preview, page range, copies, paper size, scaling)
- Extras: search (⌘F, then Return or ⌘G for the next match), "Go to Page" (⌘L),
  back/forward (⌘[ / ⌘]), password-protected PDFs, and reopening each file at the page you left off

## Install (one time, about 1 minute)
1. If you haven't already, install Apple's free Command Line Tools:
   ```bash
   xcode-select --install
   ```
2. Open **Terminal** and run:
   ```bash
   git clone https://github.com/techmalik/PDFReader.git
   bash PDFReader/install.sh
   ```
   This builds `PDFReader.app`, copies it to
   `/Applications`, and launches it.

## Make it your default PDF app
When PDFReader first launches it asks whether to become your default PDF app. Click **Make Default**.

You can also do it later in either of these ways:
- In PDFReader, choose **PDFReader ▸ Make PDFReader the Default PDF App**.
- In Finder, select any PDF, choose **File ▸ Get Info** (⌘I), pick **PDFReader** under
  **Open with**, then click **Change All…**.

## Updating or uninstalling
- To update after changing the code, run `install.sh` again.
- To uninstall, drag `/Applications/PDFReader.app` to the Trash. To restore Acrobat or Preview as
  the default, use the Finder **Get Info ▸ Open with ▸ Change All…** steps above.

## Contributing
Issues and pull requests are welcome. The app is plain Swift with no dependencies:
the sources are in `Sources/`, and `bash install.sh --build` compiles it into `./build`.

## License
[MIT](LICENSE) © 2026 Malik Kabir
