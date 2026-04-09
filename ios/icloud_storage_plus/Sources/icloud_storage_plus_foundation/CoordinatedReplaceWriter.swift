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
