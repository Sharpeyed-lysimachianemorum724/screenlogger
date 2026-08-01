import SQLite3
import XCTest

@testable import ScreenlogCore

final class StoreAXRetentionTests: XCTestCase {
    var tempRoot: URL!
    var store: Store!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenlog-ax-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = try Store(root: tempRoot)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testContentAddressedAXDeduplicatesNodes() throws {
        let xml = "<AccessibilityTree><Node role=\"AXWindow\" name=\"Shared\" /></AccessibilityTree>"
        let snap = AXTreeSnapshot(
            xml: xml,
            nodeCount: 1,
            bundleID: "dev.ax",
            applicationName: "AXApp",
            pid: 42,
            isPartial: false,
            extractionMode: "xml_full"
        )

        let f1 = try store.insertSeedFrame(timestampMs: 1, foreground: "frame1")
        let f2 = try store.insertSeedFrame(timestampMs: 2, foreground: "frame2")
        try store.storeAXSnapshot(frameID: f1, snapshot: snap)
        try store.storeAXSnapshot(frameID: f2, snapshot: snap)

        XCTAssertEqual(try countAXNodes(), 1, "identical payloads share one ax_node")
        XCTAssertEqual(try countAXSnapshots(), 2)

        let hash1 = try store.frame(id: f1)?.axRootHash
        let hash2 = try store.frame(id: f2)?.axRootHash
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1?.count, 32)

        XCTAssertEqual(try store.axTreeXML(frameID: f1), xml)
        XCTAssertEqual(try store.axTreeXML(frameID: f2), xml)
    }

    func testDistinctAXPayloadsCreateDistinctNodes() throws {
        let f1 = try store.insertSeedFrame(timestampMs: 1, foreground: "a")
        let f2 = try store.insertSeedFrame(timestampMs: 2, foreground: "b")
        try store.storeAXSnapshot(
            frameID: f1,
            snapshot: AXTreeSnapshot(xml: "<A/>", nodeCount: 1, pid: 1, isPartial: false)
        )
        try store.storeAXSnapshot(
            frameID: f2,
            snapshot: AXTreeSnapshot(xml: "<B/>", nodeCount: 1, pid: 1, isPartial: false)
        )
        XCTAssertEqual(try countAXNodes(), 2)
        XCTAssertNotEqual(
            try store.frame(id: f1)?.axRootHash,
            try store.frame(id: f2)?.axRootHash
        )
    }

    func testAXSnapshotUpsertAndEdges() throws {
        let frameID = try store.insertSeedFrame(timestampMs: 9, foreground: "edge")
        try store.storeAXSnapshot(
            frameID: frameID,
            snapshot: AXTreeSnapshot(
                xml: "<root/>",
                nodeCount: 1,
                bundleID: "dev.edge",
                applicationName: "Edge",
                pid: 7,
                isPartial: true,
                extractionMode: "partial"
            )
        )
        // Upsert same frame with fuller tree
        try store.storeAXSnapshot(
            frameID: frameID,
            snapshot: AXTreeSnapshot(
                xml: "<root><child/></root>",
                nodeCount: 2,
                bundleID: "dev.edge",
                applicationName: "Edge",
                pid: 7,
                isPartial: false,
                extractionMode: "xml_full"
            )
        )
        XCTAssertEqual(try store.axTreeXML(frameID: frameID), "<root><child/></root>")
        XCTAssertEqual(try countAXSnapshots(), 1)

        let parent = ContentHash.sha256(Data("<parent/>".utf8))
        let child = ContentHash.sha256(Data("<child/>".utf8))
        // Insert nodes so FK-less edge store works (edges don't require nodes, but we still test insert)
        try insertNode(hash: parent, payload: Data("<parent/>".utf8), frameID: frameID)
        try insertNode(hash: child, payload: Data("<child/>".utf8), frameID: frameID)
        try store.storeAXNodeEdge(parentHash: parent, childHash: child)
        try store.storeAXNodeEdge(parentHash: parent, childHash: child)  // idempotent
        XCTAssertEqual(try countAXEdges(), 1)
    }

    func testMissingAXReturnsNil() throws {
        let frameID = try store.insertSeedFrame(timestampMs: 1, foreground: "no-ax")
        XCTAssertNil(try store.axTreeXML(frameID: frameID))
        XCTAssertNil(try store.axTreeXML(frameID: 999_999))
    }

    // MARK: - Helpers

    private func countAXNodes() throws -> Int {
        try scalarCount("SELECT COUNT(*) FROM ax_node")
    }

    private func countAXSnapshots() throws -> Int {
        try scalarCount("SELECT COUNT(*) FROM ax_snapshot")
    }

    private func countAXEdges() throws -> Int {
        try scalarCount("SELECT COUNT(*) FROM ax_node_edge")
    }

    private func scalarCount(_ sql: String) throws -> Int {
        let stmt = try store.db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(SQLiteColumn.int64(stmt, 0))
    }

    private func insertNode(hash: Data, payload: Data, frameID: Int64) throws {
        let stmt = try store.db.prepare(
            "INSERT OR IGNORE INTO ax_node(hash, payload, first_seen_frame_id) VALUES(?, ?, ?)"
        )
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.blob(stmt, 1, hash)
        SQLiteBind.blob(stmt, 2, payload)
        SQLiteBind.int64(stmt, 3, frameID)
        _ = sqlite3_step(stmt)
    }
}
