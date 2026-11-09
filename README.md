# PDFReader: a lightweight PDF reader for macOS

A small, fast, native PDF reader that replaces Adobe Acrobat Reader for everyday reading and signing.
It is built on Apple's PDFKit (the same engine Preview uses), has no dependencies, and needs
**macOS 12 Monterey or newer**.

Created by **Malik Kabir**. Free and open source under the [MIT License](LICENSE).

## Features
- **View PDFs:** continuous scroll, single page, or two-page layouts, plus zoom and full screen
- **Select and copy text:** click and drag, ⌘C to copy, ⌘A to select all
- **Bookmarks sidebar:** the PDF's table of contents; click an entry to jump to it.
  Switch to **Pages** for page thumbnails. Toggle the sidebar with ⌃⌘S or the toolbar button.
- **Recent PDFs:** File ▸ Open Recent, a *Recent PDFs* window with thumbnails (⇧⌘O,
  also shown when you open PDFReader on its own), and the Dock icon's right-click menu
- **Print:** ⌘P or the printer toolbar button, with the standard macOS print dialog
  (preview, page range, copies, paper size, scaling)
- **Sign PDFs:** save up to 5 signatures, each drawn with your mouse or trackpad or imported
  from a photo or scan, then place one on any page from the **Sign** toolbar button. Drag to move,
  drag the corner handle to resize, Delete to remove, ⌘Z to undo. Save with ⌘S; the signature is
  written into the file, so it shows in Preview, Acrobat and browsers too.
- **Info pane:** click the ⓘ toolbar button (or View ▸ Show Info, ⌥⌘I) for a panel on the right with
  the document's title, author, subject, keywords, creator, producer and dates; the current page's size
  (mm, inches and points), paper name and orientation; file name, size and location; page count,
  PDF version, and whether printing, copying and changes are allowed.
- **Edit properties:** File ▸ Properties… (⌘I) to rename the file and edit the PDF's title, author,
  subject, keywords and creator. Also shows producer, dates, page count, PDF version and size.
- **Dark mode:** follows macOS, or pick Light or Dark under View ▸ Appearance. **Dark pages**
  (moon toolbar button, ⇧⌘D) shows pages light-on-dark for night reading, either always or only
  in dark mode (View ▸ Page Colors). Printing and saved files are unaffected.
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

## Signing tips
- **Drawing with the trackpad:** in the *New Signature* sheet, click **Use Trackpad** and write on the
  trackpad with one finger, the way you would on paper (the trackpad maps onto the box). Press any key
  when you're done. Or just click-and-drag with the mouse or trackpad.
- **Importing:** dark ink on plain white paper works best. PDFReader removes the background and crops
  to the ink.
- Your saved signatures stay on your Mac in `~/Library/Application Support/PDFReader/Signatures`.
  Nothing is uploaded anywhere.
- Password-protected PDFs are opened read-only, because saving would remove their protection.

## Feedback
Found a bug or have an idea? Use **Help ▸ Send Feedback…** in the app, email
[techmaleek@gmail.com](mailto:techmaleek@gmail.com), or
[open an issue](https://github.com/techmalik/PDFReader/issues).

## Contributing
Issues and pull requests are welcome. The app is plain Swift with no dependencies:
the sources are in `Sources/`, and `bash install.sh --build` compiles it into `./build`.
See [CONTRIBUTING.md](CONTRIBUTING.md) for how the code is laid out and what to check before a PR.

## License
[MIT](LICENSE) © 2026 Malik Kabir. Created and maintained by Malik Kabir
([techmaleek@gmail.com](mailto:techmaleek@gmail.com)).
