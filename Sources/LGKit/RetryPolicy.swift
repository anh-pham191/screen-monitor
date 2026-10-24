import Foundation

/// How long to wait before looking for the LG again after a refresh failed.
///
/// The LG doesn't always post a screen-change notification when it changes input, so a failed
/// refresh can otherwise leave "not connected" on screen while the LG answers fine. Quick retries
/// cover the usual case (a read right after an input switch); backing off keeps a genuinely absent
/// LG from costing a DDC timeout every few seconds forever.
public enum RetryPolicy {
    public static let quickDelay: TimeInterval = 3
    public static let slowDelay: TimeInterval = 10
    public static let quickAttempts = 10

    public static func delay(afterFailures failures: Int) -> TimeInterval {
        failures > quickAttempts ? slowDelay : quickDelay
    }
}
