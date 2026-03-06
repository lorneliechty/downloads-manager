import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// LSUIElement behavior — no dock icon, no main menu bar.
// This is also set in Info.plist but we reinforce it here.
app.setActivationPolicy(.accessory)

app.run()
