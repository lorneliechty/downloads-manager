import Foundation

/// Age-based grouping buckets for organized content.
/// Prefixed with 1_, 2_, etc. so they sort correctly by name in Finder.
public enum AgeBucket: String, CaseIterable, Codable, Sendable {
    case recent = "1_ Recent"
    case olderThan30Days = "2_ Older than 30 Days"
    case olderThan90Days = "3_ Older than 90 Days"
    case olderThan1Year = "4_ Older than 1 Year"

    /// Determine which bucket a date falls into relative to a reference date.
    public static func bucket(for date: Date, relativeTo now: Date = Date()) -> AgeBucket {
        let calendar = Calendar.current
        let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0

        if daysDiff > 365 {
            return .olderThan1Year
        } else if daysDiff > 90 {
            return .olderThan90Days
        } else if daysDiff > 30 {
            return .olderThan30Days
        } else {
            return .recent
        }
    }

    /// All buckets in age order (newest first).
    public static var allInOrder: [AgeBucket] {
        [.recent, .olderThan30Days, .olderThan90Days, .olderThan1Year]
    }
}
