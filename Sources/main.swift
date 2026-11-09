import AppKit

let app = NSApplication.shared
_ = ReaderDocumentController() // the first document controller created becomes NSDocumentController.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
