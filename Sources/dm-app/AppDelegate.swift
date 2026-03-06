import AppKit
import DownloadsManager
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var organizer: FileOrganizer!
    private var targetDirectory: String!

    // Menu items we need to update dynamically
    private var undoItem: NSMenuItem!
    private var statusLabel: NSMenuItem!
    private var fileCountLabel: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        organizer = FileOrganizer()
        targetDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").path

        setupStatusItem()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use SF Symbol for the icon — a folder with arrow
            if let image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Downloads Manager") {
                image.isTemplate = true  // adapts to light/dark menu bar
                button.image = image
            } else {
                button.title = "DM"
            }
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Status info (non-interactive)
        fileCountLabel = NSMenuItem(title: "Checking...", action: nil, keyEquivalent: "")
        fileCountLabel.isEnabled = false
        menu.addItem(fileCountLabel)

        statusLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)

        menu.addItem(NSMenuItem.separator())

        // Organize Now
        let organizeItem = NSMenuItem(
            title: "Organize Now",
            action: #selector(organizeNow),
            keyEquivalent: "o"
        )
        organizeItem.keyEquivalentModifierMask = [.command]
        organizeItem.target = self
        menu.addItem(organizeItem)

        // Undo Last Organize
        undoItem = NSMenuItem(
            title: "Undo Last Organize",
            action: #selector(undoLastOrganize),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]
        undoItem.target = self
        menu.addItem(undoItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Downloads Manager",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        // Set delegate so we can update state when menu opens
        menu.delegate = self

        return menu
    }

    // MARK: - Actions

    @objc private func organizeNow() {
        do {
            let result = try organizer.organize(directory: targetDirectory)

            if result.filesMoved > 0 {
                // Save undo ledger
                var ledger = UndoLedger()
                ledger.record(moves: result.moves, targetDirectory: targetDirectory)
                try ledger.save()
            }

            showNotification(
                title: "Downloads Organized",
                body: result.filesMoved == 0
                    ? "No files to organize."
                    : "\(result.filesMoved) file\(result.filesMoved == 1 ? "" : "s") organized."
                        + (result.filesSkipped > 0 ? " \(result.filesSkipped) skipped." : "")
            )

        } catch {
            showNotification(title: "Organize Failed", body: error.localizedDescription)
        }
    }

    @objc private func undoLastOrganize() {
        var ledger = UndoLedger.load()

        guard ledger.hasUndoableOperation else {
            showNotification(title: "Nothing to Undo", body: "No organize operation to revert.")
            return
        }

        do {
            let (restored, errors) = try organizer.undo(ledger: &ledger)
            try ledger.save()

            var body = "\(restored) file\(restored == 1 ? "" : "s") restored."
            if !errors.isEmpty {
                body += " \(errors.count) error\(errors.count == 1 ? "" : "s")."
            }
            showNotification(title: "Undo Complete", body: body)

        } catch {
            showNotification(title: "Undo Blocked", body: error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if sender.state == .on {
                    try service.unregister()
                    sender.state = .off
                } else {
                    try service.register()
                    sender.state = .on
                }
            } catch {
                showNotification(
                    title: "Launch at Login",
                    body: "Could not update setting: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Helpers

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Count files (not directories) in the root of the target directory.
    private func rootFileCount() -> Int {
        let url = URL(fileURLWithPath: targetDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return contents.filter { fileURL in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            return !isDir.boolValue
        }.count
    }

    /// Update menu labels with current state.
    fileprivate func refreshMenuState() {
        let count = rootFileCount()
        fileCountLabel.title = count == 0
            ? "Downloads folder is clean"
            : "\(count) file\(count == 1 ? "" : "s") in Downloads root"

        let ledger = UndoLedger.load()
        if ledger.hasUndoableOperation {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: ledger.organizedAt, relativeTo: Date())
            statusLabel.title = "Last organized: \(relative)"
            statusLabel.isHidden = false

            // Enable/disable undo based on state validation
            let reason = ledger.validateStateForUndo()
            undoItem.isEnabled = (reason == nil)
            if let reason = reason {
                undoItem.toolTip = reason
            } else {
                undoItem.toolTip = nil
            }
        } else {
            statusLabel.isHidden = true
            undoItem.isEnabled = false
            undoItem.toolTip = "No organize operation to undo"
        }
    }

    private func showNotification(title: String, body: String) {
        // Use NSUserNotification replacement: just show an alert for now.
        // A proper UNUserNotification setup requires an app bundle with
        // entitlements, so we use a simple alert dialog.
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }
}
