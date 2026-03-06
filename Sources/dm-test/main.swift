import Foundation
import DownloadsManager

let t = TestHarness()
let fm = FileManager.default

// MARK: - Helpers

func makeTempDir() -> URL {
    let dir = fm.temporaryDirectory.appendingPathComponent("dm-test-\(UUID().uuidString)")
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func createFile(in dir: URL, name: String, content: String = "test", date: Date? = nil) {
    let path = dir.appendingPathComponent(name)
    // Create parent directories if needed
    let parent = path.deletingLastPathComponent()
    try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
    fm.createFile(atPath: path.path, contents: content.data(using: .utf8))
    if let date = date {
        try? fm.setAttributes([.modificationDate: date], ofItemAtPath: path.path)
    }
}

func createDir(in dir: URL, name: String) {
    try! fm.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
}

func exists(in dir: URL, _ relativePath: String) -> Bool {
    fm.fileExists(atPath: dir.appendingPathComponent(relativePath).path)
}

func cleanup(_ dir: URL) {
    try? fm.removeItem(at: dir)
}

/// Returns the date+time folder name for a given date (matches FileOrganizer's format).
func dateTimeFolderName(for date: Date = Date()) -> String {
    FileOrganizer.folderName(for: date)
}

/// Returns a date offset from now by a given number of days.
func daysAgo(_ days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -days, to: Date())!
}

// ============================================================
// MARK: - AgeBucket Tests
// ============================================================

t.run("AgeBucket: recent for today") {
    let bucket = AgeBucket.bucket(for: Date(), relativeTo: Date())
    try t.assertEqual(bucket, .recent)
}

t.run("AgeBucket: recent for 29 days ago") {
    let bucket = AgeBucket.bucket(for: daysAgo(29), relativeTo: Date())
    try t.assertEqual(bucket, .recent)
}

t.run("AgeBucket: >30d for 31 days ago") {
    let bucket = AgeBucket.bucket(for: daysAgo(31), relativeTo: Date())
    try t.assertEqual(bucket, .olderThan30Days)
}

t.run("AgeBucket: >90d for 91 days ago") {
    let bucket = AgeBucket.bucket(for: daysAgo(91), relativeTo: Date())
    try t.assertEqual(bucket, .olderThan90Days)
}

t.run("AgeBucket: >1yr for 400 days ago") {
    let bucket = AgeBucket.bucket(for: daysAgo(400), relativeTo: Date())
    try t.assertEqual(bucket, .olderThan1Year)
}

t.run("AgeBucket: boundary at exactly 30 days") {
    let bucket = AgeBucket.bucket(for: daysAgo(30), relativeTo: Date())
    try t.assertEqual(bucket, .recent, "30 days is NOT > 30, so should be recent")
}

t.run("AgeBucket: allInOrder has 4 buckets") {
    try t.assertEqual(AgeBucket.allInOrder.count, 4)
    try t.assertEqual(AgeBucket.allInOrder.first, .recent)
    try t.assertEqual(AgeBucket.allInOrder.last, .olderThan1Year)
}

// ============================================================
// MARK: - FileOrganizer: Folder Detection
// ============================================================

t.run("Detection: recognizes age bucket folders") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let o = FileOrganizer()
    for bucket in AgeBucket.allCases {
        let bucketDir = dir.appendingPathComponent(bucket.rawValue)
        try fm.createDirectory(at: bucketDir, withIntermediateDirectories: true)
        try t.assertTrue(o.isAgeBucketFolder(bucketDir), "\(bucket.rawValue) should be recognized")
    }
}

t.run("Detection: non-bucket folder not recognized") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let o = FileOrganizer()
    let userFolder = dir.appendingPathComponent("My Project")
    try fm.createDirectory(at: userFolder, withIntermediateDirectories: true)
    try t.assertFalse(o.isAgeBucketFolder(userFolder))
}

t.run("Detection: recognizes date+time folder") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let o = FileOrganizer()
    let dtFolder = dir.appendingPathComponent("2026-03-06 14.32")
    try fm.createDirectory(at: dtFolder, withIntermediateDirectories: true)
    try t.assertTrue(o.isDateTimeFolder(dtFolder))
}

