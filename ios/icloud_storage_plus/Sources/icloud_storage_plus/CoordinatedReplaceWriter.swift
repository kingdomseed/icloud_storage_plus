import Foundation

struct CoordinatedReplaceWriter {
    typealias FileExists = (String) -> Bool
    typealias VerifyDestination = (URL) throws -> Void
    typealias CreateReplacementDirectory = (URL) throws -> URL
    typealias CoordinateReplace = (URL, (URL) throws -> Void) throws -> Void
    typealias ReplaceItem = (URL, URL) throws -> Void
    typealias RemoveItem = (URL) throws -> Void

    let fileExists: FileExists
    let verifyDestination: VerifyDestination
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

        try verifyDestination(destinationURL)

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
}

extension CoordinatedReplaceWriter {
    static let replaceStateErrorDomain = "ICloudStoragePlusErrorDomain"
    static let conflictReplaceStateCode = 1
    static let itemNotDownloadedReplaceStateCode = 2
    static let downloadInProgressReplaceStateCode = 3
    static let directoryReplaceStateCode = 4

    static func fileDestinationError(isDirectory: Bool) -> NSError? {
        guard isDirectory else {
            return nil
        }

        return NSError(
            domain: replaceStateErrorDomain,
            code: directoryReplaceStateCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot replace an existing directory with file content.",
            ]
        )
    }

    static func replaceReadyStateError(
        hasConflicts: Bool,
        isUbiquitousItem: Bool,
        downloadStatus: URLUbiquitousItemDownloadingStatus?,
        isDownloading: Bool
    ) -> NSError? {
        if hasConflicts {
            return NSError(
                domain: replaceStateErrorDomain,
                code: conflictReplaceStateCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Cannot replace an iCloud item with unresolved conflict versions.",
                ]
            )
        }

        guard isUbiquitousItem else {
            return nil
        }

        if downloadStatus == .current {
            return nil
        }

        if isDownloading {
            return NSError(
                domain: replaceStateErrorDomain,
                code: downloadInProgressReplaceStateCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Cannot replace an iCloud item while it is downloading.",
                ]
            )
        }

        return NSError(
            domain: replaceStateErrorDomain,
            code: itemNotDownloadedReplaceStateCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot replace a nonlocal iCloud item until it is fully downloaded.",
            ]
        )
    }

    static func verifyExistingDestinationCanBeReplaced(
        at destinationURL: URL
    ) throws {
        let hasConflicts = if let conflictVersions =
            NSFileVersion.unresolvedConflictVersionsOfItem(at: destinationURL) {
            !conflictVersions.isEmpty
        } else {
            false
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

        if let replaceStateError = replaceReadyStateError(
            hasConflicts: hasConflicts,
            isUbiquitousItem: values.isUbiquitousItem == true,
            downloadStatus: values.ubiquitousItemDownloadingStatus,
            isDownloading: values.ubiquitousItemIsDownloading == true
        ) {
            throw replaceStateError
        }
    }

    private static func verifyFileDestinationCanBeOverwritten(
        at destinationURL: URL
    ) throws {
        let values = try destinationURL.resourceValues(forKeys: [.isDirectoryKey])

        if let destinationError = fileDestinationError(
            isDirectory: values.isDirectory == true
        ) {
            throw destinationError
        }

        try verifyExistingDestinationCanBeReplaced(at: destinationURL)
    }

    static let live = CoordinatedReplaceWriter(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        verifyDestination: { destinationURL in
            try verifyFileDestinationCanBeOverwritten(at: destinationURL)
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
