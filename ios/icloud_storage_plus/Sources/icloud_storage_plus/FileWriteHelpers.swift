import Foundation

func streamCopyToURL(from sourceURL: URL, to destinationURL: URL) throws {
    let destinationDir = destinationURL.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try FileManager.default.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    guard let input = InputStream(url: sourceURL) else {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSLocalizedDescriptionKey: "Failed to open input stream"]
        )
    }

    guard let output = OutputStream(url: destinationURL, append: false) else {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSLocalizedDescriptionKey: "Failed to open output stream"]
        )
    }

    input.open()
    output.open()
    defer {
        input.close()
        output.close()
    }

    let bufferSize = 64 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while input.hasBytesAvailable {
        let read = input.read(&buffer, maxLength: buffer.count)
        if read < 0 {
            throw input.streamError ?? NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Stream read error"]
            )
        }
        if read == 0 {
            break
        }

        var totalWritten = 0
        while totalWritten < read {
            let written = buffer.withUnsafeBytes { rawBuffer -> Int in
                let base = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return output.write(
                    base.advanced(by: totalWritten),
                    maxLength: read - totalWritten
                )
            }
            if written <= 0 {
                let message = written == 0
                    ? "Stream write returned 0 bytes (stalled); treating as failure"
                    : "Stream write error"
                throw output.streamError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            totalWritten += written
        }
    }
}

func writeTextToURL(_ contents: String, to destinationURL: URL) throws {
    let destinationDir = destinationURL.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try FileManager.default.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    try contents.write(to: destinationURL, atomically: true, encoding: .utf8)
}

func writeDataToURL(_ contents: Data, to destinationURL: URL) throws {
    let destinationDir = destinationURL.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try FileManager.default.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    try contents.write(to: destinationURL, options: .atomic)
}
