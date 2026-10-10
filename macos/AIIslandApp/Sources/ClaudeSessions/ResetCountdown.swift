import Foundation

/// Time left until a usage window resets, short enough for a popover caption:
/// "45m", "2h 15m", "3d 4h", or "now" once the reset time has passed
/// (in Uzbek "45 daq", "2 soat 15 daq", "3 kun 4 soat", "hozir").
public enum ResetCountdown {
    public static func text(until reset: TimeInterval, now: TimeInterval) -> String {
        let remaining = Int(reset - now)
        guard remaining >= 60 else { return remaining > 0 ? tr("%@m", 1) : tr("now") }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return hours > 0 ? tr("%@d %@h", days, hours) : tr("%@d", days) }
        if hours > 0 { return minutes > 0 ? tr("%@h %@m", hours, minutes) : tr("%@h", hours) }
        return tr("%@m", minutes)
    }
}
