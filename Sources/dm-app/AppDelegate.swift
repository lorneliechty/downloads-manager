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
            keyEquivalent: ""
        )
        organizeItem.target = self
        menu.addItem(organizeItem)

        // Undo Last Organize
        undoItem = NSMenuItem(
            title: "Undo Last Organize",
            action: #selector(undoLastOrganize),
            keyEquivalent: ""
        )
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
            keyEquivalent: ""
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

            let message = result.filesMoved == 0
                ? "No files to organize."
                : "\(result.filesMoved) file\(result.filesMoved == 1 ? "" : "s") organized."
                    + (result.filesSkipped > 0 ? " \(result.filesSkipped) skipped." : "")
            showStatusFlash(message)

        } catch {
            showError(title: "Organize Failed", body: error.localizedDescription)
        }
    }

    @objc private func undoLastOrganize() {
        var ledger = UndoLedger.load()

        guard ledger.hasUndoableOperation else {
            showStatusFlash("Nothing to undo.")
            return
        }

        do {
            let (restored, errors) = try organizer.undo(ledger: &ledger)
            try ledger.save()

            var message = "\(restored) file\(restored == 1 ? "" : "s") restored."
            if !errors.isEmpty {
                message += " \(errors.count) error\(errors.count == 1 ? "" : "s")."
            }
            showStatusFlash(message)

        } catch {
            showError(title: "Undo Blocked", body: error.localizedDescription)
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
                showError(
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

    /// Show a brief non-modal flash in the menu bar title, then revert to the icon.
    private func showStatusFlash(_ message: String) {
        if let button = statusItem.button {
            let originalImage = button.image
            button.image = nil
            button.title = message

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                button.title = ""
                button.image = originalImage
                self?.refreshMenuState()
            }
        }
    }

    /// Show a modal alert for errors only.
    private func showError(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
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
