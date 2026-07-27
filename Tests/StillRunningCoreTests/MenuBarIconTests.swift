import Testing
import Foundation
@testable import StillRunningCore

/// The menu bar summary is pure arithmetic over two numbers, so it is tested
/// here rather than looked at.
@Test func aCleanMachineGetsAQuietIconAndNoNumber() {
    #expect(MenuBarSummary.symbolName(findingCount: 0, wastedCPU: 0) == "circle")
    #expect(MenuBarSummary.label(findingCount: 0, wastedCPU: 0) == nil)
}

@Test func somethingLeftOverButIdleShowsTheCount() {
    #expect(MenuBarSummary.symbolName(findingCount: 3, wastedCPU: 0) == "circle.dotted.circle")
    #expect(MenuBarSummary.label(findingCount: 3, wastedCPU: 0) == "3")
}

@Test func realBurningShowsAFlameAndThePercentage() {
    #expect(MenuBarSummary.symbolName(findingCount: 2, wastedCPU: 140) == "flame")
    #expect(MenuBarSummary.label(findingCount: 2, wastedCPU: 140) == "140%")
}

@Test func aLittleCPUIsNotYetAFlame() {
    #expect(MenuBarSummary.symbolName(findingCount: 2, wastedCPU: 30) == "circle.dotted.circle")
    #expect(MenuBarSummary.label(findingCount: 2, wastedCPU: 30) == "30%")
}
