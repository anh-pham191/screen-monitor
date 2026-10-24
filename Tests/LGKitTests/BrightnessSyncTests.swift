import Testing
@testable import LGKit

@Suite struct BrightnessSyncTests {
    @Test func targetFollowsBuiltInWithOffset() {
        #expect(BrightnessSync.target(builtIn: 0.5, offset: 0, maximum: 100) == 50)
        #expect(BrightnessSync.target(builtIn: 0.5, offset: -24, maximum: 100) == 26)
        #expect(BrightnessSync.target(builtIn: 0.95, offset: 20, maximum: 100) == 100)
        #expect(BrightnessSync.target(builtIn: 0.05, offset: -20, maximum: 100) == 0)
    }
    @Test func offsetFromManualChange() {
        #expect(BrightnessSync.offset(lg: 26, builtIn: 0.5, maximum: 100) == -24)
        #expect(BrightnessSync.offset(lg: 50, builtIn: 0.5, maximum: 100) == 0)
    }
    @Test func ignoresTinyChanges() {
        #expect(!BrightnessSync.isMeaningfulChange(from: 0.465, to: 0.47))
        #expect(BrightnessSync.isMeaningfulChange(from: 0.465, to: 0.48))
    }
}

@Suite struct BrightnessSyncGuardTests {
    @Test func nonFiniteBuiltInIsClampedNotTrapped() {
        #expect(BrightnessSync.target(builtIn: .nan, offset: 0, maximum: 100) == 0)
        #expect(BrightnessSync.target(builtIn: .infinity, offset: 0, maximum: 100) == 100)
        #expect(BrightnessSync.target(builtIn: -.infinity, offset: 10, maximum: 100) == 10)
        #expect(BrightnessSync.target(builtIn: 1.7, offset: -10, maximum: 100) == 90)
        #expect(BrightnessSync.offset(lg: 40, builtIn: .nan, maximum: 100) == 40)
        #expect(BrightnessSync.offset(lg: 40, builtIn: .infinity, maximum: 100) == -60)
    }
}

@Suite struct BrightnessFollowerTests {
    @Test func turningOnCapturesTheOffsetSoTheLGDoesNotJump() {
        var f = BrightnessFollower()
        let write = f.enable(lg: 26, builtIn: 0.5, maximum: 100)
        #expect(f.offset == -24)
        #expect(write == 26)
    }

    @Test func syncWriteNeverChangesTheOffset() {
        var f = BrightnessFollower(offset: 20)
        #expect(f.poll(builtIn: 0.95, maximum: 100) == 100)   // clamped
        #expect(f.offset == 20)
        #expect(f.poll(builtIn: 0.30, maximum: 100) == 50)
        #expect(f.offset == 20)
    }

    @Test func firstPollAppliesThenOnlyMeaningfulChanges() {
        var f = BrightnessFollower(offset: 0)
        #expect(f.poll(builtIn: 0.465, maximum: 100) == 47)
        #expect(f.poll(builtIn: 0.47, maximum: 100) == nil)
        #expect(f.poll(builtIn: 0.48, maximum: 100) == 48)
    }

    @Test func slowRampIsComparedWithTheLastAppliedValue() {
        var f = BrightnessFollower(offset: 0)
        #expect(f.poll(builtIn: 0.500, maximum: 100) == 50)
        #expect(f.poll(builtIn: 0.504, maximum: 100) == nil)
        #expect(f.poll(builtIn: 0.508, maximum: 100) == nil)
        // Each step was below the threshold, but the total since the last write is not.
        #expect(f.poll(builtIn: 0.512, maximum: 100) == 51)
    }

    @Test func manualChangeRecomputesTheOffset() {
        var f = BrightnessFollower(offset: 0)
        _ = f.poll(builtIn: 0.5, maximum: 100)
        f.manualChange(lg: 30, builtIn: 0.5, maximum: 100)
        #expect(f.offset == -20)
        // The manual change is the new baseline: an unchanged built-in writes nothing.
        #expect(f.poll(builtIn: 0.5, maximum: 100) == nil)
        #expect(f.poll(builtIn: 0.7, maximum: 100) == 50)
        #expect(f.offset == -20)
    }

    @Test func manualChangeWithoutAReadingKeepsTheOffset() {
        var f = BrightnessFollower(offset: 7)
        f.manualChange(lg: 30, builtIn: nil, maximum: 100)
        #expect(f.offset == 7)
    }

    @Test func resetZeroesTheOffsetAndApplies() {
        var f = BrightnessFollower(offset: -24)
        #expect(f.reset(builtIn: 0.5, maximum: 100) == 50)
        #expect(f.offset == 0)
        #expect(f.poll(builtIn: 0.5, maximum: 100) == nil)
    }

    @Test func resetWithoutAReadingOnlyZeroes() {
        var f = BrightnessFollower(offset: -24)
        #expect(f.reset(builtIn: nil, maximum: 100) == nil)
        #expect(f.offset == 0)
    }

    @Test func unusableInputsWriteNothing() {
        var f = BrightnessFollower(offset: 0)
        #expect(f.poll(builtIn: .nan, maximum: 100) == nil)
        #expect(f.poll(builtIn: 0.5, maximum: 0) == nil)
        #expect(f.enable(lg: 10, builtIn: 0.5, maximum: 0) == nil)
        #expect(f.offset == 0)
    }

    @Test func enableWithoutAReadingKeepsTheStoredOffset() {
        var f = BrightnessFollower(offset: 12)
        #expect(f.enable(lg: 40, builtIn: nil, maximum: 100) == nil)
        #expect(f.offset == 12)
        #expect(f.poll(builtIn: 0.5, maximum: 100) == 62)
    }
}
