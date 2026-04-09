import Foundation

struct CoordinatedReplaceWriter {
    typealias FileExists = (String) -> Bool
    typealias VerifyDestinationState = (URL) throws -> Void
    typealias CreateReplacementDirectory = (URL) throws -> URL
    typealias CoordinateReplace = (URL, (URL) throws -> Void) throws -> Void
    typealias ReplaceItem = (URL, URL) throws -> Void
    typealias RemoveItem = (URL) throws -> Void

    let fileExists: FileExists
    let verifyDestinationState: VerifyDestinationState
    let createReplacementDirectory: CreateReplacementDirectory
    let coordinateReplace: CoordinateReplace
    let replaceItem: ReplaceItem
    let removeItem: RemoveItem

    func overwriteExistingItem(
        at destinationURL: URL,
        prepareReplacementFile: (URL) throws -> Void
    ) throws -> Bool {
        guard fileExists(destinationURL.path) else {
            return false
        }

        try verifyDestinationState(destinationURL)

        let replacementDirectory = try createReplacementDirectory(destinationURL)
        let replacementURL = replacementDirectory
            .appendingPathComponent(destinationURL.lastPathComponent)

        do {
            try prepareReplacementFile(replacementURL)
            try coordinateReplace(destinationURL) { coordinatedURL in
                try replaceItem(coordinatedURL, replacementURL)
            }
        } catch {
            try? removeItem(replacementDirectory)
            throw error
        }

        try? removeItem(replacementDirectory)
        return true
    }

    func copyItemOverwritingExistingItem(
        from sourceURL: URL,
        to destinationURL: URL,
        copyItem: (URL, URL) throws -> Void
    ) throws -> Bool {
        try overwriteExistingItem(at: destinationURL) { replacementURL in
            try copyItem(sourceURL, replacementURL)
        }
    }
}

extension CoordinatedReplaceWriter {
    private static func verifyReplaceReadyState(for destinationURL: URL) throws {
        if let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(
            at: destinationURL
        ), !conflictVersions.isEmpty {
            throw NSError(
                domain: "ICloudStoragePlusErrorDomain",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Cannot replace an iCloud item with unresolved conflict versions.",
                ]
            )
        }

        let values = try destinationURL.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadingErrorKey,
        ])

        if let downloadError = values.ubiquitousItemDownloadingError {
            throw downloadError
        }

        guard values.isUbiquitousItem == true else {
            return
        }

        let downloadStatus = values.ubiquitousItemDownloadingStatus

        if downloadStatus == .current {
            return
        }

        if values.ubiquitousItemIsDownloading == true
            || downloadStatus == .notDownloaded {
            throw NSError(
                domain: "ICloudStoragePlusErrorDomain",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Cannot replace a nonlocal iCloud item until it is fully downloaded.",
                ]
            )
        }
    }

    static let live = CoordinatedReplaceWriter(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        verifyDestinationState: { destinationURL in
            try verifyReplaceReadyState(for: destinationURL)
        },
        createReplacementDirectory: { destinationURL in
            try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: destinationURL,
                create: true
            )
        },
        coordinateReplace: { destinationURL, accessor in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var accessError: Error?

            coordinator.coordinate(
                writingItemAt: destinationURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try accessor(coordinatedURL)
                } catch {
                    accessError = error
                }
            }

            if let coordinationError {
                throw coordinationError
            }

            if let accessError {
                throw accessError
            }
        },
        replaceItem: { destinationURL, replacementURL in
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: replacementURL
            )
        },
        removeItem: { url in
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    )
}
