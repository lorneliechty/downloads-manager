# Design Decisions

Confirmed design decisions for Downloads Manager. Agents: read this before making changes.

## Organization Strategy: History-First

Files sort into **date folders first**, then **type subfolders within**. Downloads naturally cluster around tasks (research sessions, project work, etc.), so date-based grouping preserves that context better than pure type buckets.

```
~/Downloads/
  2026-03-06/
    Documents/
      report.pdf
    Images/
      screenshot.png
  2026-03-05/
    Installers/
      app.pkg
```

Date is derived from the file's modification time (not creation time — many downloads preserve origin mtime, but modification time is more reliably set by the browser on download completion).

## Scope: Root Files Only

Only files sitting in the root of the target directory are moved. Existing subfolders are left untouched. No "deep clean" mode — that's on the future wishlist.

## Organize Means Everything

No recency threshold. When the user clicks "Organize Now," every file in root moves. No exceptions, no "leave recent files" option.

## Undo Safety

The undo system records every file move in a ledger. Before executing an undo, it validates that the folder state matches exactly what the last organize operation left behind. If any file has been added, removed, renamed, or modified since the organize, undo is blocked and the user is told why. This prevents undo from causing conflicts when the user or another process has touched the folder.

## Conflict Resolution

Finder-style rename on collision: `report.pdf` → `report (1).pdf` → `report (2).pdf`. This matches what macOS users expect.

## No Auto-Organize

Not in scope. No FSEvents watcher, no scheduled runs. Manual "Organize Now" only. This may be revisited after extended manual use.

## Build System: CLI Only

Everything builds via Swift Package Manager from the command line. No Xcode project. `swift build`, `swift test`, `swift run`. The .app bundle is assembled by a shell script.

Target: macOS 13+ (Ventura).
