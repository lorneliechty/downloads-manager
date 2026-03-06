import XCTest
@testable import DownloadsManager

final class UndoLedgerTests: XCTestCase {
    var tempDir: URL!
    var organizer: FileOrganizer!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UndoLedgerTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        organizer = FileOrganizer()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func createTestFile(name: String) {
        let path = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: path.path, contents: "test".data(using: .utf8))
    }

    func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(relativePath).path)
    }

    // MARK: - Basic Undo

    func testUndoRestoresFilesToOriginalLocations() throws {
        createTestFile(name: "report.pdf")
        createTestFile(name: "image.png")

        let result = try organizer.organize(directory: tempDir.path)
        XCTAssertEqual(result.filesMoved, 2)

        // Record in ledger
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)

        // Undo
        let (restored, errors) = try organizer.undo(ledger: &ledger)

        XCTAssertEqual(restored, 2)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(fileExists("report.pdf"), "report.pdf should be restored to root")
        XCTAssertTrue(fileExists("image.png"), "image.png should be restored to root")
    }

    func testUndoCleansUpEmptyDirectories() throws {
        createTestFile(name: "file.pdf")

        let result = try organizer.organize(directory: tempDir.path)
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)

        _ = try organizer.undo(ledger: &ledger)

        // The date and type directories should be cleaned up
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        // Should only have the restored file, no empty directories
        let dirs = contents.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        XCTAssertTrue(dirs.isEmpty, "Empty directories should be cleaned up after undo")
    }

    // MARK: - Undo Safety Validation

    func testUndoBlockedWhenNewFileAdded() throws {
        createTestFile(name: "original.pdf")

        let result = try organizer.organize(directory: tempDir.path)
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)

        // Simulate a new file appearing after organize
        createTestFile(name: "intruder.txt")

        let reason = ledger.validateStateForUndo()
        XCTAssertNotNil(reason, "Undo should be blocked when new files appear")
        XCTAssertTrue(reason!.contains("blocked"), "Reason should indicate undo is blocked")
    }

    func testUndoBlockedWhenFileRemoved() throws {
        createTestFile(name: "a.pdf")
        createTestFile(name: "b.png")

        let result = try organizer.organize(directory: tempDir.path)
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)

        // Remove one of the organized files
        let movedPath = result.moves.first!.destination
        try FileManager.default.removeItem(atPath: movedPath)

        let reason = ledger.validateStateForUndo()
        XCTAssertNotNil(reason, "Undo should be blocked when files are removed")
    }

    func testUndoBlockedWhenFileModified() throws {
        createTestFile(name: "doc.pdf")

        let result = try organizer.organize(directory: tempDir.path)
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)

        // Modify the organized file
        let movedPath = result.moves.first!.destination
        try "modified content that is different".data(using: .utf8)!.write(to: URL(fileURLWithPath: movedPath))

        let reason = ledger.validateStateForUndo()
        XCTAssertNotNil(reason, "Undo should be blocked when files are modified")
    }

    func testUndoBlockedWhenOriginalLocationOccupied() throws {
        createTestFile(name: "file.pdf")

        let result = try organizer.organize(directory: tempDir.path)
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)

        // Put a new file at the original location
        createTestFile(name: "file.pdf")

        let reason = ledger.validateStateForUndo()
        XCTAssertNotNil(reason, "Undo should be blocked when original location is occupied")
    }

    func testUndoAllowedWhenStateUnchanged() throws {
        createTestFile(name: "file.pdf")

        let result = try organizer.organize(directory: tempDir.path)
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)

        let reason = ledger.validateStateForUndo()
        XCTAssertNil(reason, "Undo should be allowed when state is unchanged")
    }

    // MARK: - Ledger State

    func testFreshLedgerHasNoUndoableOperation() {
        let ledger = UndoLedger()
        XCTAssertFalse(ledger.hasUndoableOperation)
    }

    func testLedgerClearsAfterUndo() throws {
        createTestFile(name: "file.pdf")

        let result = try organizer.organize(directory: tempDir.path)
        var ledger = UndoLedger()
        ledger.record(moves: result.moves, targetDirectory: tempDir.path)
        XCTAssertTrue(ledger.hasUndoableOperation)

        _ = try organizer.undo(ledger: &ledger)
        XCTAssertFalse(ledger.hasUndoableOperation)
    }

    // MARK: - Persistence

    func testLedgerRoundTrips() throws {
        let ledgerPath = tempDir.appendingPathComponent("test_ledger.json")

        var ledger = UndoLedger()
        ledger.record(
            moves: [FileMove(source: "/a/b.txt", destination: "/a/2026-03-06/Documents/b.txt")],
            targetDirectory: "/a"
        )

        try ledger.save(to: ledgerPath)
        let loaded = UndoLedger.load(from: ledgerPath)

        XCTAssertEqual(loaded.lastMoves.count, 1)
        XCTAssertEqual(loaded.lastMoves.first?.source, "/a/b.txt")
        XCTAssertEqual(loaded.targetDirectory, "/a")
        XCTAssertTrue(loaded.hasUndoableOperation)
    }

    func testLoadReturnsEmptyLedgerForMissingFile() {
        let missing = tempDir.appendingPathComponent("nonexistent.json")
        let ledger = UndoLedger.load(from: missing)
        XCTAssertFalse(ledger.hasUndoableOperation)
    }
}
