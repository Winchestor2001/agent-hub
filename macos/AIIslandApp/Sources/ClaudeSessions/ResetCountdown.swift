import Foundation

/// Time left until a usage window resets, short enough for a popover caption:
/// "45m", "2h 15m", "3d 4h", or "now" once the reset time has passed.
public enum ResetCountdown {
    public static func text(until reset: TimeInterval, now: TimeInterval) -> String {
        let remaining = Int(reset - now)
        guard remaining >= 60 else { return remaining > 0 ? "1m" : "now" }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}
