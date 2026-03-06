import Foundation

/// The core engine that organizes a Downloads folder into age-bucketed, date+time groups.
///
/// Structure after organizing:
/// ```
/// ~/Downloads/
///   Recent/
///     2026-03-06 14.32/
///       report.pdf
///       screenshot.png
///       ProjectFolder/       ← folder group kept intact
///     2026-03-05 09.15/
///       backup.zip
///   Older than 30 Days/
///     2026-02-01 11.20/
///       notes.txt
///   Older than 90 Days/
///     ...
///   Older than 1 Year/
///     ...
/// ```
///
/// On subsequent runs, existing date+time folders are re-bucketed if they've aged out,
/// and new root items are organized into a fresh date+time folder.
public final class FileOrganizer {
    private let fileManager: FileManager

    /// Regex matching our date+time folder naming convention: "YYYY-MM-DD HH.MM"
    /// The dot separator in time avoids filesystem issues with colons.
    private static let dateTimeFolderRegex = try! NSRegularExpression(
        pattern: "^\\d{4}-\\d{2}-\\d{2} \\d{2}\\.\\d{2}$"
    )

    /// Formatter for creating date+time folder names.
    private static let folderNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Formatter for parsing date+time folder names back to dates.
    private static let folderNameParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Status

    /// Returns true if the root of the directory contains any items that are not
    /// DM-managed folders (age buckets or date+time folders). Used to determine
    /// whether the menu bar icon should indicate unorganized content.
    public func hasUnsortedItems(in directory: String) -> Bool {
        let dirURL = URL(fileURLWithPath: directory)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for item in contents {
            if isAgeBucketFolder(item) { continue }
            if isDateTimeFolder(item) { continue }
            return true
        }
        return false
    }

    // MARK: - Organize

    /// Organize the target directory.
    ///
    /// 1. Any new files/folders in root → new date+time folder under the appropriate age bucket.
    /// 2. Existing date+time folders inside age buckets → re-bucketed if they've aged out.
    /// 3. Folder groups (non-DM directories in root) are moved as a unit using their most recent timestamp.
    public func organize(directory: String) throws -> OrganizeResult {
        let dirURL = URL(fileURLWithPath: directory)
        let now = Date()
        var moves: [FileMove] = []
        var skipped: [String] = []
        var errors: [String] = []

        // Phase 1: Re-bucket existing date+time folders that have aged into a different bucket
        let rebucketMoves = try rebucketExistingFolders(in: dirURL, now: now)
        moves.append(contentsOf: rebucketMoves)

        // Phase 2: Organize new root-level items (files and non-DM folders)
        let rootContents = try fileManager.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        // Separate root items into: age bucket folders (ours) vs everything else (new stuff)
        var newItems: [URL] = []
        for item in rootContents {
            if isAgeBucketFolder(item) {
                continue  // skip our own bucket folders
            }
            if isDateTimeFolder(item) {
                // A date+time folder sitting in root (shouldn't normally happen, but handle it)
                // Treat it as something to re-bucket
                let date = parseDate(fromFolderName: item.lastPathComponent) ?? now
                let bucket = AgeBucket.bucket(for: date, relativeTo: now)
                let destDir = dirURL.appendingPathComponent(bucket.rawValue)
                try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
                let dest = destDir.appendingPathComponent(item.lastPathComponent)
                if !fileManager.fileExists(atPath: dest.path) {
                    try fileManager.moveItem(at: item, to: dest)
                    moves.append(FileMove(source: item.path, destination: dest.path))
                }
                continue
            }
            newItems.append(item)
        }

        if newItems.isEmpty {
            return OrganizeResult(moves: moves, skipped: skipped, errors: errors)
        }

        // Create a date+time folder name for this organize run
        let runFolderName = Self.folderNameFormatter.string(from: now)

        // Group new items by their age bucket
        var bucketedItems: [AgeBucket: [URL]] = [:]
        for item in newItems {
            // Skip partial downloads (files only)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDir)

            if !isDir.boolValue {
                let ext = item.pathExtension.lowercased()
                if isPartialDownload(extension: ext) {
                    skipped.append(item.path)
                    continue
                }
            }

            let itemDate = mostRecentDate(for: item)
            let bucket = AgeBucket.bucket(for: itemDate, relativeTo: now)
            bucketedItems[bucket, default: []].append(item)
        }

        // Move items into their bucket's date+time folder
        for (bucket, items) in bucketedItems {
            let destDir = dirURL
                .appendingPathComponent(bucket.rawValue)
                .appendingPathComponent(runFolderName)
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

            for item in items {
                let dest = resolveConflict(filename: item.lastPathComponent, in: destDir)
                do {
                    try fileManager.moveItem(at: item, to: dest)
                    moves.append(FileMove(source: item.path, destination: dest.path))
                } catch {
                    errors.append("\(item.lastPathComponent): \(error.localizedDescription)")
                    skipped.append(item.path)
                }
            }
        }

        return OrganizeResult(moves: moves, skipped: skipped, errors: errors)
    }

    // MARK: - Undo

