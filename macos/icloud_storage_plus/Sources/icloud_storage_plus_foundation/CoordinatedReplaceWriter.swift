import Foundation

struct CoordinatedReplaceWriter {
    typealias FileExists = (String) -> Bool
    typealias EnsureDownloaded = (URL) async throws -> Void
    typealias VerifyDestination = (URL) throws -> Void
    typealias CreateReplacementDirectory = (URL) throws -> URL
    typealias CoordinateReplace = (
        URL,
        @escaping @Sendable (URL) async throws -> Void
    ) async throws -> Void
    typealias ResolveConflicts = (URL) async throws -> Void
    typealias ReplaceItem = (URL, URL) throws -> Void
    typealias RemoveItem = (URL) throws -> Void

    let fileExists: FileExists
    let ensureDownloaded: EnsureDownloaded
    let verifyDestination: VerifyDestination
    let createReplacementDirectory: CreateReplacementDirectory
    let coordinateReplace: CoordinateReplace
    let resolveConflicts: ResolveConflicts
    let replaceItem: ReplaceItem
    let removeItem: RemoveItem

    func overwriteExistingItem(
        at destinationURL: URL,
        prepareReplacementFile: (URL) throws -> Void
    ) async throws -> Bool {
        guard fileExists(destinationURL.path) else {
            return false
        }

        try await ensureDownloaded(destinationURL)

        try verifyDestination(destinationURL)

        let replacementDirectory = try createReplacementDirectory(destinationURL)
        let replacementURL = replacementDirectory
            .appendingPathComponent(destinationURL.lastPathComponent)

        do {
            try prepareReplacementFile(replacementURL)
            let resolveConflicts = self.resolveConflicts
            let replaceItem = self.replaceItem
            try await coordinateReplace(destinationURL) {
                [replacementURL] coordinatedURL in
                try await resolveConflicts(coordinatedURL)
                // The resolver above calls `replaceItem(at:)` on the
                // most-recent conflict version; the next line clobbers
                // that content with the user's replacement. That's
                // Apple's canonical pattern — accepting the micro-cost
                // keeps one way to resolve conflicts across both the
                // observer path and the write path.
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
    static let autoResolveFailedDescriptionMarker = "auto-resolution failed"

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

    /// Wraps an auto-resolution failure in an `ICloudStoragePlusErrorDomain`
    /// conflict error so the Dart layer still maps it to
    /// `ICloudConflictException` while signaling (via the localized
    /// description) that the failure came from resolution, not pre-flight.
    static func autoResolveConflictError(
        underlying: Error
    ) -> NSError {
        NSError(
            domain: replaceStateErrorDomain,
            code: conflictReplaceStateCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot replace an iCloud item: "
                    + "\(autoResolveFailedDescriptionMarker) — "
                    + (underlying as NSError).localizedDescription,
                NSUnderlyingErrorKey: underlying,
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

    /// Directory-only pre-flight for the writeInPlace path.
    ///
    /// The new auto-resolve / auto-download seams handle conflict and
    /// download states recoverably. Pre-flight refusal on those states
    /// would block the seams from running. Only categorical
    /// impossibilities (replacing a directory with a file) belong
    /// here. The legacy `verifyExistingDestinationCanBeReplaced`
    /// remains for the copy path, which still runs without recovery.
    static func verifyOverwriteDestinationIsFile(
        at destinationURL: URL
    ) throws {
        let values = try destinationURL.resourceValues(forKeys: [.isDirectoryKey])

        if let destinationError = fileDestinationError(
            isDirectory: values.isDirectory == true
        ) {
            throw destinationError
        }
    }

    /// Default `ensureDownloaded` binding: no-op for non-ubiquitous
    /// items and already-current ubiquitous items; surfaces any
    /// existing download error; otherwise kicks off a download and
    /// waits using the interactive-write schedule.
    static let liveEnsureDownloaded: EnsureDownloaded = { url in
        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey,
        ])
        guard values.isUbiquitousItem == true else { return }
        if let err = values.ubiquitousItemDownloadingError {
            throw err
        }
        guard values.ubiquitousItemDownloadingStatus != .current else {
            return
        }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        try await waitForDownloadCompletion(
            at: url,
            idleTimeouts: DownloadSchedule.interactiveWrite.idleTimeouts,
            retryBackoff: DownloadSchedule.interactiveWrite.retryBackoff
        )
    }

    /// Default `coordinateReplace` binding: bridges async accessor
    /// work into `NSFileCoordinator.coordinate(writingItemAt:)` via a
    /// short-lived DispatchSemaphore. Safe because the live accessor
    /// (resolveConflicts + replaceItem) has no actual suspension
    /// points — resolveUnresolvedConflicts calls synchronous
    /// NSFileVersion APIs wrapped in `async`.
    static let liveCoordinateReplace: CoordinateReplace = {
        destinationURL, accessor in
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var accessError: Error?

            coordinator.coordinate(
                writingItemAt: destinationURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                let semaphore = DispatchSemaphore(value: 0)
                let errorBox = CoordinatedReplaceErrorBox()
                Task.detached {
                    do {
                        try await accessor(coordinatedURL)
                    } catch {
                        errorBox.error = error
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                accessError = errorBox.error
            }

            if let coordinationError {
                continuation.resume(throwing: coordinationError)
                return
            }
            if let accessError {
                continuation.resume(throwing: accessError)
                return
            }
            continuation.resume()
        }
    }

    static let live = CoordinatedReplaceWriter(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        ensureDownloaded: liveEnsureDownloaded,
        verifyDestination: { destinationURL in
            try verifyOverwriteDestinationIsFile(at: destinationURL)
        },
        createReplacementDirectory: { destinationURL in
            try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: destinationURL,
                create: true
            )
        },
        coordinateReplace: liveCoordinateReplace,
        resolveConflicts: { url in
            do {
                try await resolveUnresolvedConflicts(at: url)
            } catch {
                throw autoResolveConflictError(underlying: error)
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

/// Escape hatch for the sync-to-async bridge inside `liveCoordinateReplace`.
/// Lives at file scope so the bridge closure can capture it without
/// tying it to a specific test double.
private final class CoordinatedReplaceErrorBox: @unchecked Sendable {
    var error: Error?
}
