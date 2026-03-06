# Design Decisions

Confirmed design decisions for Downloads Manager. Agents: read this before making changes.

## Organization Strategy: Age-Bucketed, History-First

Files and folders are organized into **age-based buckets** first, then into **date+time groups** within each bucket. Downloads naturally cluster around tasks (research sessions, project work, etc.), so date-based grouping preserves that context.

### Age Buckets

Four buckets based on how old the content is (by modification time):

- **1_ Recent** — 0–30 days old
- **2_ Older than 30 Days** — 31–90 days old
- **3_ Older than 90 Days** — 91–365 days old
- **4_ Older than 1 Year** — 366+ days old

### Date+Time Folders

Within each age bucket, items are grouped into folders named by the organize run timestamp: `YYYY-MM-DD HH.MM` (dots instead of colons to avoid filesystem issues). All items organized in the same run share a folder.

```
~/Downloads/
  1_ Recent/
    2026-03-06 14.32/
      report.pdf
      screenshot.png
      ProjectFolder/         ← folder group kept intact
    2026-03-05 09.15/
      backup.zip
  2_ Older than 30 Days/
    2026-02-01 11.20/
      notes.txt
  3_ Older than 90 Days/
    ...
  4_ Older than 1 Year/
    ...
```

The `N_` prefixes ensure age buckets sort correctly (newest first) when Finder sorts by name.

### Re-bucketing

On subsequent runs, existing date+time folders are checked against current age thresholds. If a folder has aged into a different bucket (e.g., a "Recent" folder is now 45 days old), it's automatically moved to the correct bucket. The date+time folder name is preserved — it always reflects when the content was originally organized.

## Scope: Recursive (Root Items)

Everything in the root of the target directory is organized — both files and folders. Folders are moved as a unit (the entire tree). Their age is determined by the most recent file modification time anywhere in the tree.

Existing age bucket folders and date+time folders created by the manager are detected and skipped (not re-organized as new items). Detection uses exact name matching for age buckets and a regex pattern (`YYYY-MM-DD HH.MM`) for date+time folders.

## Organize Means Everything

No recency threshold. When the user clicks "Organize Now," every item in root moves. No exceptions.

## Undo Safety

The undo system records every move in a ledger. Before executing an undo, it validates that the folder state matches exactly what the last organize operation left behind. If any file has been added, removed, renamed, or modified since the organize, undo is blocked and the user is told why. This prevents undo from causing conflicts when the user or another process has touched the folder.

## Conflict Resolution

Finder-style rename on collision: `report.pdf` → `report (1).pdf` → `report (2).pdf`. This matches what macOS users expect.

## No Auto-Organize

Not in scope. No FSEvents watcher, no scheduled runs. Manual "Organize Now" only. This may be revisited after extended manual use.

## Partial Downloads

Files with extensions indicating in-progress downloads are skipped: `.crdownload`, `.part`, `.download`, `.partial`, `.tmp`. This only applies to files, not folders.

## Build System: CLI Only

Everything builds via Swift Package Manager from the command line. No Xcode project. `swift build`, `swift run`. The .app bundle is assembled by a shell script. Tests run as a standalone executable (`dm-test`) since XCTest requires full Xcode.

Target: macOS 13+ (Ventura).
