import AppKit

// Menu bar app entry point (PRD §14). `.accessory` keeps it out of the Dock.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
