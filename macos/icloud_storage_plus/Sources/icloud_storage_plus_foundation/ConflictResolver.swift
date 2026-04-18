import Foundation

func resolvePresentedItemConflictsSync(at url: URL) throws {
    guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
          !conflicts.isEmpty else {
        return
    }

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
