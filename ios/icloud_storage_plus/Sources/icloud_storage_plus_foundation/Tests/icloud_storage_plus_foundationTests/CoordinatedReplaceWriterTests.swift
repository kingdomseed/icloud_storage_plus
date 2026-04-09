import Foundation
import XCTest
@testable import icloud_storage_plus_foundation

final class CoordinatedReplaceWriterTests: XCTestCase {
    func testCopyItemOverwritingExistingItemCopiesIntoReplacementURL() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.json")
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let replacementURL = replacementDirectory
            .appendingPathComponent(destinationURL.lastPathComponent)
        var copiedSourceURL: URL?
        var copiedReplacementURL: URL?
        var replacedDestinationURL: URL?
        var replacedItemURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            createReplacementDirectory: { _ in replacementDirectory },
            coordinateReplace: { url, accessor in try accessor(url) },
            replaceItem: { destinationURL, replacementURL in
                replacedDestinationURL = destinationURL
                replacedItemURL = replacementURL
            },
            removeItem: { _ in }
        )

        let handled = try writer.copyItemOverwritingExistingItem(
            from: sourceURL,
            to: destinationURL
        ) { sourceURL, replacementURL in
            copiedSourceURL = sourceURL
            copiedReplacementURL = replacementURL
        }

        XCTAssertTrue(handled)
        XCTAssertEqual(copiedSourceURL, sourceURL)
        XCTAssertEqual(copiedReplacementURL, replacementURL)
        XCTAssertEqual(replacedDestinationURL, destinationURL)
        XCTAssertEqual(replacedItemURL, replacementURL)
    }

    func testOverwriteExistingItemReturnsFalseWhenDestinationDoesNotExist() throws {
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in false },
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
    }

    func testOverwriteExistingItemCleansUpReplacementArtifactWhenReplaceFails() {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let expectedError = NSError(domain: NSCocoaErrorDomain, code: 512)
        var cleanedURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
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
}
