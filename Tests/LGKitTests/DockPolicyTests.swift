import Testing
@testable import LGKit

@Test func dockIconIsOffByDefaultAndFollowsTheSetting() {
    #expect(DockPolicy.isRegular(showInDock: false) == false)
    #expect(DockPolicy.isRegular(showInDock: true))
    #expect(DockPolicy.defaultsKey == "showInDock")
}
