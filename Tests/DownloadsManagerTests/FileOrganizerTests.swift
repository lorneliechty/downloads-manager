import XCTest
@testable import DownloadsManager

final class FileOrganizerTests: XCTestCase {
    var tempDir: URL!
    var organizer: FileOrganizer!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadsManagerTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        organizer = FileOrganizer()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Create a test file with a specific modification date.
    func createTestFile(name: String, date: Date? = nil) {
        let path = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: path.path, contents: "test".data(using: .utf8))

        if let date = date {
            try? FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: path.path
            )
        }
    }

    func createTestDirectory(name: String) {
        let path = tempDir.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }

    func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(relativePath).path)
    }

    // MARK: - Categorization

    func testCategorizePDF() {
        XCTAssertEqual(organizer.categorize(extension: "pdf"), "Documents")
    }

    func testCategorizePNG() {
        XCTAssertEqual(organizer.categorize(extension: "png"), "Images")
    }

    func testCategorizeUnknown() {
        XCTAssertEqual(organizer.categorize(extension: "xyz123"), "Other")
    }

    func testCategorizeEmptyExtension() {
        XCTAssertEqual(organizer.categorize(extension: ""), "Other")
    }

    // MARK: - Organize

    func testOrganizeMovesFilesToDateTypeFolders() throws {
        let today = Date()
        createTestFile(name: "report.pdf", date: today)
        createTestFile(name: "photo.png", date: today)

        let result = try organizer.organize(directory: tempDir.path)

        XCTAssertEqual(result.filesMoved, 2)
        XCTAssertFalse(fileExists("report.pdf"), "report.pdf should be moved from root")
        XCTAssertFalse(fileExists("photo.png"), "photo.png should be moved from root")

        // Files should be in date/type folders
        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: today)
        }()

        XCTAssertTrue(fileExists("\(dateStr)/Documents/report.pdf"))
        XCTAssertTrue(fileExists("\(dateStr)/Images/photo.png"))
    }

    func testOrganizeSkipsDirectories() throws {
        createTestFile(name: "file.txt")
        createTestDirectory(name: "MyFolder")

        let result = try organizer.organize(directory: tempDir.path)

        XCTAssertEqual(result.filesMoved, 1)
        XCTAssertTrue(fileExists("MyFolder"), "Directories should be left alone")
    }

    func testOrganizeSkipsPartialDownloads() throws {
        createTestFile(name: "bigfile.crdownload")
        createTestFile(name: "another.part")
        createTestFile(name: "real.pdf")

        let result = try organizer.organize(directory: tempDir.path)

        XCTAssertEqual(result.filesMoved, 1)
        XCTAssertEqual(result.filesSkipped, 2)
        XCTAssertTrue(fileExists("bigfile.crdownload"), "Partial downloads should stay")
        XCTAssertTrue(fileExists("another.part"), "Partial downloads should stay")
    }

    func testOrganizeEmptyDirectorySucceeds() throws {
        let result = try organizer.organize(directory: tempDir.path)
        XCTAssertEqual(result.filesMoved, 0)
        XCTAssertEqual(result.filesSkipped, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testOrganizeGroupsByModificationDate() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        createTestFile(name: "today.pdf", date: today)
        createTestFile(name: "yesterday.pdf", date: yesterday)

        let result = try organizer.organize(directory: tempDir.path)

        XCTAssertEqual(result.filesMoved, 2)

        let todayStr = formatter.string(from: today)
        let yesterdayStr = formatter.string(from: yesterday)

        XCTAssertTrue(fileExists("\(todayStr)/Documents/today.pdf"))
        XCTAssertTrue(fileExists("\(yesterdayStr)/Documents/yesterday.pdf"))
    }

    // MARK: - Conflict Resolution

    func testConflictResolutionRenamesWithCounter() {
        let dir = tempDir!

        // Create a file already in the destination
        let destDir = dir.appendingPathComponent("dest")
        try! FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: destDir.appendingPathComponent("file.pdf").path,
            contents: "original".data(using: .utf8)
        )

        let resolved = organizer.resolveConflict(filename: "file.pdf", in: destDir)
        XCTAssertEqual(resolved.lastPathComponent, "file (1).pdf")
    }

    func testConflictResolutionIncrementsCounter() {
        let destDir = tempDir.appendingPathComponent("dest")
        try! FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Create file.pdf and file (1).pdf
        FileManager.default.createFile(
            atPath: destDir.appendingPathComponent("file.pdf").path,
            contents: nil
        )
        FileManager.default.createFile(
            atPath: destDir.appendingPathComponent("file (1).pdf").path,
            contents: nil
        )

        let resolved = organizer.resolveConflict(filename: "file.pdf", in: destDir)
        XCTAssertEqual(resolved.lastPathComponent, "file (2).pdf")
    }

    func testConflictResolutionHandlesNoExtension() {
        let destDir = tempDir.appendingPathComponent("dest")
        try! FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        FileManager.default.createFile(
            atPath: destDir.appendingPathComponent("Makefile").path,
            contents: nil
        )

        let resolved = organizer.resolveConflict(filename: "Makefile", in: destDir)
        XCTAssertEqual(resolved.lastPathComponent, "Makefile (1)")
    }
}
