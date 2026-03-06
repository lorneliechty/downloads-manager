import Foundation

/// Records organize operations and supports safe undo.
///
/// The ledger stores the last organize operation's file moves along with a snapshot
/// of the folder state immediately after the organize. Before undoing, it validates
/// that the current folder state matches the snapshot exactly — if anything has
/// changed (files added, removed, renamed, or modified), undo is blocked.
public struct UndoLedger: Codable {
    /// A snapshot of a file's key attributes for state comparison.
    struct FileSnapshot: Codable, Equatable {
        let path: String
        let size: UInt64
        let modified: Date
    }

    /// The moves from the last organize operation.
    public internal(set) var lastMoves: [FileMove]

    /// Snapshot of the target directory state immediately after the last organize.
    /// This captures every file (recursively) in every date/type folder that was
    /// created or modified by the organize. We also snapshot the root to detect
    /// new files that appeared.
    var postOrganizeSnapshot: [FileSnapshot]

    /// The root directory that was organized.
    public internal(set) var targetDirectory: String

    /// Timestamp of the last organize.
    public internal(set) var organizedAt: Date

    public init() {
        self.lastMoves = []
        self.postOrganizeSnapshot = []
        self.targetDirectory = ""
        self.organizedAt = .distantPast
    }

    /// Whether there's an operation available to undo.
    public var hasUndoableOperation: Bool {
        !lastMoves.isEmpty
    }

    /// Record a completed organize operation.
    public mutating func record(moves: [FileMove], targetDirectory: String, fileManager: FileManager = .default) {
        self.lastMoves = moves
        self.targetDirectory = targetDirectory
        self.organizedAt = Date()
        self.postOrganizeSnapshot = Self.snapshot(directory: targetDirectory, fileManager: fileManager)
    }

    /// Validate that the folder state hasn't changed since the organize.
    /// Returns nil if safe to undo, or a description of what changed if not.
    public func validateStateForUndo(fileManager: FileManager = .default) -> String? {
        guard hasUndoableOperation else {
            return "No organize operation to undo."
        }

        let currentSnapshot = Self.snapshot(directory: targetDirectory, fileManager: fileManager)

        // Compare snapshots
        let postSet = Set(postOrganizeSnapshot.map { $0.path })
        let currentSet = Set(currentSnapshot.map { $0.path })

        let added = currentSet.subtracting(postSet)
        let removed = postSet.subtracting(currentSet)

        if !added.isEmpty {
            let names = added.prefix(3).map { URL(fileURLWithPath: $0).lastPathComponent }
            return "New files detected since last organize: \(names.joined(separator: ", "))\(added.count > 3 ? " and \(added.count - 3) more" : ""). Undo blocked to prevent conflicts."
        }

        if !removed.isEmpty {
            let names = removed.prefix(3).map { URL(fileURLWithPath: $0).lastPathComponent }
            return "Files removed since last organize: \(names.joined(separator: ", "))\(removed.count > 3 ? " and \(removed.count - 3) more" : ""). Undo blocked to prevent conflicts."
        }

        // Check for modifications (size or date changes)
        let postByPath = Dictionary(uniqueKeysWithValues: postOrganizeSnapshot.map { ($0.path, $0) })
        for current in currentSnapshot {
            if let original = postByPath[current.path] {
                if current.size != original.size || abs(current.modified.timeIntervalSince(original.modified)) > 1.0 {
                    let name = URL(fileURLWithPath: current.path).lastPathComponent
                    return "File modified since last organize: \(name). Undo blocked to prevent conflicts."
                }
            }
        }

        // Also verify that all source locations are still available (not occupied by new files)
        for move in lastMoves {
            if fileManager.fileExists(atPath: move.source) {
                let name = URL(fileURLWithPath: move.source).lastPathComponent
                return "Original location already occupied: \(name). Undo blocked to prevent conflicts."
            }
        }

        return nil  // Safe to undo
    }

    /// Clear the ledger after a successful undo.
    public mutating func clear() {
        lastMoves = []
        postOrganizeSnapshot = []
        targetDirectory = ""
        organizedAt = .distantPast
    }

    // MARK: - Snapshot Helpers

    /// Build a snapshot of all files in the directory (including subdirectories).
    static func snapshot(directory: String, fileManager: FileManager = .default) -> [FileSnapshot] {
        let url = URL(fileURLWithPath: directory)
        var snapshots: [FileSnapshot] = []

        // Snapshot root-level files
        if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for fileURL in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        // Recurse into subdirectories
                        snapshots.append(contentsOf: snapshotRecursive(directory: fileURL.path, fileManager: fileManager))
                    } else {
                        if let snap = makeSnapshot(url: fileURL) {
                            snapshots.append(snap)
                        }
                    }
                }
            }
        }

        return snapshots
    }

    private static func snapshotRecursive(directory: String, fileManager: FileManager = .default) -> [FileSnapshot] {
        let url = URL(fileURLWithPath: directory)
        var snapshots: [FileSnapshot] = []

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return snapshots
        }

        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                if let snap = makeSnapshot(url: fileURL) {
                    snapshots.append(snap)
                }
            }
        }

        return snapshots
    }

    private static func makeSnapshot(url: URL) -> FileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modified = values.contentModificationDate else {
            return nil
        }
        return FileSnapshot(path: url.path, size: UInt64(size), modified: modified)
    }
}

// MARK: - Persistence

extension UndoLedger {
    /// Default storage location for the ledger.
    public static var defaultPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DownloadsManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("undo_ledger.json")
    }

    /// Save the ledger to disk.
    public func save(to url: URL? = nil) throws {
        let target = url ?? Self.defaultPath
        let data = try JSONEncoder().encode(self)
        try data.write(to: target, options: .atomic)
    }

    /// Load the ledger from disk. Returns a fresh ledger if the file doesn't exist.
    public static func load(from url: URL? = nil) -> UndoLedger {
        let target = url ?? defaultPath
        guard let data = try? Data(contentsOf: target),
              let ledger = try? JSONDecoder().decode(UndoLedger.self, from: data) else {
            return UndoLedger()
        }
        return ledger
    }
}
