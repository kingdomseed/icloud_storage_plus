import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class CoordinatedReplaceWriterTests: XCTestCase {
    func testHelperSourceMatchesProductionSource() throws {
        let helperSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Tests/icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/CoordinatedReplaceWriter.swift"
                ),
            encoding: .utf8
        )
        let productionSource = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(
                    of: "/Sources/icloud_storage_plus_foundation/Tests/"
                        + "icloud_storage_plus_foundationTests/"
                        + "CoordinatedReplaceWriterTests.swift",
                    with: "/Sources/icloud_storage_plus/"
                        + "CoordinatedReplaceWriter.swift"
                ),
            encoding: .utf8
        )

        XCTAssertEqual(helperSource, productionSource)
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
