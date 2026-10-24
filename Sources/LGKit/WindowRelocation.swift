import CoreGraphics

/// Where a window goes when it leaves the LG for the MacBook, and back.
///
/// All rects are in one coordinate space; the app uses Accessibility coordinates (top-left origin,
/// anchored to the primary screen) because that is what it reads from and writes to other apps'
/// windows. The maths only needs `minX/minY` to be the same corner in every rect, so it works in
/// Cocoa coordinates too, with "top" and "bottom" swapped.
public enum WindowRelocation {
    public static func target(for window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let width = min(window.width, destination.width)
        let height = min(window.height, destination.height)
        // Position as a share of the free space rather than of the screen, so a window touching an
        // edge of the LG touches the same edge of the MacBook, and a centred one stays centred.
        let fx = share(window.minX - source.minX, free: source.width - window.width)
        let fy = share(window.minY - source.minY, free: source.height - window.height)
        return CGRect(x: destination.minX + fx * (destination.width - width),
                      y: destination.minY + fy * (destination.height - height),
                      width: width, height: height)
    }

    /// The centre decides, as it does for macOS when it picks a window's screen.
    public static func isOn(_ window: CGRect, screen: CGRect) -> Bool {
        screen.contains(CGPoint(x: window.midX, y: window.midY))
    }

    /// Clamped to 0...1 so a window hanging off the LG still lands wholly on the MacBook. A window
    /// as big as the LG or bigger has no free space to place it in; centre it.
    private static func share(_ offset: CGFloat, free: CGFloat) -> CGFloat {
        guard free > 0 else { return 0.5 }
        return min(max(offset / free, 0), 1)
    }
}
