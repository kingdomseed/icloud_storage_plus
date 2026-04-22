import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

private final class FakeVersion {
    let id: Int
    let modificationDate: Date?
    var isResolved: Bool = false

    init(id: Int, modificationDate: Date?) {
        self.id = id
        self.modificationDate = modificationDate
    }
}

final class ConflictResolverTests: XCTestCase {
    private let targetURL = URL(fileURLWithPath: "/tmp/file.json")

    func testReturnsEarlyWhenNoUnresolvedConflicts() throws {
        var replaceCount = 0
        var removeOtherCount = 0

        try resolveUnresolvedConflicts(
            at: targetURL,
            unresolvedVersions: { _ in nil },
            modificationDate: { (_: FakeVersion) in nil },
            replaceItem: { _, _ in replaceCount += 1 },
            markResolved: { _ in },
            removeOtherVersions: { _ in removeOtherCount += 1 }
        )

        XCTAssertEqual(replaceCount, 0)
        XCTAssertEqual(removeOtherCount, 0)
    }

    func testReturnsEarlyWhenConflictsArrayIsEmpty() throws {
        var replaceCount = 0
        var removeOtherCount = 0

        try resolveUnresolvedConflicts(
            at: targetURL,
            unresolvedVersions: { _ in [] as [FakeVersion] },
            modificationDate: { $0.modificationDate },
            replaceItem: { _, _ in replaceCount += 1 },
            markResolved: { _ in },
            removeOtherVersions: { _ in removeOtherCount += 1 }
        )

        XCTAssertEqual(replaceCount, 0)
        XCTAssertEqual(removeOtherCount, 0)
    }

    func testReplacesWithMostRecentVersionAndMarksAllResolved() throws {
        let older = FakeVersion(
            id: 1,
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let newer = FakeVersion(
            id: 2,
            modificationDate: Date(timeIntervalSince1970: 200)
        )
        let versions = [older, newer]
        var callOrder: [String] = []
        var replacedWith: FakeVersion?

        try resolveUnresolvedConflicts(
            at: targetURL,
            unresolvedVersions: { _ in versions },
            modificationDate: { $0.modificationDate },
            replaceItem: { version, targetURL in
                XCTAssertEqual(targetURL, self.targetURL)
                replacedWith = version
                callOrder.append("replace")
            },
            markResolved: { version in
                version.isResolved = true
                callOrder.append("mark-\(version.id)")
            },
            removeOtherVersions: { url in
                XCTAssertEqual(url, self.targetURL)
                callOrder.append("removeOther")
            }
        )

        XCTAssertEqual(replacedWith?.id, newer.id)
        XCTAssertTrue(older.isResolved)
        XCTAssertTrue(newer.isResolved)
        XCTAssertEqual(
            callOrder.prefix(1),
            ["replace"],
            "replaceItem must run before mark-resolved"
        )
        XCTAssertEqual(
            callOrder.last,
            "removeOther",
            "removeOtherVersions must run last"
        )
    }

    func testUsesDistantPastWhenModificationDateIsNil() throws {
        let dated = FakeVersion(
            id: 1,
            modificationDate: Date(timeIntervalSince1970: 50)
        )
        let undated = FakeVersion(id: 2, modificationDate: nil)
        let versions = [undated, dated]
        var replacedWith: FakeVersion?

        try resolveUnresolvedConflicts(
            at: targetURL,
            unresolvedVersions: { _ in versions },
            modificationDate: { $0.modificationDate },
            replaceItem: { version, _ in replacedWith = version },
            markResolved: { _ in },
            removeOtherVersions: { _ in }
        )

        XCTAssertEqual(
            replacedWith?.id,
            dated.id,
            "dated version should sort ahead of undated versions"
        )
    }

    func testPropagatesReplaceItemFailureBeforeMarkingResolved() {
        let version = FakeVersion(
            id: 1,
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let expectedError = NSError(
            domain: "TestDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "replace failed"]
        )
        var markedResolved = false
        var removedOthers = false

        XCTAssertThrowsError(
            try resolveUnresolvedConflicts(
                at: targetURL,
                unresolvedVersions: { _ in [version] },
                modificationDate: { $0.modificationDate },
                replaceItem: { _, _ in throw expectedError },
                markResolved: { _ in markedResolved = true },
                removeOtherVersions: { _ in removedOthers = true }
            )
        ) { error in
            XCTAssertEqual((error as NSError).code, 42)
        }

        XCTAssertFalse(markedResolved)
        XCTAssertFalse(removedOthers)
    }

    func testPropagatesRemoveOtherVersionsFailure() {
        let version = FakeVersion(
            id: 1,
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let expectedError = NSError(
            domain: "TestDomain",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "remove failed"]
        )

        XCTAssertThrowsError(
            try resolveUnresolvedConflicts(
                at: targetURL,
                unresolvedVersions: { _ in [version] },
                modificationDate: { $0.modificationDate },
                replaceItem: { _, _ in },
                markResolved: { $0.isResolved = true },
                removeOtherVersions: { _ in throw expectedError }
            )
        ) { error in
            XCTAssertEqual((error as NSError).code, 7)
        }

        XCTAssertTrue(
            version.isResolved,
            "markResolved must run before removeOtherVersions so the "
                + "next write still sees the conflict as resolved."
        )
    }

    func testRealAsyncWrapperIsNoOpOnFileWithNoConflicts() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("file.json")
        try Data("payload".utf8).write(to: fileURL)

        try await resolveUnresolvedConflicts(at: fileURL)

        XCTAssertEqual(try String(contentsOf: fileURL), "payload")
    }
}
