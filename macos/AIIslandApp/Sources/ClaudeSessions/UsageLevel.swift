import Foundation

/// How close a usage window is to its limit. The island, its bar and the
/// popover bars all color usage from this one rule.
public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical

    /// Used percentage at which usage turns yellow.
    public static let warningThreshold = 70.0
    /// Used percentage at which usage turns red and gets a non-color signal.
    public static let criticalThreshold = 90.0

    public init(percent: Double) {
        if percent >= Self.criticalThreshold {
            self = .critical
        } else if percent >= Self.warningThreshold {
            self = .warning
        } else {
            self = .normal
        }
    }
}
