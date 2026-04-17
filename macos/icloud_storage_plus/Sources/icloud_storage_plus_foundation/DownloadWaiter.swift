import Foundation

/// Named default schedules for `waitForDownloadCompletion`.
///
/// Callers pick a schedule by intent. Both are exposed so read and
/// write paths parameterize the same helper rather than calling two
/// variants.
enum DownloadSchedule {
    /// User-triggered writes must not block minutes on a stalled
    /// download. ~32s maximum before a timeout fires.
    static let interactiveWrite: (
        idleTimeouts: [TimeInterval],
        retryBackoff: [TimeInterval]
    ) = (idleTimeouts: [10, 20], retryBackoff: [2])

    /// Background reads tolerate longer waits for cold items.
    static let backgroundRead: (
        idleTimeouts: [TimeInterval],
        retryBackoff: [TimeInterval]
    ) = (idleTimeouts: [60, 90, 180], retryBackoff: [2, 4])
}

/// Metadata-query scopes shared by every iCloud code path.
let iCloudMetadataQuerySearchScopes: [String] = [
    NSMetadataQueryUbiquitousDataScope,
    NSMetadataQueryUbiquitousDocumentsScope,
]

/// NSError surfaced when the idle watchdog exhausts its budget.
func iCloudDownloadTimeoutError() -> NSError {
    NSError(
        domain: "ICloudStorageTimeout",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Download idle timeout"]
    )
}

/// Resume-at-most-once gate used by the waiter to guard completion
/// across NSMetadataQuery observers, watchdog timers, and retries.
final class CompletionGate {
    private let queue = DispatchQueue(
        label: "icloud_storage_plus.completion_gate"
    )
    private var completed = false

    var isCompleted: Bool {
        queue.sync { completed }
    }

    func tryComplete() -> Bool {
        queue.sync {
            if completed { return false }
            completed = true
            return true
        }
    }
}

/// Result of evaluating the current download status for `fileURL`.
///
/// - Strategy:
///   1. Resolve the item via the query's first result when available
///      (handles recent renames/moves the filesystem hasn't caught up to).
///   2. Fall back to `fileURL` directly when the query isn't indexed.
func evaluateICloudDownloadStatus(
    query: NSMetadataQuery,
    fileURL: URL
) -> (completed: Bool, error: Error?) {
    let resolvedURL = (query.results.first as? NSMetadataItem)
        .flatMap { $0.value(forAttribute: NSMetadataItemURLKey) as? URL }
        ?? fileURL

    guard let values = try? resolvedURL.resourceValues(
        forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey,
        ]
    ) else {
        return (false, nil)
    }

    if let error = values.ubiquitousItemDownloadingError {
        return (true, error)
    }

    if values.ubiquitousItemDownloadingStatus == .current {
        return (true, nil)
    }

    return (false, nil)
}

/// Waits until `fileURL` reaches `.current` or a terminal error
/// surfaces. Uses an idle watchdog that resets when download progress
/// advances; when the watchdog elapses, the next entry in
/// `idleTimeouts` is tried after the matching `retryBackoff`. When
/// all entries are exhausted, throws `iCloudDownloadTimeoutError()`.
///
/// Passing empty schedules falls back to `DownloadSchedule.backgroundRead`
/// for compatibility with existing read callers that previously passed
/// empty arrays.
func waitForDownloadCompletion(
    at fileURL: URL,
    idleTimeouts: [TimeInterval],
    retryBackoff: [TimeInterval]
) async throws {
    if let values = try? fileURL.resourceValues(forKeys: [
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemDownloadingErrorKey,
    ]) {
        if let error = values.ubiquitousItemDownloadingError {
            throw error
        }
        if values.ubiquitousItemDownloadingStatus == .current {
            return
        }
    }

    let idleSchedule = idleTimeouts.isEmpty
        ? DownloadSchedule.backgroundRead.idleTimeouts
        : idleTimeouts
    let backoffSchedule = retryBackoff.isEmpty
        ? DownloadSchedule.backgroundRead.retryBackoff
        : retryBackoff

    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let gate = CompletionGate()
        let completeOnce: (Error?) -> Void = { error in
            guard gate.tryComplete() else { return }
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }

        func startAttempt(index: Int) {
            if gate.isCompleted { return }

            let query = NSMetadataQuery()
            query.operationQueue = .main
            query.searchScopes = iCloudMetadataQuerySearchScopes
            query.predicate = NSPredicate(
                format: "%K == %@",
                NSMetadataItemPathKey,
                fileURL.path
            )

            var watchdogTimer: Timer?
            var lastProgress = -1.0
            var observerTokens: [NSObjectProtocol] = []

            let tearDown: () -> Void = {
                watchdogTimer?.invalidate()
                watchdogTimer = nil
                for token in observerTokens {
                    NotificationCenter.default.removeObserver(token)
                }
                observerTokens.removeAll()
                query.stop()
            }

            let resetWatchdog: () -> Void = {
                watchdogTimer?.invalidate()
                watchdogTimer = Timer.scheduledTimer(
                    withTimeInterval: idleSchedule[index],
                    repeats: false
                ) { _ in
                    tearDown()
                    if index < idleSchedule.count - 1 {
                        let delayIndex = min(index, backoffSchedule.count - 1)
                        let delay = backoffSchedule[delayIndex]
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + delay
                        ) {
                            startAttempt(index: index + 1)
                        }
                        return
                    }
                    completeOnce(iCloudDownloadTimeoutError())
                }
            }

            let handleEvaluation: () -> Void = {
                let evaluation = evaluateICloudDownloadStatus(
                    query: query,
                    fileURL: fileURL
                )
                if evaluation.completed {
                    tearDown()
                    completeOnce(evaluation.error)
                    return
                }

                if let item = query.results.first as? NSMetadataItem,
                   let progress = item.value(
                    forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey
                   ) as? Double,
                   progress > lastProgress {
                    lastProgress = progress
                    resetWatchdog()
                }
            }

            let finishToken = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: query.operationQueue
            ) { _ in handleEvaluation() }
            observerTokens.append(finishToken)

            let updateToken = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: query.operationQueue
            ) { _ in handleEvaluation() }
            observerTokens.append(updateToken)

            DispatchQueue.main.async {
                guard !gate.isCompleted else {
                    return
                }
                resetWatchdog()
                query.start()
            }
        }

        startAttempt(index: 0)
    }
}
