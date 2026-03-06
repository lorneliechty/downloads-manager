import Foundation

/// A category that files can be sorted into, defined by a name and a set of file extensions.
public struct FileCategory: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let extensions: Set<String>

    public init(name: String, extensions: Set<String>) {
        self.name = name
        // Normalize: lowercase, no leading dots
        self.extensions = Set(extensions.map { ext in
            ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        })
    }

    /// Check if this category matches a given file extension.
    public func matches(extension ext: String) -> Bool {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return extensions.contains(normalized)
    }
}

// MARK: - Default Categories

extension FileCategory {
    public static let documents = FileCategory(
        name: "Documents",
        extensions: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                     "txt", "rtf", "csv", "pages", "numbers", "keynote",
                     "odt", "ods", "odp", "md", "tex"]
    )

    public static let images = FileCategory(
        name: "Images",
        extensions: ["jpg", "jpeg", "png", "gif", "svg", "webp", "heic",
                     "tiff", "tif", "bmp", "ico", "psd", "ai", "eps",
                     "raw", "cr2", "nef", "arw"]
    )

    public static let videos = FileCategory(
        name: "Videos",
        extensions: ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm",
                     "m4v", "mpg", "mpeg", "3gp"]
    )

    public static let audio = FileCategory(
        name: "Audio",
        extensions: ["mp3", "wav", "aac", "flac", "ogg", "m4a", "wma",
                     "aiff", "alac", "opus"]
    )

    /// Note: compound extensions like .tar.gz aren't supported because
    /// pathExtension only returns the last component. A file named
    /// archive.tar.gz has pathExtension "gz", which matches here.
    /// The .tar part stays in the filename, which is fine.
    public static let archives = FileCategory(
        name: "Archives",
        extensions: ["zip", "tar", "gz", "rar", "7z", "bz2", "xz", "tgz"]
    )

    public static let installers = FileCategory(
        name: "Installers",
        extensions: ["pkg", "dmg", "app", "iso", "msi", "exe"]
    )

    public static let code = FileCategory(
        name: "Code",
        extensions: ["js", "ts", "py", "swift", "java", "c", "cpp", "h",
                     "rb", "go", "rs", "json", "xml", "yaml", "yml",
                     "html", "css", "sh", "bash", "zsh", "sql", "r",
                     "m", "kt", "scala", "hs", "lua", "pl", "php"]
    )

    /// The default set of categories, checked in order. First match wins.
    /// Order matters: installers before archives (dmg appears in both).
    public static let defaults: [FileCategory] = [
        .documents, .images, .videos, .audio, .installers, .archives, .code
    ]
}
