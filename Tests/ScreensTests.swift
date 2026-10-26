
@Test func detailsDisplayIsTheOneMatchingTheEDID() {
    let id = HardwareScreenID(edid: lgInfo)
    #expect(DisplayDetailsReader.displayID(among: [macScreen, phl1, lgScreen, phl2], matching: id) == 2)
}
@Test func detailsDisplayIsNilWithoutAMatchOrID() {
    #expect(DisplayDetailsReader.displayID(among: [macScreen, phl1, phl2], matching: HardwareScreenID(edid: lgInfo)) == nil)
    #expect(DisplayDetailsReader.displayID(among: [lgScreen], matching: nil) == nil)
}
