//
//  CompanionTests.swift
//  My Videos Tests
//

import Foundation
import Testing
@testable import My_Videos

@Suite("iPhone companion server")
struct CompanionTests {
    @Test func parsesRequestsWithQueryAndBody() throws {
        let raw = "POST /api/download?x=1&url=https%3A%2F%2Fa.b%2Fc%3Fd%3D1 HTTP/1.1\r\nHost: mac.local\r\nAuthorization: Bearer abc\r\nContent-Length: 13\r\n\r\n{\"format\":1}x"
        let (request, consumed) = try #require(HTTPRequest.parse(Data(raw.utf8)))
        #expect(request.method == "POST")
        #expect(request.path == "/api/download")
        #expect(request.query["url"] == "https://a.b/c?d=1")
        #expect(request.headers["authorization"] == "Bearer abc")
        #expect(request.body.count == 13)
        #expect(consumed == raw.utf8.count)
    }

    @Test func waitsForTheWholeBody() {
        let partial = "POST /api/pair HTTP/1.1\r\nContent-Length: 20\r\n\r\n{\"code\""
        #expect(HTTPRequest.parse(Data(partial.utf8)) == nil)
        #expect(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)) == nil)
    }

    @Test func mediaTypesFitIOSPlayback() {
        #expect(HTTPResponse.mimeType(for: "mp4") == "video/mp4")
        #expect(HTTPResponse.mimeType(for: "M4A") == "audio/mp4")
        #expect(HTTPResponse.mimeType(for: "mp3") == "audio/mpeg")
        #expect(HTTPResponse.mimeType(for: "xyz") == "application/octet-stream")
    }

    @MainActor @Test func pairingAcceptsOnlyTheRightCodeAndToken() {
        let pairing = CompanionPairing.shared
        let code = pairing.code
        if case .paired(let token) = pairing.pair(with: String(code.prefix(3)) + " " + code.suffix(3)) {
            #expect(pairing.isValid(token))
        } else {
            Issue.record("Correct code with a space should pair")
        }
        #expect(!pairing.isValid(nil))
        #expect(!pairing.isValid("wrong"))
        #expect(!pairing.isValid(String(pairing.token.dropLast()) + "x"))
    }
}
