import Foundation

/// A single file move recorded during an organize operation.
public struct FileMove: Codable, Equatable, Sendable {
    /// Original absolute path of the file.
    public let source: String
    /// Destination absolute path after the move.
    public let destination: String

    public init(source: String, destination: String) {
        self.source = source
        self.destination = destination
    }
}

/// The result of an organize operation — what was moved, what was skipped, and the ledger for undo.
public struct OrganizeResult: Sendable {
    public let moves: [FileMove]
    public let skipped: [String]  // files that couldn't be moved (permissions, etc.)
    public let errors: [String]   // error descriptions

    public var filesMoved: Int { moves.count }
    public var filesSkipped: Int { skipped.count }

    public init(moves: [FileMove], skipped: [String], errors: [String]) {
        self.moves = moves
        self.skipped = skipped
        self.errors = errors
    }
}
