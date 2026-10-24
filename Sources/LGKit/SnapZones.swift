import CoreGraphics

public enum SnapZones {
    /// Returns [left, right] in Cocoa coordinates. The left half floors so the right half
    /// absorbs the odd pixel and the two always tile the frame exactly.
    public static func halves(of visibleFrame: CGRect) -> [CGRect] {
        let leftWidth = (visibleFrame.width / 2).rounded(.down)
        let left = CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: leftWidth, height: visibleFrame.height)
        let right = CGRect(x: visibleFrame.minX + leftWidth, y: visibleFrame.minY, width: visibleFrame.width - leftWidth, height: visibleFrame.height)
        return [left, right]
    }

    public static func zoneIndex(at point: CGPoint, in zones: [CGRect]) -> Int? {
        zones.firstIndex { $0.contains(point) }
    }

    /// Accessibility uses a top-left origin anchored to the primary screen (NSScreen.screens[0]),
    /// not NSScreen.main, which follows keyboard focus.
    public static func axRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func axPoint(fromCocoa p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryScreenHeight - p.y)
    }
}
