import Testing
import Foundation
@testable import DockerClient

@Test func parsesStatusAndBody() throws {
    let raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n[{\"Id\":\"abc\"}]"
    let response = try HTTPResponse(raw: Data(raw.utf8))

    #expect(response.status == 200)
    #expect(String(decoding: response.body, as: UTF8.self) == "[{\"Id\":\"abc\"}]")
}

@Test func parsesAnEmptyBody() throws {
    let response = try HTTPResponse(raw: Data("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n".utf8))

    #expect(response.status == 204)
    #expect(response.body.isEmpty)
}

@Test func rejectsAResponseWithoutAHeaderTerminator() {
    #expect(throws: HTTPError.self) {
        _ = try HTTPResponse(raw: Data("HTTP/1.1 200 OK\r\nContent-Type: x".utf8))
    }
}

@Test func rejectsAMalformedStatusLine() {
    #expect(throws: HTTPError.self) {
        _ = try HTTPResponse(raw: Data("GARBAGE\r\n\r\n".utf8))
    }
}

@Test func undoesChunkedFraming() throws {
    // What the daemon actually sends, even with Connection: close.
    let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        + "5\r\n[{\"a\"\r\n4\r\n:1}]\r\n0\r\n\r\n"
    let response = try HTTPResponse(raw: Data(raw.utf8))

    #expect(response.status == 200)
    #expect(String(decoding: response.body, as: UTF8.self) == "[{\"a\":1}]")
}

@Test func leavesUnchunkedBodiesAlone() throws {
    let raw = "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc"
    let response = try HTTPResponse(raw: Data(raw.utf8))

    #expect(String(decoding: response.body, as: UTF8.self) == "abc")
}

@Test func rejectsAChunkHeaderThatIsNotHexadecimal() {
    let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nbody\r\n0\r\n\r\n"

    #expect(throws: HTTPError.self) { _ = try HTTPResponse(raw: Data(raw.utf8)) }
}

@Test func decodesTheContainerListPayload() throws {
    let payload = """
    [{"Id":"09ac719c3957","Names":["/selene-web"],"Image":"selene-backend-web",
      "Created":1785000000,"State":"running","Status":"Up 20 hours"}]
    """
    let containers = try DockerClient.decodeContainers(Data(payload.utf8))

    #expect(containers.count == 1)
    #expect(containers[0].id == "09ac719c3957")
    #expect(containers[0].displayName == "selene-web")   // leading slash stripped
    #expect(containers[0].state == "running")
    #expect(containers[0].created == Date(timeIntervalSince1970: 1_785_000_000))
}

@Test func readsTheStartTimeOfTheCurrentRunFromInspect() throws {
    // A container created weeks ago but restarted yesterday must report
    // yesterday. The list endpoint alone would report the creation date.
    let payload = """
    {"Id":"abc","State":{"Status":"running","StartedAt":"2026-07-26T20:55:13.045630605Z"}}
    """
    let started = try DockerClient.decodeStartedAt(Data(payload.utf8))

    #expect(started == ISO8601DateFormatter().date(from: "2026-07-26T20:55:13Z"))
}

@Test func toleratesTimestampsWithoutAFractionalPart() {
    #expect(DockerClient.parseDockerTimestamp("2026-07-26T20:55:13Z")
            == ISO8601DateFormatter().date(from: "2026-07-26T20:55:13Z"))
}

@Test func rejectsAnUnparsableTimestamp() {
    #expect(DockerClient.parseDockerTimestamp("not a date") == nil)
}

@Test func containerFallsBackToCreationTimeWithoutAStartTime() throws {
    let payload = """
    [{"Id":"abc","Names":["/x"],"Image":"i","Created":1785000000,"State":"running"}]
    """
    let container = try DockerClient.decodeContainers(Data(payload.utf8))[0]

    #expect(container.started == nil)
    #expect(container.runningSince == Date(timeIntervalSince1970: 1_785_000_000))
}

@Test func prefersTheOrbStackSocketWhenSeveralExist() {
    let candidates = DockerClient.socketCandidates(home: "/Users/x")

    #expect(candidates.first == "/Users/x/.orbstack/run/docker.sock")
    #expect(candidates.contains("/var/run/docker.sock"))
}

@Test func liveDaemonListsContainersWhenASocketIsPresent() async throws {
    guard let client = DockerClient.discover() else { return }   // no daemon: nothing to assert
    let containers = try await client.containers()

    #expect(containers.allSatisfy { !$0.id.isEmpty })
    #expect(containers.allSatisfy { !$0.displayName.hasPrefix("/") })
}
