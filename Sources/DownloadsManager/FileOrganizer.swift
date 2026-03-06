import Foundation

/// The core engine that organizes files from a target directory into date/type subfolders.
public final class FileOrganizer {
    public let categories: [FileCategory]
    public let uncategorizedName: String
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter

    public init(
        categories: [FileCategory] = FileCategory.defaults,
        uncategorizedName: String = "Other",
        fileManager: FileManager = .default
    ) {
        self.categories = categories
        self.uncategorizedName = uncategorizedName
        self.fileManager = fileManager

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    }

    // MARK: - Organize

    /// Organize all files in the root of `directory` into date/type subfolders.
    ///
    /// - Parameter directory: The directory to organize (e.g., ~/Downloads).
    /// - Returns: An `OrganizeResult` describing what was moved.
    public func organize(directory: String) throws -> OrganizeResult {
        let dirURL = URL(fileURLWithPath: directory)

        // Get only root-level contents (no recursion)
        let contents = try fileManager.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var moves: [FileMove] = []
        var skipped: [String] = []
        var errors: [String] = []

        for fileURL in contents {
            // Skip directories — we only move files from root
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                  !isDir.boolValue else {
                continue
            }

            // Skip partial downloads
            let ext = fileURL.pathExtension.lowercased()
            if isPartialDownload(extension: ext) {
                skipped.append(fileURL.path)
                continue
            }

            do {
                let move = try moveFile(fileURL: fileURL, baseDirectory: dirURL)
                moves.append(move)
            } catch {
                errors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
                skipped.append(fileURL.path)
            }
        }

        return OrganizeResult(moves: moves, skipped: skipped, errors: errors)
    }

    // MARK: - Undo

    /// Undo the last organize operation by moving files back to their original locations.
    ///
    /// - Parameters:
    ///   - ledger: The undo ledger containing the operation to reverse.
    /// - Returns: A tuple of (success count, error descriptions).
    /// - Throws: If the folder state has changed since the organize.
    public func undo(ledger: inout UndoLedger) throws -> (restored: Int, errors: [String]) {
        // Validate state safety
        if let reason = ledger.validateStateForUndo(fileManager: fileManager) {
            throw UndoError.stateChanged(reason)
        }

        var restored = 0
        var errors: [String] = []

        // Reverse moves in reverse order (LIFO)
        for move in ledger.lastMoves.reversed() {
            let sourceURL = URL(fileURLWithPath: move.destination)  // current location
            let destURL = URL(fileURLWithPath: move.source)         // original location

            do {
                try fileManager.moveItem(at: sourceURL, to: destURL)
                restored += 1
            } catch {
                errors.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Clean up empty directories left behind
        if ledger.hasUndoableOperation {
            cleanupEmptyDirectories(in: URL(fileURLWithPath: ledger.targetDirectory))
        }

        ledger.clear()

        return (restored, errors)
    }

    // MARK: - Private

    /// Determine the category for a file extension.
    func categorize(extension ext: String) -> String {
        for category in categories {
            if category.matches(extension: ext) {
                return category.name
            }
        }
        return uncategorizedName
    }

    /// Determine the date folder name from a file's modification date.
    func dateFolderName(for fileURL: URL) -> String {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let date = values?.contentModificationDate ?? Date()
        return dateFormatter.string(from: date)
    }

    /// Move a single file to its date/type destination, handling conflicts.
    private func moveFile(fileURL: URL, baseDirectory: URL) throws -> FileMove {
        let ext = fileURL.pathExtension
        let categoryName = categorize(extension: ext)
        let dateFolder = dateFolderName(for: fileURL)

        // Build destination: base/YYYY-MM-DD/Category/
        let destDir = baseDirectory
            .appendingPathComponent(dateFolder)
            .appendingPathComponent(categoryName)

        // Create directory if needed
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Resolve conflicts
        let destURL = resolveConflict(
            filename: fileURL.lastPathComponent,
            in: destDir
        )

        try fileManager.moveItem(at: fileURL, to: destURL)

        return FileMove(source: fileURL.path, destination: destURL.path)
    }

    /// Finder-style conflict resolution: file.pdf → file (1).pdf → file (2).pdf
    func resolveConflict(filename: String, in directory: URL) -> URL {
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

    /// Check if a file extension indicates a partial/in-progress download.
    private func isPartialDownload(extension ext: String) -> Bool {
        let partialExtensions: Set<String> = [
            "crdownload",  // Chrome
            "part",        // Firefox
            "download",    // Safari
            "partial",     // Various
            "tmp",         // Temporary
        ]
        return partialExtensions.contains(ext)
    }

    /// Remove empty directories created by organize (date folders, type folders).
    private func cleanupEmptyDirectories(in directory: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            // Recurse into subdirectories first
            cleanupEmptyDirectories(in: item)

            // Remove if empty
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
