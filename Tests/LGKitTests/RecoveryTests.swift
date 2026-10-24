import CoreGraphics
import Testing
@testable import LGKit

// MARK: RetryPolicy

@Test func retryDelayIsThreeSecondsForTheFirstTenFailures() {
    for failures in 0...10 { #expect(RetryPolicy.delay(afterFailures: failures) == 3, "\(failures)") }
}
@Test func retryDelayBacksOffToTenSecondsAfterTenFailures() {
    for failures in [11, 12, 50, 10_000] { #expect(RetryPolicy.delay(afterFailures: failures) == 10, "\(failures)") }
}
@Test func retryDelayTreatsANegativeCountAsZero() {
    #expect(RetryPolicy.delay(afterFailures: -1) == 3)
}

// MARK: WindowPlacement (all-windows path)

@Test func allWindowsMoveOnlyWhenLeavingTheMacWithABuiltInScreen() {
    #expect(WindowPlacement.shouldMoveToBuiltIn(target: .ps5, builtInAvailable: true))
    #expect(WindowPlacement.shouldMoveToBuiltIn(target: .windows, builtInAvailable: true))
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .mac, builtInAvailable: true))
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .ps5, builtInAvailable: false))
}

// MARK: WindowRelocation (Accessibility coordinates: top-left origin)

// The MacBook is the primary screen; the LG sits to its right and higher up.
private let macBookVisible = CGRect(x: 0, y: 33, width: 1512, height: 949)
private let lgFrame = CGRect(x: 1512, y: -300, width: 2560, height: 1440)

@Test func windowCentredOnTheLGLandsCentredOnTheMacBook() {
    let window = CGRect(x: lgFrame.midX - 400, y: lgFrame.midY - 300, width: 800, height: 600)
    let target = WindowRelocation.target(for: window, from: lgFrame, to: macBookVisible)
    #expect(target.size == CGSize(width: 800, height: 600))
    #expect(target.midX == macBookVisible.midX)
    #expect(target.midY == macBookVisible.midY)
}
@Test func lgSizedWindowShrinksToTheMacBooksVisibleFrame() {
    let target = WindowRelocation.target(for: lgFrame, from: lgFrame, to: macBookVisible)
    #expect(target == macBookVisible)
}
@Test func windowAtTheLGsTopLeftLandsAtTheMacBooksTopLeft() {
    let window = CGRect(origin: lgFrame.origin, size: CGSize(width: 700, height: 500))
    let target = WindowRelocation.target(for: window, from: lgFrame, to: macBookVisible)
    #expect(target == CGRect(origin: macBookVisible.origin, size: window.size))
}
@Test func windowAtTheLGsBottomRightLandsAtTheMacBooksBottomRight() {
    let window = CGRect(x: lgFrame.maxX - 700, y: lgFrame.maxY - 500, width: 700, height: 500)
    let target = WindowRelocation.target(for: window, from: lgFrame, to: macBookVisible)
    #expect(target.maxX == macBookVisible.maxX)
    #expect(target.maxY == macBookVisible.maxY)
}
@Test func relocatedWindowAlwaysLiesInsideTheDestination() {
    // Hanging off the LG's edges, and taller than the MacBook.
    let windows = [CGRect(x: lgFrame.maxX - 100, y: lgFrame.minY - 50, width: 900, height: 1200),
                   CGRect(x: lgFrame.minX - 300, y: lgFrame.maxY - 20, width: 3000, height: 400)]
    for window in windows {
        let target = WindowRelocation.target(for: window, from: lgFrame, to: macBookVisible)
        #expect(macBookVisible.contains(target), "\(window) -> \(target)")
        #expect(target.width <= window.width && target.height <= window.height)
    }
}
@Test func windowMostlyOnTheMacBookIsNotOnTheLG() {
    let window = CGRect(x: 1000, y: 100, width: 800, height: 600)   // 512 pt on the MacBook, 288 on the LG
    #expect(!WindowRelocation.isOn(window, screen: lgFrame))
    #expect(WindowRelocation.isOn(window, screen: CGRect(x: 0, y: 0, width: 1512, height: 982)))
}
@Test func windowMostlyOnTheLGIsOnTheLG() {
    let window = CGRect(x: 1300, y: 100, width: 800, height: 600)
    #expect(WindowRelocation.isOn(window, screen: lgFrame))
}

// MARK: AudioRestore

@Test func restoresTheLGOnlyWhenItWasTheOutputIsBackAndMacOSFellBackToTheMacBook() {
    #expect(AudioRestore.shouldRestore(lgWasOutput: true, lgDeviceAvailable: true, currentIsLG: false, currentIsBuiltIn: true))
}
@Test func doesNotRestoreWhenTheLGWasNotTheOutput() {
    #expect(!AudioRestore.shouldRestore(lgWasOutput: false, lgDeviceAvailable: true, currentIsLG: false, currentIsBuiltIn: true))
}
@Test func doesNotRestoreWhileTheLGDeviceIsMissing() {
    #expect(!AudioRestore.shouldRestore(lgWasOutput: true, lgDeviceAvailable: false, currentIsLG: false, currentIsBuiltIn: true))
}
@Test func doesNotRestoreWhenTheLGIsAlreadyTheOutput() {
    #expect(!AudioRestore.shouldRestore(lgWasOutput: true, lgDeviceAvailable: true, currentIsLG: true, currentIsBuiltIn: false))
}
@Test func doesNotOverrideAnOutputTheUserPicked() {
    #expect(!AudioRestore.shouldRestore(lgWasOutput: true, lgDeviceAvailable: true, currentIsLG: false, currentIsBuiltIn: false))
}
@Test func audioRestoreTruthTable() {
    for bits in 0..<16 {
        let was = bits & 1 != 0, available = bits & 2 != 0, isLG = bits & 4 != 0, builtIn = bits & 8 != 0
        let expected = was && available && !isLG && builtIn
        #expect(AudioRestore.shouldRestore(lgWasOutput: was, lgDeviceAvailable: available,
                                           currentIsLG: isLG, currentIsBuiltIn: builtIn) == expected, "\(bits)")
    }
}
