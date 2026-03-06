# Downloads Manager

A lightweight macOS menu bar utility that keeps your Downloads folder clean with one click.

## What It Does

Downloads Manager sits in your menu bar and organizes files in your `~/Downloads` folder into date-and-type subfolders. The goal is simple: keep the root of Downloads clear so it stays useful as a landing zone rather than becoming a graveyard.

## How It Works

- **One-click organize:** Click the menu bar icon, hit "Organize Now," and every file in the root of `~/Downloads` gets sorted. No exceptions, no stragglers.
- **History-first organization:** Files are grouped first by date (when they were downloaded/modified), then by type within each date folder. Downloads naturally cluster around tasks — this structure preserves that context.
- **Non-destructive:** Files are moved, never deleted. Uncategorizable files go to an "Other" type folder within their date group.
- **Safe undo:** Undo the last organize operation — but only if the folder state hasn't been modified since. If you or another process moved something after the organize, undo is blocked to prevent conflicts.

### Folder Structure After Organizing

```
~/Downloads/
  2026-03-06/
    Documents/
      report.pdf
      notes.txt
    Images/
      screenshot.png
    Archives/
      project.zip
  2026-03-05/
    Installers/
      app.pkg
    Code/
      script.py
```

Only files in the root of `~/Downloads` are moved. Existing subfolders are left alone.

## Project Status

In Development — Initial project setup.

## Development Plan

### Phase 1: Core Engine
- History-first file organization engine (date → type folder structure)
- Extension-to-category mapping with sensible defaults
- File mover with conflict resolution (Finder-style rename on collision)
- Undo ledger — records every move, validates folder state before reverting
- Unit tests for categorization, move logic, and undo safety checks
- CLI entry point for testing (`swift run downloads-manager organize`)

### Phase 2: Menu Bar App
- macOS menu bar (NSStatusItem) integration — no dock icon
- "Organize Now" button
- "Undo Last Organize" button (disabled when state has changed)
- Last-organized timestamp and file count in menu
- Launch at login toggle (SMAppService)

### Phase 3: Preferences & Polish
- SwiftUI preferences window
- Custom category rules editor (add/edit/delete extension → category mappings)
- Configurable target folder (defaults to ~/Downloads)
- Folder statistics display

### Future Wishlist
- Deep clean mode (recurse into existing subfolders)
- Auto-organize on schedule or file detection
- Notification support

## Tech Stack

- **Language:** Swift
- **UI Framework:** SwiftUI + AppKit (NSStatusItem for menu bar)
- **File Operations:** Foundation (FileManager)
- **Build System:** Swift Package Manager (command-line builds only, no Xcode project)
- **Minimum Target:** macOS 13 (Ventura)

## Building

```bash
# Build
swift build -c release

# Run CLI
swift run downloads-manager organize ~/Downloads

# Run tests
swift test

# Package as .app bundle
./scripts/bundle.sh
```

The `bundle.sh` script wraps the built binary into a proper macOS .app bundle with Info.plist, sets LSUIElement (no dock icon), and does ad-hoc code signing.

## License

MIT
