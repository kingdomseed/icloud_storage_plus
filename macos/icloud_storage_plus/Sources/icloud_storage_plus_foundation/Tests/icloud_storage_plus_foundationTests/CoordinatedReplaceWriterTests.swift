import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class CoordinatedReplaceWriterTests: XCTestCase {
    func testCopyDestinationReadyStateErrorAllowsCurrentItems() {
        let error = CoordinatedReplaceWriter.copyDestinationReadyStateError(
            isUbiquitousItem: true,
            downloadStatus: .current
        )

        XCTAssertNil(error)
    }

    func testCopyDestinationReadyStateErrorRejectsNotDownloadedItems() {
        let error = CoordinatedReplaceWriter.copyDestinationReadyStateError(
            isUbiquitousItem: true,
            downloadStatus: .notDownloaded
        ) as NSError?

        XCTAssertEqual(
            error?.code,
            CoordinatedReplaceWriter.itemNotDownloadedReplaceStateCode
        )
        XCTAssertEqual(
            error?.localizedDescription,
            "Cannot replace a nonlocal iCloud item until it is fully downloaded."
        )
    }

    func testLiveWriterReplacesExistingLocalFile() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let destinationURL = temporaryDirectory.appendingPathComponent("file.json")
        try Data("old".utf8).write(to: destinationURL)

        let handled = try await CoordinatedReplaceWriter.live.overwriteExistingItem(
            at: destinationURL
        ) { replacementURL in
            try Data("new".utf8).write(to: replacementURL)
        }

        XCTAssertTrue(handled)
        XCTAssertEqual(try String(contentsOf: destinationURL), "new")
    }

    func testLiveWriterRejectsExistingDirectoryDestination() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let destinationURL = temporaryDirectory.appendingPathComponent(
            "folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        do {
            _ = try await CoordinatedReplaceWriter.live.overwriteExistingItem(
                at: destinationURL
            ) { replacementURL in
                try Data("new".utf8).write(to: replacementURL)
            }
            XCTFail("expected overwrite to throw")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an existing directory with file content."
            )
        }
    }

    func testOverwriteExistingItemThrowsWhenDestinationHasUnresolvedConflicts() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in
                throw NSError(
                    domain: "ICloudStoragePlusErrorDomain",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cannot replace an iCloud item with unresolved conflict versions.",
                    ]
                )
            },
            createReplacementDirectory: { _ in
                XCTFail("should not create replacement directory")
                return URL(fileURLWithPath: "/tmp/replacement")
            },
            coordinateReplace: { _, _ in
                XCTFail("should not coordinate replace")
            },
            cleanupConflicts: { _ in },
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        do {
            _ = try await writer.overwriteExistingItem(at: destinationURL) { _ in
                preparedReplacement = true
            }
            XCTFail("expected overwrite to throw")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an iCloud item with unresolved conflict versions."
            )
        }

        XCTAssertFalse(preparedReplacement)
    }

    func testOverwriteExistingItemThrowsWhenDestinationIsNotFullyLocal() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in
                throw NSError(
                    domain: "ICloudStoragePlusErrorDomain",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cannot replace a nonlocal iCloud item until it is fully downloaded.",
                    ]
                )
            },
            createReplacementDirectory: { _ in
                XCTFail("should not create replacement directory")
                return URL(fileURLWithPath: "/tmp/replacement")
            },
            coordinateReplace: { _, _ in
                XCTFail("should not coordinate replace")
            },
            cleanupConflicts: { _ in },
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        do {
            _ = try await writer.overwriteExistingItem(at: destinationURL) { _ in
                preparedReplacement = true
            }
            XCTFail("expected overwrite to throw")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace a nonlocal iCloud item until it is fully downloaded."
            )
        }

        XCTAssertFalse(preparedReplacement)
    }

    func testCopyDestinationReadyStateErrorRejectsDownloadedButNotCurrentItems() {
        let error = CoordinatedReplaceWriter.copyDestinationReadyStateError(
            isUbiquitousItem: true,
            downloadStatus: .downloaded
        ) as NSError?

        XCTAssertEqual(error?.domain, "ICloudStoragePlusErrorDomain")
        XCTAssertEqual(error?.code, 2)
        XCTAssertEqual(
            error?.localizedDescription,
            "Cannot replace a nonlocal iCloud item until it is fully downloaded."
        )
    }

    func testOverwriteExistingItemReturnsFalseWhenDestinationDoesNotExist() async throws {
        var preparedReplacement = false
        var verifiedDestinationState = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in false },
            ensureDownloaded: { _ in
                XCTFail("should not ensure download")
            },
            verifyDestination: { _ in
                verifiedDestinationState = true
            },
            createReplacementDirectory: { _ in
                XCTFail("should not create replacement directory")
                return URL(fileURLWithPath: "/tmp")
            },
            coordinateReplace: { _, _ in
                XCTFail("should not coordinate replace")
            },
            cleanupConflicts: { _ in },
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        let handled = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in
            preparedReplacement = true
        }

        XCTAssertFalse(handled)
        XCTAssertFalse(preparedReplacement)
        XCTAssertFalse(verifiedDestinationState)
    }

    func testOverwriteExistingItemCleansUpReplacementArtifactWhenReplaceFails() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let expectedError = NSError(domain: NSCocoaErrorDomain, code: 512)
        var cleanedURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in replacementDirectory },
            coordinateReplace: { url, accessor in try accessor(url) },
            cleanupConflicts: { _ in },
            replaceItem: { _, _ in throw expectedError },
            removeItem: { cleanedURL = $0 }
        )

        do {
            _ = try await writer.overwriteExistingItem(at: destinationURL) { url in
                XCTAssertEqual(
                    url.deletingLastPathComponent().path,
                    replacementDirectory.path
                )
            }
            XCTFail("expected overwrite to throw")
        } catch {
            XCTAssertEqual((error as NSError).code, expectedError.code)
        }

        XCTAssertNotNil(cleanedURL)
    }

    func testOverwriteExistingItemReplacesBeforeConflictCleanup() async throws {
        var events: [String] = []

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in
                URL(fileURLWithPath: "/tmp/replacement")
            },
            coordinateReplace: { _, accessor in
                try accessor(URL(fileURLWithPath: "/tmp/file.json"))
            },
            cleanupConflicts: { _ in events.append("cleanupConflicts") },
            replaceItem: { _, _ in events.append("replaceItem") },
            removeItem: { _ in }
        )

        _ = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertEqual(events, ["replaceItem", "cleanupConflicts"])
    }

    func testOverwriteExistingItemMapsCleanupFailureToConflictError() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let underlyingError = NSError(domain: NSCocoaErrorDomain, code: 512)
        var cleanedURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in replacementDirectory },
            coordinateReplace: { url, accessor in try accessor(url) },
            cleanupConflicts: { _ in throw underlyingError },
            replaceItem: { _, _ in },
            removeItem: { cleanedURL = $0 }
        )

        do {
            _ = try await writer.overwriteExistingItem(at: destinationURL) { _ in }
            XCTFail("expected overwrite to throw")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(
                nsError.domain,
                CoordinatedReplaceWriter.replaceStateErrorDomain
            )
            XCTAssertEqual(
                nsError.code,
                CoordinatedReplaceWriter.conflictReplaceStateCode
            )
            XCTAssertEqual(
                nsError.localizedDescription,
                "Cannot replace an iCloud item: auto-resolution failed."
            )
            XCTAssertEqual(
                (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code,
                underlyingError.code
            )
        }

        XCTAssertEqual(cleanedURL, replacementDirectory)
    }

    func testOverwriteExistingItemEnsuresDownloadBeforeValidation() async throws {
        var events: [String] = []

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in events.append("ensureDownloaded") },
            verifyDestination: { _ in events.append("verifyDestination") },
            createReplacementDirectory: { _ in
                URL(fileURLWithPath: "/tmp/replacement")
            },
            coordinateReplace: { _, accessor in
                try accessor(URL(fileURLWithPath: "/tmp/file.json"))
            },
            cleanupConflicts: { _ in },
            replaceItem: { _, _ in },
            removeItem: { _ in }
        )

        _ = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertEqual(events, ["ensureDownloaded", "verifyDestination"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        return temporaryDirectory
    }
}
