import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class CoordinatedReplaceWriterTests: XCTestCase {
    func testProductionSourceIsNotDuplicated() throws {
        let productionPath = #filePath
            .replacingOccurrences(
                of: "/Sources/icloud_storage_plus_foundation/Tests/"
                    + "icloud_storage_plus_foundationTests/"
                    + "CoordinatedReplaceWriterTests.swift",
                with: "/Sources/icloud_storage_plus/"
                    + "CoordinatedReplaceWriter.swift"
            )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: productionPath),
            "CoordinatedReplaceWriter.swift must live only in the "
                + "icloud_storage_plus_foundation module; the plugin target "
                + "references it via SPM target.sources sharing."
        )
    }

    func testHelperSourceDoesNotExposeCopyOverwriteEntryPoint() throws {
        let helperSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Tests/icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/CoordinatedReplaceWriter.swift"
                ),
            encoding: .utf8
        )

        XCTAssertFalse(helperSource.contains("copyItemOverwritingExistingItem"))
    }

    func testHelperSourceDoesNotKeepRedundantNonCurrentGuard() throws {
        let helperSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Tests/icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/CoordinatedReplaceWriter.swift"
                ),
            encoding: .utf8
        )

        XCTAssertFalse(
            helperSource.contains("if downloadStatus != .current"),
            "replaceReadyStateError should not keep a non-current guard after "
                + "the earlier .current return."
        )
    }

    func testMacOSCopyPropagatesSourceReadCoordinationErrors() throws {
        let pluginSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Sources/icloud_storage_plus_foundation/Tests/"
                        + "icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/Sources/icloud_storage_plus/"
                        + "macOSICloudStoragePlugin.swift"
                ),
            encoding: .utf8
        )

        XCTAssertTrue(
            pluginSource.contains("var sourceCoordinationError: NSError?"),
            "copy() should capture read coordination failures before "
                + "falling through to destination handling."
        )
        XCTAssertTrue(
            pluginSource.contains("error: &sourceCoordinationError"),
            "copy() should pass a read coordination error pointer instead "
                + "of discarding coordination failures."
        )
        XCTAssertTrue(
            pluginSource.contains("if let sourceCoordinationError"),
            "copy() should surface a failed source read coordination "
                + "instead of continuing silently."
        )
        XCTAssertTrue(
            pluginSource.contains("var copyCoordinationError: NSError?"),
            "copy() should also capture read/write coordination failures in "
                + "the non-overwrite path."
        )
        XCTAssertTrue(
            pluginSource.contains("error: &copyCoordinationError"),
            "copy() should not discard the combined read/write "
                + "coordination error."
        )
        XCTAssertTrue(
            pluginSource.contains("if let copyCoordinationError"),
            "copy() should surface a failed combined coordination instead "
                + "of leaving the Flutter call without a result."
        )
    }

    func testMacOSCopyFailuresReportDestinationRelativePath() throws {
        let pluginSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Sources/icloud_storage_plus_foundation/Tests/"
                        + "icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/Sources/icloud_storage_plus/"
                        + "macOSICloudStoragePlugin.swift"
                ),
            encoding: .utf8
        )

        XCTAssertEqual(
            pluginSource.components(
                separatedBy: "relativePath: toRelativePath"
            ).count - 1,
            3,
            "copy() should surface the blocked destination path for both "
                + "destination-side failure branches, including coordination "
                + "errors in the combined read/write path."
        )
    }

    func testMacOSUploadProgressFailuresReportCloudRelativePath() throws {
        let pluginSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Sources/icloud_storage_plus_foundation/Tests/"
                        + "icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/Sources/icloud_storage_plus/"
                        + "macOSICloudStoragePlugin.swift"
                ),
            encoding: .utf8
        )

        XCTAssertTrue(
            pluginSource.contains(
                "streamHandler.setEvent(nativeCodeError(\n"
                    + "        error,\n"
                    + "        operation: \"uploadFile\",\n"
                    + "        relativePath: cloudRelativePath\n"
                    + "      ))"
            ),
            "upload progress failures should surface cloudRelativePath in "
                + "the structured error payload."
        )
    }

    func testLiveWriterReplacesExistingLocalFile() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let destinationURL = temporaryDirectory.appendingPathComponent("file.json")
        try Data("old".utf8).write(to: destinationURL)

        let handled = try CoordinatedReplaceWriter.live.overwriteExistingItem(
            at: destinationURL
        ) { replacementURL in
            try Data("new".utf8).write(to: replacementURL)
        }

        XCTAssertTrue(handled)
        XCTAssertEqual(try String(contentsOf: destinationURL), "new")
    }

    func testLiveWriterRejectsExistingDirectoryDestination() throws {
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

        XCTAssertThrowsError(
            try CoordinatedReplaceWriter.live.overwriteExistingItem(
                at: destinationURL
            ) { replacementURL in
                try Data("new".utf8).write(to: replacementURL)
            }
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an existing directory with file content."
            )
        }
    }

    func testOverwriteExistingItemThrowsWhenDestinationHasUnresolvedConflicts() {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
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
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        XCTAssertThrowsError(
            try writer.overwriteExistingItem(at: destinationURL) { _ in
                preparedReplacement = true
            }
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace an iCloud item with unresolved conflict versions."
            )
        }

        XCTAssertFalse(preparedReplacement)
    }

    func testOverwriteExistingItemThrowsWhenDestinationIsNotFullyLocal() {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
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
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        XCTAssertThrowsError(
            try writer.overwriteExistingItem(at: destinationURL) { _ in
                preparedReplacement = true
            }
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Cannot replace a nonlocal iCloud item until it is fully downloaded."
            )
        }

        XCTAssertFalse(preparedReplacement)
    }

    func testReplaceReadyStateErrorReturnsDistinctDownloadInProgressCode() {
        let error = CoordinatedReplaceWriter.replaceReadyStateError(
            hasConflicts: false,
            isUbiquitousItem: true,
            downloadStatus: URLUbiquitousItemDownloadingStatus.downloaded,
            isDownloading: true
        ) as NSError?

        XCTAssertEqual(error?.domain, "ICloudStoragePlusErrorDomain")
        XCTAssertEqual(error?.code, 3)
        XCTAssertEqual(
            error?.localizedDescription,
            "Cannot replace an iCloud item while it is downloading."
        )
    }

    func testReplaceReadyStateErrorRejectsDownloadedButNotCurrentItems() {
        let error = CoordinatedReplaceWriter.replaceReadyStateError(
            hasConflicts: false,
            isUbiquitousItem: true,
            downloadStatus: URLUbiquitousItemDownloadingStatus.downloaded,
            isDownloading: false
        ) as NSError?

        XCTAssertEqual(error?.domain, "ICloudStoragePlusErrorDomain")
        XCTAssertEqual(error?.code, 2)
        XCTAssertEqual(
            error?.localizedDescription,
            "Cannot replace a nonlocal iCloud item until it is fully downloaded."
        )
    }

    func testOverwriteExistingItemReturnsFalseWhenDestinationDoesNotExist() throws {
        var preparedReplacement = false
        var verifiedDestinationState = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in false },
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
            replaceItem: { _, _ in
                XCTFail("should not replace item")
            },
            removeItem: { _ in }
        )

        let handled = try writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in
            preparedReplacement = true
        }

        XCTAssertFalse(handled)
        XCTAssertFalse(preparedReplacement)
        XCTAssertFalse(verifiedDestinationState)
    }

    func testOverwriteExistingItemCleansUpReplacementArtifactWhenReplaceFails() {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let expectedError = NSError(domain: NSCocoaErrorDomain, code: 512)
        var cleanedURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in replacementDirectory },
            coordinateReplace: { url, accessor in try accessor(url) },
            replaceItem: { _, _ in throw expectedError },
            removeItem: { cleanedURL = $0 }
        )

        XCTAssertThrowsError(
            try writer.overwriteExistingItem(at: destinationURL) { url in
                XCTAssertEqual(
                    url.deletingLastPathComponent().path,
                    replacementDirectory.path
                )
            }
        ) { error in
            XCTAssertEqual((error as NSError).code, expectedError.code)
        }

        XCTAssertNotNil(cleanedURL)
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
