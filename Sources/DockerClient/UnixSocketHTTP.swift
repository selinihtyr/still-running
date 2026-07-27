import Foundation
import Network

public enum HTTPError: Error, Equatable {
    case malformedResponse
    case socketUnavailable
    case transport(String)
    case status(Int, String)
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(raw: Data) throws {
        let terminator = Data("\r\n\r\n".utf8)
        guard let range = raw.range(of: terminator) else { throw HTTPError.malformedResponse }
        let head = String(decoding: raw[..<range.lowerBound], as: UTF8.self)
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let statusLine = lines.first,
              statusLine.hasPrefix("HTTP/"),
              let code = Int(statusLine.split(separator: " ").dropFirst().first.map(String.init) ?? "")
        else { throw HTTPError.malformedResponse }

        self.status = code

        // The Docker daemon chunks its responses even when asked to close the
        // connection, so the framing has to be undone before the body is JSON.
        let isChunked = lines.dropFirst().contains {
            $0.lowercased().replacingOccurrences(of: " ", with: "") == "transfer-encoding:chunked"
        }
        let payload = Data(raw[range.upperBound...])
        self.body = isChunked ? try HTTPResponse.dechunk(payload) : payload
    }

    /// Undoes `<hex length>\r\n<bytes>\r\n` framing, ending at a zero-length chunk.
    static func dechunk(_ data: Data) throws -> Data {
        var result = Data()
        var cursor = data.startIndex
        let separator = Data("\r\n".utf8)

        while cursor < data.endIndex {
            guard let lineEnd = data[cursor...].range(of: separator) else { throw HTTPError.malformedResponse }
            // A chunk header may carry extensions after a semicolon; the size is the first field.
            let header = String(decoding: data[cursor..<lineEnd.lowerBound], as: UTF8.self)
            let sizeField = header.split(separator: ";").first.map(String.init) ?? header
            guard let size = Int(sizeField.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw HTTPError.malformedResponse
            }
            if size == 0 { break }

            let chunkStart = lineEnd.upperBound
            guard let chunkEnd = data.index(chunkStart, offsetBy: size, limitedBy: data.endIndex) else {
                throw HTTPError.malformedResponse
            }
            result.append(data[chunkStart..<chunkEnd])
            // Skip the CRLF that terminates the chunk body.
            cursor = data.index(chunkEnd, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
        }
        return result
    }
}

/// Minimal HTTP/1.1 over a unix domain socket. One request per connection,
/// always with `Connection: close`, so the body is simply everything received
/// before the peer hangs up — no chunked or Content-Length handling needed.
public struct UnixSocketHTTP: Sendable {
    public let socketPath: String

    public init(socketPath: String) { self.socketPath = socketPath }

    public func send(method: String, path: String, timeout: TimeInterval = 10) async throws -> HTTPResponse {
        let request = """
        \(method) \(path) HTTP/1.1\r
        Host: localhost\r
        Accept: application/json\r
        Connection: close\r
        \r

        """
        let raw = try await exchange(Data(request.utf8), timeout: timeout)
        return try HTTPResponse(raw: raw)
    }

    private func exchange(_ request: Data, timeout: TimeInterval) async throws -> Data {
        let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        let collector = ResponseCollector()

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let resumed = ResumeGate()
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            connection.send(content: request, completion: .contentProcessed { error in
                                if let error, resumed.claim() {
                                    continuation.resume(throwing: HTTPError.transport("\(error)"))
                                }
                            })
                            Self.receive(on: connection, into: collector,
                                         gate: resumed, continuation: continuation)
                        case .failed(let error):
                            if resumed.claim() { continuation.resume(throwing: HTTPError.transport("\(error)")) }
                        case .cancelled:
                            if resumed.claim() { continuation.resume(throwing: HTTPError.transport("cancelled")) }
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw HTTPError.transport("timed out after \(Int(timeout))s")
            }
            defer { group.cancelAll(); connection.cancel() }
            guard let first = try await group.next() else { throw HTTPError.transport("no result") }
            return first
        }
    }

    private static func receive(on connection: NWConnection, into collector: ResponseCollector,
                                gate: ResumeGate, continuation: CheckedContinuation<Data, Error>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { chunk, _, isComplete, error in
            if let error {
                if gate.claim() { continuation.resume(throwing: HTTPError.transport("\(error)")) }
                return
            }
            if let chunk { collector.append(chunk) }
            if isComplete {
                if gate.claim() { continuation.resume(returning: collector.data) }
                return
            }
            receive(on: connection, into: collector, gate: gate, continuation: continuation)
        }
    }
}

/// A continuation may only be resumed once; Network.framework can report a
/// failure and a completion for the same connection.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

private final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    func append(_ chunk: Data) { lock.lock(); buffer.append(chunk); lock.unlock() }
}
