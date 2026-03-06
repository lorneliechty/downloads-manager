import Foundation
import DownloadsManager

// Simple CLI for testing the organize engine.
// Usage:
//   dm organize [directory]    — organize the directory (defaults to ~/Downloads)
//   dm undo                    — undo the last organize
//   dm status                  — show current state

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "help"

let defaultDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Downloads")
    .path

switch command {
case "organize":
    let directory = args.dropFirst().first ?? defaultDir
    let organizer = FileOrganizer()

    print("Organizing \(directory)...")

    do {
        let result = try organizer.organize(directory: directory)

        print("Done. \(result.filesMoved) item\(result.filesMoved == 1 ? "" : "s") moved, \(result.filesSkipped) skipped.")

        if !result.moves.isEmpty {
            // Save undo ledger
            var ledger = UndoLedger()
            ledger.record(moves: result.moves, targetDirectory: directory)
            try ledger.save()
            print("Undo ledger saved. Run `dm undo` to revert.")
        }

        if !result.errors.isEmpty {
            print("\nErrors:")
            for error in result.errors {
                print("  - \(error)")
            }
        }

        // Print summary of where things went
        if !result.moves.isEmpty {
            print("\nMoves:")
            for move in result.moves {
                let srcName = URL(fileURLWithPath: move.source).lastPathComponent
                let destRelative = move.destination.replacingOccurrences(of: directory + "/", with: "")
                print("  \(srcName) → \(destRelative)")
            }
        }

    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }

case "undo":
    var ledger = UndoLedger.load()

    guard ledger.hasUndoableOperation else {
        print("Nothing to undo.")
        exit(0)
    }

    print("Validating folder state...")

    let organizer = FileOrganizer()
    do {
        let (restored, errors) = try organizer.undo(ledger: &ledger)
        try ledger.save()

        print("Undo complete. \(restored) files restored to original locations.")

        if !errors.isEmpty {
            print("\nErrors during undo:")
            for error in errors {
                print("  - \(error)")
            }
        }
    } catch {
        print("Undo blocked: \(error.localizedDescription)")
        exit(1)
    }

case "status":
    let ledger = UndoLedger.load()

    if ledger.hasUndoableOperation {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: ledger.organizedAt)

        print("Last organize: \(dateStr)")
        print("Files moved: \(ledger.lastMoves.count)")
        print("Directory: \(ledger.targetDirectory)")

        // Check if undo is safe
        if let reason = ledger.validateStateForUndo() {
            print("Undo status: BLOCKED — \(reason)")
        } else {
            print("Undo status: Available")
        }
    } else {
        print("No organize operation recorded.")
    }

case "help", "--help", "-h":
    print("""
    Downloads Manager CLI

    Usage:
      dm organize [directory]  Organize files in directory (default: ~/Downloads)
      dm undo                  Undo the last organize operation
      dm status                Show status of last organize operation
      dm help                  Show this help message
    """)

default:
    print("Unknown command: \(command). Run `dm help` for usage.")
    exit(1)
}
