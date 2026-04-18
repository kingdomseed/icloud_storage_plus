import Foundation

// Keep this mirrored with the iOS foundation package until the reset work
// intentionally consolidates Darwin sources in a later task.

func resolvePresentedItemConflictsSync(at url: URL) throws {
    guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
          !conflicts.isEmpty else {
        return
    }

    // Observer recovery restores the newest known file version so the
    // presented item converges on the latest iCloud winner.
    let sorted = conflicts.sorted {
        ($0.modificationDate ?? .distantPast) >
            ($1.modificationDate ?? .distantPast)
    }

    if let latest = sorted.first {
        try latest.replaceItem(at: url, options: [])
    }

    for version in conflicts {
        version.isResolved = true
    }

    try NSFileVersion.removeOtherVersionsOfItem(at: url)
}

func resolvePresentedItemConflicts(at url: URL) async throws {
    try resolvePresentedItemConflictsSync(at: url)
}

func cleanupConflictsAfterOverwrite(at url: URL) throws {
    guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
          !conflicts.isEmpty else {
        return
    }

    for version in conflicts {
        version.isResolved = true
    }

    try NSFileVersion.removeOtherVersionsOfItem(at: url)
}