t.run("Detection: rejects non-matching folder names") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let o = FileOrganizer()
    for name in ["2026-03-06", "My Folder", "14.32", "2026-03-06_14.32"] {
        let folder = dir.appendingPathComponent(name)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try t.assertFalse(o.isDateTimeFolder(folder), "\(name) should NOT match date+time pattern")
    }
}

t.run("Detection: parseDate round-trips") {
    let o = FileOrganizer()
    let name = FileOrganizer.folderName(for: Date())
    let parsed = o.parseDate(fromFolderName: name)
    try t.assertNotNil(parsed, "Should parse a folder name we generated")
}

// ============================================================
// MARK: - FileOrganizer: Organize
// ============================================================

t.run("Organize: moves files into age bucket + date+time folder") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "report.pdf")
    createFile(in: dir, name: "photo.png")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    let dtName = dateTimeFolderName()

    try t.assertEqual(result.filesMoved, 2)
    try t.assertFalse(exists(in: dir, "report.pdf"), "report.pdf should be moved from root")
    try t.assertFalse(exists(in: dir, "photo.png"), "photo.png should be moved from root")
    try t.assertTrue(exists(in: dir, "1_ Recent/\(dtName)/report.pdf"))
    try t.assertTrue(exists(in: dir, "1_ Recent/\(dtName)/photo.png"))
}

t.run("Organize: moves folders as units") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    // Create a folder group with files inside
    createDir(in: dir, name: "ProjectX")
    createFile(in: dir, name: "ProjectX/readme.md")
    createFile(in: dir, name: "ProjectX/code.swift")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    let dtName = dateTimeFolderName()

    try t.assertEqual(result.filesMoved, 1, "Folder should be moved as one unit")
    try t.assertFalse(exists(in: dir, "ProjectX"), "ProjectX should be moved from root")
    try t.assertTrue(exists(in: dir, "1_ Recent/\(dtName)/ProjectX/readme.md"))
    try t.assertTrue(exists(in: dir, "1_ Recent/\(dtName)/ProjectX/code.swift"))
}

t.run("Organize: skips partial downloads") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "bigfile.crdownload")
    createFile(in: dir, name: "another.part")
    createFile(in: dir, name: "real.pdf")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)

    try t.assertEqual(result.filesMoved, 1)
    try t.assertEqual(result.filesSkipped, 2)
    try t.assertTrue(exists(in: dir, "bigfile.crdownload"))
    try t.assertTrue(exists(in: dir, "another.part"))
}

t.run("Organize: empty directory succeeds") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)

    try t.assertEqual(result.filesMoved, 0)
    try t.assertEqual(result.filesSkipped, 0)
    try t.assertTrue(result.errors.isEmpty)
}

t.run("Organize: old files go to correct age bucket") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let oldDate = daysAgo(45)  // > 30 days
    createFile(in: dir, name: "old_report.pdf", date: oldDate)

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    let dtName = dateTimeFolderName()

    try t.assertEqual(result.filesMoved, 1)
    // The file's mod date is 45 days ago, but the organize-run folder name uses "now"
    // The file should land in "Older than 30 Days" bucket
    try t.assertTrue(exists(in: dir, "2_ Older than 30 Days/\(dtName)/old_report.pdf"))
}

t.run("Organize: very old files go to >1yr bucket") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let ancientDate = daysAgo(400)
    createFile(in: dir, name: "ancient.txt", date: ancientDate)

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    let dtName = dateTimeFolderName()

    try t.assertEqual(result.filesMoved, 1)
    try t.assertTrue(exists(in: dir, "4_ Older than 1 Year/\(dtName)/ancient.txt"))
}

t.run("Organize: mixed-age files go to different buckets") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "recent.pdf")  // today → Recent
    createFile(in: dir, name: "old.pdf", date: daysAgo(50))  // → >30 Days

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    let dtName = dateTimeFolderName()

    try t.assertEqual(result.filesMoved, 2)
    try t.assertTrue(exists(in: dir, "1_ Recent/\(dtName)/recent.pdf"))
    try t.assertTrue(exists(in: dir, "2_ Older than 30 Days/\(dtName)/old.pdf"))
}

