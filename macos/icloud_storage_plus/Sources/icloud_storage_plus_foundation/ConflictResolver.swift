import Foundation

/// Shared seams for resolving unresolved file-version conflicts.
///
/// The pure generic entry point accepts any `Version` type so callers
/// can inject test doubles via the DI-via-closures idiom already used
/// by `CoordinatedReplaceWriter.live`. The async wrapper below binds
/// the real `NSFileVersion` APIs.
///
/// MUST be called from within an `NSFileCoordinator` write block when
/// using the real `NSFileVersion` binding per Apple's documented
/// contract for `removeOtherVersionsOfItem(at:)`.
func resolveUnresolvedConflicts<Version>(
    at url: URL,
    unresolvedVersions: (URL) -> [Version]?,
    modificationDate: (Version) -> Date?,
    replaceItem: (Version, URL) throws -> Void,
    markResolved: (Version) -> Void,
    removeOtherVersions: (URL) throws -> Void
) throws {
    guard let conflicts = unresolvedVersions(url),
          !conflicts.isEmpty else {
        return
    }

    let sorted = conflicts.sorted {
        (modificationDate($0) ?? .distantPast)
            > (modificationDate($1) ?? .distantPast)
    }

    if let latest = sorted.first {
        try replaceItem(latest, url)
    }

    for version in conflicts {
        markResolved(version)
    }

    try removeOtherVersions(url)
}

/// Async-throws wrapper using the real `NSFileVersion` APIs.
///
/// Declared `async` so it matches the seam signature in
/// `CoordinatedReplaceWriter` and can be awaited inside future
/// coordinator blocks. The underlying `NSFileVersion` calls are
/// synchronous; there is no implicit suspension.
func resolveUnresolvedConflicts(at url: URL) async throws {
    try resolveUnresolvedConflicts(
        at: url,
        unresolvedVersions: {
            NSFileVersion.unresolvedConflictVersionsOfItem(at: $0)
        },
        modificationDate: { $0.modificationDate },
        replaceItem: { version, targetURL in
            try version.replaceItem(at: targetURL, options: [])
        },
        markResolved: { $0.isResolved = true },
        removeOtherVersions: {
            try NSFileVersion.removeOtherVersionsOfItem(at: $0)
        }
    )
}
