import Foundation
import XCTest

@testable import ScreenlogCore

final class IPCRequestValidationTests: XCTestCase {
    func testResultLimitsRejectZeroNegativeAndExcessiveValues() throws {
        for limit in [-1, 0, 501, Int.max] {
            XCTAssertThrowsError(try IPCRequest(cmd: .fts, query: "invoice", limit: limit).validate())
            XCTAssertThrowsError(try IPCRequest(cmd: .sample, limit: limit).validate())
            XCTAssertThrowsError(try IPCRequest(cmd: .topApplications, limit: limit).validate())
        }

        XCTAssertNoThrow(try IPCRequest(cmd: .fts, query: "invoice", limit: 1).validate())
        XCTAssertNoThrow(try IPCRequest(cmd: .fts, query: "invoice", limit: 500).validate())
    }

    func testTextAndPathPayloadsAreBoundedByUTF8Bytes() throws {
        XCTAssertNoThrow(try IPCRequest(cmd: .fts, query: String(repeating: "a", count: 4_096)).validate())
        XCTAssertThrowsError(try IPCRequest(cmd: .fts, query: String(repeating: "a", count: 4_097)).validate())
        XCTAssertThrowsError(
            try IPCRequest(
                cmd: .extractImage,
                frameID: 1,
                outPath: String(repeating: "\u{E9}", count: 2_049)
            ).validate()
        )
    }

    func testFrameCommandsRequirePositiveIdentifiers() throws {
        for command in [IPCCommand.frame, .ocrBoxes, .axTree] {
            XCTAssertThrowsError(try IPCRequest(cmd: command).validate())
            XCTAssertThrowsError(try IPCRequest(cmd: command, frameID: 0).validate())
            XCTAssertThrowsError(try IPCRequest(cmd: command, frameID: -1).validate())
            XCTAssertNoThrow(try IPCRequest(cmd: command, frameID: 1).validate())
        }

        XCTAssertThrowsError(try IPCRequest(cmd: .extractImage).validate())
        XCTAssertNoThrow(try IPCRequest(cmd: .extractImage, timestampMs: 0).validate())
    }

    func testSessionAndSampleBoundsAreEnforced() throws {
        XCTAssertThrowsError(try IPCRequest(cmd: .sessions, gapMinutes: 0).validate())
        XCTAssertThrowsError(try IPCRequest(cmd: .sessions, gapMinutes: 10_081).validate())
        XCTAssertNoThrow(try IPCRequest(cmd: .sessions, gapMinutes: 10_080).validate())

        XCTAssertThrowsError(try IPCRequest(cmd: .sample, minSegLen: 0).validate())
        XCTAssertThrowsError(try IPCRequest(cmd: .sample, minSegLen: 10_001).validate())
        XCTAssertNoThrow(try IPCRequest(cmd: .sample, minSegLen: 10_000).validate())
    }

    func testProtocolRangeMustBeOrderedAndPositive() throws {
        XCTAssertThrowsError(try IPCRequest(cmd: .ping, protocolMinimumVersion: 0, protocolMaximumVersion: 1).validate())
        XCTAssertThrowsError(try IPCRequest(cmd: .ping, protocolMinimumVersion: 2, protocolMaximumVersion: 1).validate())
        XCTAssertNoThrow(try IPCRequest(cmd: .ping, protocolMinimumVersion: 1, protocolMaximumVersion: 2).validate())
    }

    func testUnknownOpcodeDecodesToSafeUnsupportedCommand() throws {
        let payload = Data(#"{"id":"test","cmd":"seed"}"#.utf8)
        let request = try JSONDecoder().decode(IPCRequest.self, from: payload)
        XCTAssertEqual(request.cmd, .unsupported)
    }
}
