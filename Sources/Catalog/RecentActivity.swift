import SharedKernel

/// A folder changed inside this window may still be in use by a build.
public enum RecentActivity {
    public static let windowSeconds: Int64 = 86_400
    public static let blockedReason = "Changed in the last 24 hours. Wait until no build uses it."

    /// The blocked reason when `newestChange` is inside the window of `now`, otherwise nil.
    public static func reason(newestChange: Instant?, now: Instant) -> String? {
        guard let newestChange, isInsideWindow(newestChange, now: now) else { return nil }
        return blockedReason
    }

    private static func isInsideWindow(_ newest: Instant, now: Instant) -> Bool {
        let (window, overflowed) = windowSeconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflowed else { return false }
        let (age, ageOverflowed) = now.nanosecondsSince1970.subtractingReportingOverflow(newest.nanosecondsSince1970)
        if ageOverflowed { return newest >= now }
        return age <= window
    }
}