t.run("Organize: skips own age bucket folders") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    // Pre-create a bucket folder (as if from a previous organize)
    let recentDir = dir.appendingPathComponent("1_ Recent")
    try fm.createDirectory(at: recentDir, withIntermediateDirectories: true)
    let dtFolder = recentDir.appendingPathComponent("2026-03-01 10.00")
    try fm.createDirectory(at: dtFolder, withIntermediateDirectories: true)
    createFile(in: dtFolder, name: "old_organized.pdf")

    // Add a new file at root
    createFile(in: dir, name: "new_file.txt")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)

    // Should only organize the new root file, not touch existing bucket contents
    try t.assertEqual(result.filesMoved, 1, "Only the new root file should be moved")
    try t.assertTrue(exists(in: dir, "1_ Recent/2026-03-01 10.00/old_organized.pdf"),
        "Previously organized file should remain")
}

t.run("Organize: re-buckets aged date+time folders") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    // Create a date+time folder in "1_ Recent" that's actually 45 days old
    let recentDir = dir.appendingPathComponent("1_ Recent")
    try fm.createDirectory(at: recentDir, withIntermediateDirectories: true)

    let oldDate = daysAgo(45)
    let oldFolderName = FileOrganizer.folderName(for: oldDate)
    let oldFolder = recentDir.appendingPathComponent(oldFolderName)
    try fm.createDirectory(at: oldFolder, withIntermediateDirectories: true)
    createFile(in: oldFolder, name: "aged_file.pdf", date: oldDate)

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)

    // The folder should be re-bucketed from Recent to Older than 30 Days
    try t.assertFalse(exists(in: dir, "1_ Recent/\(oldFolderName)"),
        "Old folder should be removed from Recent")
    try t.assertTrue(exists(in: dir, "2_ Older than 30 Days/\(oldFolderName)/aged_file.pdf"),
        "Old folder should be moved to >30 Days bucket")
}

// ============================================================
// MARK: - Conflict Resolution
// ============================================================

t.run("Conflict: no conflict returns original") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let o = FileOrganizer()
    let resolved = o.resolveConflict(filename: "file.pdf", in: dir)
    try t.assertEqual(resolved.lastPathComponent, "file.pdf")
}

t.run("Conflict: first conflict gets (1)") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    fm.createFile(atPath: dir.appendingPathComponent("file.pdf").path, contents: nil)

    let o = FileOrganizer()
    let resolved = o.resolveConflict(filename: "file.pdf", in: dir)
    try t.assertEqual(resolved.lastPathComponent, "file (1).pdf")
}

t.run("Conflict: increments counter") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    fm.createFile(atPath: dir.appendingPathComponent("file.pdf").path, contents: nil)
    fm.createFile(atPath: dir.appendingPathComponent("file (1).pdf").path, contents: nil)

    let o = FileOrganizer()
    let resolved = o.resolveConflict(filename: "file.pdf", in: dir)
    try t.assertEqual(resolved.lastPathComponent, "file (2).pdf")
}

t.run("Conflict: handles no extension") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    fm.createFile(atPath: dir.appendingPathComponent("Makefile").path, contents: nil)

    let o = FileOrganizer()
    let resolved = o.resolveConflict(filename: "Makefile", in: dir)
    try t.assertEqual(resolved.lastPathComponent, "Makefile (1)")
}

// ============================================================
// MARK: - mostRecentDate
// ============================================================

t.run("Date: file returns its own mtime") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let yesterday = daysAgo(1)
    createFile(in: dir, name: "old.txt", date: yesterday)

    let o = FileOrganizer()
    let result = o.mostRecentDate(for: dir.appendingPathComponent("old.txt"))
    // Should be close to yesterday (within a second)
    try t.assertTrue(abs(result.timeIntervalSince(yesterday)) < 2.0,
        "File date should match what was set")
}

t.run("Date: folder returns most recent child") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let folder = dir.appendingPathComponent("project")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)

    let oldDate = daysAgo(10)
    let recentDate = daysAgo(1)
    createFile(in: folder, name: "old.txt", date: oldDate)
    createFile(in: folder, name: "new.txt", date: recentDate)

    let o = FileOrganizer()
    let result = o.mostRecentDate(for: folder)
    // Should be close to the more recent file
    try t.assertTrue(abs(result.timeIntervalSince(recentDate)) < 2.0,
        "Folder date should reflect most recent child")
}

