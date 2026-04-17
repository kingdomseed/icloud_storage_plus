import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class DownloadWaiterTests: XCTestCase {
    func testInteractiveWriteScheduleHasShorterBudgetThanBackgroundRead() {
        let writeBudget = DownloadSchedule.interactiveWrite.idleTimeouts
            .reduce(0, +)
        let readBudget = DownloadSchedule.backgroundRead.idleTimeouts
            .reduce(0, +)

        XCTAssertLessThan(
            writeBudget,
            readBudget,
            "writes must not block minutes on a stalled download; read "
                + "path tolerates longer waits."
        )
    }

    func testInteractiveWriteScheduleMatchesSpec() {
        XCTAssertEqual(
            DownloadSchedule.interactiveWrite.idleTimeouts,
            [10, 20]
        )
        XCTAssertEqual(
            DownloadSchedule.interactiveWrite.retryBackoff,
            [2]
        )
    }

    func testBackgroundReadScheduleMatchesLegacyReadDefault() {
        XCTAssertEqual(
            DownloadSchedule.backgroundRead.idleTimeouts,
            [60, 90, 180]
        )
        XCTAssertEqual(
            DownloadSchedule.backgroundRead.retryBackoff,
            [2, 4]
        )
    }

    func testTimeoutErrorHasStableDomainAndDescription() {
        let error = iCloudDownloadTimeoutError()

        XCTAssertEqual(error.domain, "ICloudStorageTimeout")
        XCTAssertEqual(error.code, 1)
        XCTAssertEqual(
            error.localizedDescription,
            "Download idle timeout"
        )
    }

    func testMetadataQuerySearchScopesCoverDataAndDocuments() {
        XCTAssertEqual(
            iCloudMetadataQuerySearchScopes,
            [
                NSMetadataQueryUbiquitousDataScope,
                NSMetadataQueryUbiquitousDocumentsScope,
            ]
        )
    }

    func testCompletionGateAllowsExactlyOneTryComplete() {
        let gate = CompletionGate()

        XCTAssertFalse(gate.isCompleted)
        XCTAssertTrue(gate.tryComplete())
        XCTAssertTrue(gate.isCompleted)
        XCTAssertFalse(gate.tryComplete())
    }

    func testEvaluateDownloadStatusReturnsPendingForNonUbiquitousFile()
        throws
    {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("file.json")
        try Data("payload".utf8).write(to: fileURL)

        let query = NSMetadataQuery()
        query.searchScopes = iCloudMetadataQuerySearchScopes

        let result = evaluateICloudDownloadStatus(
            query: query,
            fileURL: fileURL
        )

        XCTAssertFalse(result.completed)
        XCTAssertNil(result.error)
    }

    func testWaitForDownloadCompletionTimesOutOnNonUbiquitousPath() async {
        let fileURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).json")

        do {
            try await waitForDownloadCompletion(
                at: fileURL,
                idleTimeouts: [0.05],
                retryBackoff: []
            )
            XCTFail("expected timeout error")
        } catch {
            XCTAssertEqual(
                (error as NSError).domain,
                "ICloudStorageTimeout",
                "non-ubiquitous path with tight budget should exhaust the "
                    + "watchdog and surface the idle timeout."
            )
        }
    }

    func testWaitForDownloadCompletionWalksRetrySchedule() async {
        let fileURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).json")

        let start = Date()
        do {
            try await waitForDownloadCompletion(
                at: fileURL,
                idleTimeouts: [0.05, 0.05],
                retryBackoff: [0.05]
            )
            XCTFail("expected timeout error")
        } catch {
            XCTAssertEqual(
                (error as NSError).domain,
                "ICloudStorageTimeout"
            )
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(
            elapsed,
            0.1,
            "two attempts (~0.05s each) + one backoff (~0.05s) must elapse "
                + "before the timeout surfaces."
        )
    }
}
