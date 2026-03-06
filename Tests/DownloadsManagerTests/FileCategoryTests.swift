import XCTest
@testable import DownloadsManager

final class FileCategoryTests: XCTestCase {

    // MARK: - Extension Matching

    func testMatchesExactExtension() {
        let cat = FileCategory(name: "Docs", extensions: ["pdf", "txt"])
        XCTAssertTrue(cat.matches(extension: "pdf"))
        XCTAssertTrue(cat.matches(extension: "txt"))
        XCTAssertFalse(cat.matches(extension: "png"))
    }

    func testMatchesIsCaseInsensitive() {
        let cat = FileCategory(name: "Docs", extensions: ["PDF", "TXT"])
        XCTAssertTrue(cat.matches(extension: "pdf"))
        XCTAssertTrue(cat.matches(extension: "PDF"))
        XCTAssertTrue(cat.matches(extension: "Pdf"))
    }

    func testMatchesStripsLeadingDot() {
        let cat = FileCategory(name: "Docs", extensions: [".pdf"])
        XCTAssertTrue(cat.matches(extension: "pdf"))
        XCTAssertTrue(cat.matches(extension: ".pdf"))
    }

    // MARK: - Default Categories

    func testDefaultCategoriesAreNonEmpty() {
        XCTAssertFalse(FileCategory.defaults.isEmpty)
        for cat in FileCategory.defaults {
            XCTAssertFalse(cat.name.isEmpty)
            XCTAssertFalse(cat.extensions.isEmpty)
        }
    }

    func testCommonExtensionsAreCategorized() {
        let allExtensions = FileCategory.defaults.flatMap { $0.extensions }
        let common = ["pdf", "jpg", "png", "mp4", "zip", "dmg", "py", "mp3"]
        for ext in common {
            XCTAssertTrue(allExtensions.contains(ext), "\(ext) should be in default categories")
        }
    }

    func testInstallersBeforeArchives() {
        // dmg should be in Installers, which comes before Archives in the defaults
        let organizer = FileOrganizer()
        let result = organizer.categorize(extension: "dmg")
        XCTAssertEqual(result, "Installers", "dmg should categorize as Installers, not Archives")
    }

    func testCompoundExtensionLastComponentMatches() {
        // pathExtension on "archive.tar.gz" returns "gz" — that should match Archives
        let organizer = FileOrganizer()
        XCTAssertEqual(organizer.categorize(extension: "gz"), "Archives")
        XCTAssertEqual(organizer.categorize(extension: "bz2"), "Archives")
        XCTAssertEqual(organizer.categorize(extension: "xz"), "Archives")
    }
}
