import Foundation

public struct ClaudeRateLimitWindow: Sendable, Equatable {
    public let usedPercent: Double
    public let resetsAt: Double?

    public init(usedPercent: Double, resetsAt: Double?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct ClaudeRateLimits: Sendable, Equatable {
    public let fiveHour: ClaudeRateLimitWindow?
    public let sevenDay: ClaudeRateLimitWindow?
    public let capturedAt: Double?
    public let stale: Bool
    public var maxPercent: Double { max(fiveHour?.usedPercent ?? 0, sevenDay?.usedPercent ?? 0) }

    public init(fiveHour: ClaudeRateLimitWindow?, sevenDay: ClaudeRateLimitWindow?, capturedAt: Double?, stale: Bool) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.capturedAt = capturedAt
        self.stale = stale
    }
}

// Reads the cache written by the user's global statusline (~/.claude/statusline.sh):
// {"captured_at": epoch, "rate_limits": {"five_hour": {"used_percentage", "resets_at"}, "seven_day": {...}}}.
// Claude Code only hands rate limits to the statusline, so this never touches
// settings, OAuth tokens, or the Keychain.
public enum ClaudeRateLimitCache {
    /// Older than this, the values are shown as last known.
    public static let staleAfter: Double = 20 * 60
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/agent-hub-rate-limits.json")
    }

    public static func read(_ url: URL = defaultURL, now: Double = Date().timeIntervalSince1970) -> ClaudeRateLimits? {
        guard let data = try? Data(contentsOf: url), data.count <= 64_000,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rates = json["rate_limits"] as? [String: Any] else { return nil }
        let fiveHour = window(rates["five_hour"], now: now), sevenDay = window(rates["seven_day"], now: now)
        guard fiveHour != nil || sevenDay != nil else { return nil }
        let captured = (json["captured_at"] as? NSNumber)?.doubleValue
        return ClaudeRateLimits(fiveHour: fiveHour, sevenDay: sevenDay, capturedAt: captured,
                                stale: captured.map { now - $0 > staleAfter } ?? true)
    }

    private static func window(_ raw: Any?, now: Double) -> ClaudeRateLimitWindow? {
        guard let raw = raw as? [String: Any], let used = (raw["used_percentage"] as? NSNumber)?.doubleValue,
              used.isFinite, (0...100).contains(used) else { return nil }
        let resets = (raw["resets_at"] as? NSNumber)?.doubleValue
        // The window rolled over after the snapshot: the old percentage no longer applies.
        if let resets, resets <= now { return nil }
        return ClaudeRateLimitWindow(usedPercent: used, resetsAt: resets)
    }
}