    /// Undo the last organize operation by moving items back to their original locations.
    public func undo(ledger: inout UndoLedger) throws -> (restored: Int, errors: [String]) {
        if let reason = ledger.validateStateForUndo(fileManager: fileManager) {
            throw UndoError.stateChanged(reason)
        }

        var restored = 0
        var undoErrors: [String] = []

        // Reverse moves in LIFO order
        for move in ledger.lastMoves.reversed() {
            let sourceURL = URL(fileURLWithPath: move.destination)
            let destURL = URL(fileURLWithPath: move.source)

            // Ensure parent directory exists (it should, but be safe)
            let parentDir = destURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

            do {
                try fileManager.moveItem(at: sourceURL, to: destURL)
                restored += 1
            } catch {
                undoErrors.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Clean up empty directories
        if ledger.hasUndoableOperation {
            cleanupEmptyDirectories(in: URL(fileURLWithPath: ledger.targetDirectory))
        }

        ledger.clear()
        return (restored, undoErrors)
    }

    // MARK: - Re-bucketing

    /// Check existing age bucket folders for date+time subfolders that need to move to a different bucket.
    private func rebucketExistingFolders(in dirURL: URL, now: Date) throws -> [FileMove] {
        var moves: [FileMove] = []

        for bucket in AgeBucket.allInOrder {
            let bucketDir = dirURL.appendingPathComponent(bucket.rawValue)

            guard fileManager.fileExists(atPath: bucketDir.path) else { continue }

            let subfolders = try fileManager.contentsOfDirectory(
                at: bucketDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for folder in subfolders {
                guard isDateTimeFolder(folder) else { continue }

                // Parse the date from the folder name
                guard let folderDate = parseDate(fromFolderName: folder.lastPathComponent) else { continue }

                let correctBucket = AgeBucket.bucket(for: folderDate, relativeTo: now)
                if correctBucket != bucket {
                    // Needs to move to a different bucket
                    let destBucketDir = dirURL.appendingPathComponent(correctBucket.rawValue)
                    try fileManager.createDirectory(at: destBucketDir, withIntermediateDirectories: true)

                    let dest = destBucketDir.appendingPathComponent(folder.lastPathComponent)
                    if !fileManager.fileExists(atPath: dest.path) {
                        try fileManager.moveItem(at: folder, to: dest)
                        moves.append(FileMove(source: folder.path, destination: dest.path))
                    }
                }
            }
        }

        return moves
    }

    // MARK: - Date Helpers

    /// Get the most recent modification date for an item.
    /// For files, this is their modification date.
    /// For directories, this is the most recent modification date of any file in the tree.
    public func mostRecentDate(for url: URL) -> Date {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return Date()
        }

        if !isDir.boolValue {
            // It's a file
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? Date()
        }

        // It's a directory — find the most recent file in the tree
        var mostRecent = Date.distantPast

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return Date() }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if let isFile = values?.isRegularFile, isFile,
               let modified = values?.contentModificationDate,
               modified > mostRecent {
                mostRecent = modified
            }
        }

        return mostRecent == .distantPast ? Date() : mostRecent
    }

    // MARK: - Folder Name Detection

    /// Check if a URL is one of our age bucket folders.
    public func isAgeBucketFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return AgeBucket.allCases.contains { $0.rawValue == url.lastPathComponent }
    }

    /// Check if a URL is one of our date+time folders (matches "YYYY-MM-DD HH.MM").
    public func isDateTimeFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let name = url.lastPathComponent
        let range = NSRange(name.startIndex..., in: name)
        return Self.dateTimeFolderRegex.firstMatch(in: name, range: range) != nil
    }

    /// Parse a date from one of our date+time folder names.
    public func parseDate(fromFolderName name: String) -> Date? {
        Self.folderNameParser.date(from: name)
    }

    /// Generate a date+time folder name for a given date.
    public static func folderName(for date: Date) -> String {
        folderNameFormatter.string(from: date)
    }

    // MARK: - Conflict Resolution

    /// Finder-style conflict resolution: file.pdf → file (1).pdf → file (2).pdf
    public func resolveConflict(filename: String, in directory: URL) -> URL {
        let destURL = directory.appendingPathComponent(filename)

        if !fileManager.fileExists(atPath: destURL.path) {
            return destURL
        }

        let nameWithoutExt = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        var counter = 1
        while true {
            let newName: String
            if ext.isEmpty {
                newName = "\(nameWithoutExt) (\(counter))"
            } else {
                newName = "\(nameWithoutExt) (\(counter)).\(ext)"
            }

            let candidate = directory.appendingPathComponent(newName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    // MARK: - Private Helpers

    private func isPartialDownload(extension ext: String) -> Bool {
        let partialExtensions: Set<String> = [
            "crdownload", "part", "download", "partial", "tmp",
        ]
        return partialExtensions.contains(ext)
    }

    /// Remove empty directories recursively.
    public func cleanupEmptyDirectories(in directory: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            cleanupEmptyDirectories(in: item)

            if let subContents = try? fileManager.contentsOfDirectory(atPath: item.path),
               subContents.isEmpty {
                try? fileManager.removeItem(at: item)
            }
        }
    }
}

// MARK: - Errors

public enum UndoError: LocalizedError {
    case stateChanged(String)
    case noOperation

    public var errorDescription: String? {
        switch self {
        case .stateChanged(let reason): return reason
        case .noOperation: return "No organize operation to undo."
        }
    }
}
