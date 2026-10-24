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
