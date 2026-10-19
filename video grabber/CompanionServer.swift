//
//  CompanionServer.swift
//  My Videos
//
//  A small HTTP server so the iPhone web app can use My Videos over the home network.
//  Static app files are public; every /api call needs the token issued at pairing.
//

import Foundation
import Network
import Observation
import SystemConfiguration

// MARK: - HTTP primitives

nonisolated struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    /// Parses a complete request, or returns nil if more bytes are needed.
    static func parse(_ data: Data) -> (HTTPRequest, Int)? {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return nil }
        let body = data[bodyStart..<(bodyStart + length)]

        let target = String(requestLine[1])
        let components = URLComponents(string: "http://x" + target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let request = HTTPRequest(method: String(requestLine[0]), path: components?.percentEncodedPath.removingPercentEncoding ?? "/",
                                  query: query, headers: headers, body: Data(body))
        return (request, bodyStart - data.startIndex + length)
    }

    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }
}

nonisolated struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String] = [:]
    var body: Data = Data()
    /// Streamed instead of `body` (large media files).
    var file: (url: URL, range: ClosedRange<Int64>)?

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8",
                                                      "Cache-Control": "no-store"], body: data)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        .json(["error": message], status: status)
    }

    static func html(_ text: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"],
                     body: Data(text.utf8))
    }

    var reason: String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 416: return "Range Not Satisfiable"
        case 429: return "Too Many Requests"
        default: return "Error"
        }
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/manifest+json"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "opus", "ogg": return "audio/ogg"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Server

/// Accepts connections from the local network and hands requests to a handler on the main actor.
@Observable
final class CompanionServer {
    static let shared = CompanionServer()
    static let preferredPort: UInt16 = 8765

    private(set) var isRunning = false
    private(set) var port: UInt16 = 0
    private(set) var lastError: String?
    /// When a paired device last talked to the Mac.
    private(set) var lastSeen: Date?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "MyVideos.companion")

    var handler: ((HTTPRequest) async -> HTTPResponse)?

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.preferredPort)!)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.update(state, listener: listener) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func update(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            isRunning = true
            port = listener.port?.rawValue ?? Self.preferredPort
            lastError = nil
        case .failed(let error):
            isRunning = false
            lastError = error.localizedDescription
            self.listener = nil
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    func noteSeen() { lastSeen = Date() }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > 2_000_000 || error != nil {
                connection.cancel()
                return
            }
            if let (request, _) = HTTPRequest.parse(buffer) {
                Task { @MainActor in
                    let response = await self.handler?(request) ?? .error(503, "Not ready")
                    self.send(response, method: request.method, on: connection)
                }
            } else if isComplete {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private nonisolated func send(_ response: HTTPResponse, method: String, on connection: NWConnection) {
        var headers = response.headers
        headers["Connection"] = "close"
        headers["Access-Control-Allow-Origin"] = "*"
        headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
        headers["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
        let length: Int64
        if let file = response.file {
            length = file.range.upperBound - file.range.lowerBound + 1
        } else {
            length = Int64(response.body.count)
        }
        headers["Content-Length"] = String(length)

        var head = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
        for (key, value) in headers { head += "\(key): \(value)\r\n" }
        head += "\r\n"

        let isHead = method == "HEAD"
        if let file = response.file, !isHead {
            connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
                guard error == nil, let handle = try? FileHandle(forReadingFrom: file.url) else {
                    connection.cancel()
                    return
                }
                try? handle.seek(toOffset: UInt64(file.range.lowerBound))
                self?.stream(handle, remaining: length, on: connection)
            })
        } else {
            let payload = isHead ? Data(head.utf8) : Data(head.utf8) + response.body
            connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Sends a file in 512 KB chunks so even large videos stream with little memory.
    private nonisolated func stream(_ handle: FileHandle, remaining: Int64, on connection: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            connection.cancel()
            return
        }
        let chunk = (try? handle.read(upToCount: Int(min(remaining, 512 * 1024)))) ?? Data()
        guard !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self?.stream(handle, remaining: remaining - Int64(chunk.count), on: connection)
        })
    }

    // MARK: Addresses

    /// "Justins-MacBook-Pro.local" — stays the same when the Mac's IP address changes.
    static var bonjourHost: String? {
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String? else { return nil }
        return name + ".local"
    }

    /// The Mac's current IPv4 address on Wi-Fi or Ethernet.
    static var ipAddress: String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var candidates: [(String, String)] = []
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(item.pointee.ifa_flags)
            guard let addr = item.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                candidates.append((name, String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)))
            }
        }
        return candidates.sorted { $0.0 < $1.0 }.first?.1
    }
}
