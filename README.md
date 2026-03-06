# Downloads Manager

A lightweight macOS menu bar utility that keeps your Downloads folder clean with one click.

## What It Does

Downloads Manager sits in your menu bar and organizes files and folders in your `~/Downloads` into age-bucketed, timestamped groups. The goal is simple: keep the root of Downloads clear so it stays useful as a landing zone rather than becoming a graveyard.

## How It Works

- **One-click organize:** Click the menu bar icon, hit "Organize Now," and every item in the root of `~/Downloads` gets sorted into age-based buckets with date+time groups.
- **Recursive:** Both files and folders are organized. Folders are moved as a unit — their age is determined by the most recent file inside them.
- **Age buckets:** Content is grouped by age: Recent, >30 Days, >90 Days, >1 Year. On each run, existing groups are re-bucketed if they've aged out.
- **Non-destructive:** Items are moved, never deleted. Partial downloads (.crdownload, .part, etc.) are left alone.
- **Safe undo:** Undo the last organize operation — but only if the folder state hasn't been modified since. If you or another process moved something after the organize, undo is blocked to prevent conflicts.

### Folder Structure After Organizing

```
~/Downloads/
  Recent/
    2026-03-06 14.32/
      report.pdf
      screenshot.png
      ProjectFolder/
        src/
          main.swift
    2026-03-05 09.15/
      backup.zip
  Older than 30 Days/
    2026-02-01 11.20/
      notes.txt
  Older than 90 Days/
    2025-11-15 16.45/
      old_installer.dmg
  Older than 1 Year/
    2025-01-10 08.30/
      ancient_archive.zip
```

## Building

```bash
# Build everything
swift build

# Run CLI
swift run dm organize ~/Downloads
swift run dm undo
swift run dm status

# Run tests
swift run dm-test

# Package as .app bundle (release)
./scripts/bundle.sh

# Package as .app bundle (debug)
./scripts/bundle.sh debug
```

The `bundle.sh` script wraps the built binary into a proper macOS .app bundle with Info.plist, sets LSUIElement (no dock icon), and does ad-hoc code signing.

## Project Structure

```
Sources/
  DownloadsManager/     # Core library
    FileOrganizer.swift   # Organize + undo engine
    AgeBucket.swift       # Age bucket definitions
    OrganizeResult.swift  # Result types (FileMove, OrganizeResult)
    UndoLedger.swift      # Undo state + snapshot validation
    FileCategory.swift    # Extension-to-category mapping (future use)
  dm-cli/               # Command-line interface
  dm-app/               # Menu bar app (NSStatusItem)
  dm-test/              # Test executable (no XCTest dependency)
scripts/
  bundle.sh             # .app bundle packaging
```

## Tech Stack

- **Language:** Swift
- **UI Framework:** AppKit (NSStatusItem for menu bar)
- **File Operations:** Foundation (FileManager)
- **Build System:** Swift Package Manager (command-line builds only, no Xcode project)
- **Minimum Target:** macOS 13 (Ventura)

## License

MIT
