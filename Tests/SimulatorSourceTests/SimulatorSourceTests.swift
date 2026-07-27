import Testing
import Foundation
@testable import SimulatorSource

@Test func parsesBootedDevicesFromSimctlJSON() throws {
    let payload = """
    {"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
        {"udid":"A1B2","name":"iPhone 17 Pro","state":"Booted","isAvailable":true}],
      "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[]
    }}
    """
    let devices = try SimctlSource.decodeBooted(Data(payload.utf8))

    #expect(devices.count == 1)
    #expect(devices[0].udid == "A1B2")
    #expect(devices[0].name == "iPhone 17 Pro")
    #expect(devices[0].runtime == "iOS 26.5")
}

@Test func ignoresDevicesThatAreNotBooted() throws {
    let payload = """
    {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
      {"udid":"A1B2","name":"iPhone 17 Pro","state":"Shutdown","isAvailable":true}]}}
    """

    #expect(try SimctlSource.decodeBooted(Data(payload.utf8)).isEmpty)
}

@Test func returnsNoDevicesWhenXcodeIsMissing() async {
    let source = SimctlSource(xcrunPath: "/nonexistent/xcrun")
    let devices = try? await source.booted()

    #expect(devices?.isEmpty ?? true)
}

@Test func liveSimctlIsQueryableOnThisMachine() async throws {
    let devices = try await SimctlSource().booted()

    #expect(devices.allSatisfy { !$0.udid.isEmpty })
}
