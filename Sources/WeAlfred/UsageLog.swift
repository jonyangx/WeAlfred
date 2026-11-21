import Foundation

enum UsageLog {
    private static let countsKey = "applicationOpenCounts"

    static func record(_ id: String, in defaults: UserDefaults = .standard) {
        var counts = counts(in: defaults)
        counts[id, default: 0] += 1
        defaults.set(counts, forKey: countsKey)
    }

    static func counts(in defaults: UserDefaults = .standard) -> [String: Int] {
        defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }
}