// ============================================================
// MARK: - Undo Tests
// ============================================================

t.run("Undo: restores files to original locations") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "report.pdf")
    createFile(in: dir, name: "image.png")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    try t.assertEqual(result.filesMoved, 2)

    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)

    let (restored, errors) = try o.undo(ledger: &ledger)

    try t.assertEqual(restored, 2)
    try t.assertTrue(errors.isEmpty)
    try t.assertTrue(exists(in: dir, "report.pdf"), "report.pdf should be restored to root")
    try t.assertTrue(exists(in: dir, "image.png"), "image.png should be restored to root")
}

t.run("Undo: cleans up empty directories") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "file.pdf")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)

    _ = try o.undo(ledger: &ledger)

    let contents = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    let dirs = contents.filter { url in
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
    try t.assertTrue(dirs.isEmpty, "Empty directories should be cleaned up after undo")
}

t.run("Undo: blocked when new file added") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "original.pdf")
    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)

    // Add a new file to the organized area
    let dtName = dateTimeFolderName()
    createFile(in: dir, name: "1_ Recent/\(dtName)/intruder.txt")

    let reason = ledger.validateStateForUndo()
    try t.assertNotNil(reason, "Undo should be blocked when new files appear")
}

t.run("Undo: blocked when file removed") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "a.pdf")
    createFile(in: dir, name: "b.png")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)

    try fm.removeItem(atPath: result.moves.first!.destination)

    let reason = ledger.validateStateForUndo()
    try t.assertNotNil(reason, "Undo should be blocked when files are removed")
}

t.run("Undo: blocked when file modified") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "doc.pdf")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)

    try "modified content that is different".data(using: .utf8)!
        .write(to: URL(fileURLWithPath: result.moves.first!.destination))

    let reason = ledger.validateStateForUndo()
    try t.assertNotNil(reason, "Undo should be blocked when files are modified")
}

t.run("Undo: blocked when original location occupied") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "file.pdf")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)

    createFile(in: dir, name: "file.pdf")

    let reason = ledger.validateStateForUndo()
    try t.assertNotNil(reason, "Undo should be blocked when original location is occupied")
}

t.run("Undo: allowed when state unchanged") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "file.pdf")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)

    let reason = ledger.validateStateForUndo()
    try t.assertNil(reason, "Undo should be allowed when state is unchanged")
}

t.run("Undo: fresh ledger has no undoable operation") {
    let ledger = UndoLedger()
    try t.assertFalse(ledger.hasUndoableOperation)
}

t.run("Undo: ledger clears after undo") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    createFile(in: dir, name: "file.pdf")

    let o = FileOrganizer()
    let result = try o.organize(directory: dir.path)
    var ledger = UndoLedger()
    ledger.record(moves: result.moves, targetDirectory: dir.path)
    try t.assertTrue(ledger.hasUndoableOperation)

    _ = try o.undo(ledger: &ledger)
    try t.assertFalse(ledger.hasUndoableOperation)
}

t.run("Undo: ledger persistence round-trips") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let ledgerPath = dir.appendingPathComponent("test_ledger.json")

    var ledger = UndoLedger()
    ledger.record(
        moves: [FileMove(source: "/a/b.txt", destination: "/a/_1_ Recent/2026-03-06 14.32/b.txt")],
        targetDirectory: "/a"
    )

    try ledger.save(to: ledgerPath)
    let loaded = UndoLedger.load(from: ledgerPath)

    try t.assertEqual(loaded.lastMoves.count, 1)
    try t.assertEqual(loaded.lastMoves.first?.source, "/a/b.txt")
    try t.assertEqual(loaded.targetDirectory, "/a")
    try t.assertTrue(loaded.hasUndoableOperation)
}

t.run("Undo: load returns empty for missing file") {
    let dir = makeTempDir()
    defer { cleanup(dir) }

    let missing = dir.appendingPathComponent("nonexistent.json")
    let ledger = UndoLedger.load(from: missing)
    try t.assertFalse(ledger.hasUndoableOperation)
}

// ============================================================
// Results
// ============================================================

t.printResults()
exit(t.failed > 0 ? 1 : 0)
