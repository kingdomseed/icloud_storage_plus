import Cocoa

/// NSDocument subclass for handling iCloud documents with proper file coordination
/// This class provides automatic conflict resolution, version tracking, and safe file operations
class ICloudDocument: NSDocument {
    /// The raw data content of the document
    var data: Data?
    
    /// Error occurred during the last operation (if any)
    var lastError: Error?
    
    // MARK: - NSDocument Override Methods
    
    /// Returns the document contents to be written to disk
    /// - Parameter typeName: The uniform type identifier for the document
    /// - Returns: The document data to be saved
    override func data(ofType typeName: String) throws -> Data {
        guard let data = data else {
            // Return empty data if no content is set
            return Data()
        }
        return data
    }
    
    /// Loads the document contents from disk
    /// - Parameters:
    ///   - data: The document data loaded from disk
    ///   - typeName: The uniform type identifier for the document
    override func read(from data: Data, ofType typeName: String) throws {
        self.data = data
    }
    
    /// Enable autosaving for iCloud documents
    override class var autosavesInPlace: Bool {
        return true
    }
    
    // MARK: - File Presenter Protocol
    
    /// Handle file version conflicts
    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        
        // Check for conflicts
        if let fileURL = fileURL,
           let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL),
           !conflictVersions.isEmpty {
            resolveConflicts()
        }
    }
    
    /// Handle when the document is moved
    override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        DebugHelper.log("Document moved to: \(newURL.lastPathComponent)")
    }
    
    // MARK: - Conflict Resolution
    
    /// Automatically resolve conflicts by choosing the most recent version
    private func resolveConflicts() {
        guard let fileURL = fileURL else { return }
        
        DebugHelper.log("Resolving conflicts for: \(fileURL.lastPathComponent)")
        
        // Get all conflicting versions
        if let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL),
           !conflictVersions.isEmpty {
            
            // Find the most recent version based on modification date
            let sortedVersions = conflictVersions.sorted { version1, version2 in
                let date1 = version1.modificationDate ?? Date.distantPast
                let date2 = version2.modificationDate ?? Date.distantPast
                return date1 > date2
            }
            
            // Use the most recent version
            if let mostRecentVersion = sortedVersions.first {
                do {
                    // Replace current file with the most recent version
                    try mostRecentVersion.replaceItem(at: fileURL)
                    
                    // Mark all conflicts as resolved
                    for version in conflictVersions {
                        version.isResolved = true
                    }
                    
                    // Remove resolved versions
                    try NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
                    
                    DebugHelper.log("Conflicts resolved using version from: \(mostRecentVersion.modificationDate?.description ?? "unknown")")
                } catch {
                    DebugHelper.log("Failed to resolve conflicts: \(error.localizedDescription)")
                    lastError = error
                }
            }
        }
    }
    
    // MARK: - Error Handling
    
    /// Handle document reading errors
    override func read(from url: URL, ofType typeName: String) throws {
        do {
            try super.read(from: url, ofType: typeName)
        } catch {
            lastError = error
            throw error
        }
    }
    
    /// Handle document writing errors
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        do {
            try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        } catch {
            lastError = error
            throw error
        }
    }
}

// MARK: - Extension for Document Operations

extension ICloudStoragePlugin {
    /// Read a document from iCloud using NSDocument
    /// - Parameters:
    ///   - url: The URL of the document to read
    ///   - completion: Completion handler with the document data or error
    func readDocumentAt(url: URL, completion: @escaping (Data?, Error?) -> Void) {
        // Create and configure the document
        let document = ICloudDocument()
        
        // Use a background queue for document operations
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Read the document
                try document.read(from: url, ofType: "public.data")
                
                // Return the data on the main queue
                DispatchQueue.main.async {
                    completion(document.data, nil)
                }
            } catch {
                // Return the error on the main queue
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Write a document to iCloud using NSDocument
    /// - Parameters:
    ///   - url: The URL where the document should be saved
    ///   - data: The data to write to the document
    ///   - completion: Completion handler with optional error
    func writeDocument(at url: URL, data: Data, completion: @escaping (Error?) -> Void) {
        // Create and configure the document
        let document = ICloudDocument()
        document.data = data
        
        // Determine save operation type
        let saveOperation: NSDocument.SaveOperationType = FileManager.default.fileExists(atPath: url.path) ? .saveAsOperation : .saveOperation
        
        // Use a background queue for document operations
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Save the document
                try document.writeSafely(to: url, ofType: "public.data", for: saveOperation)
                
                // Return success on the main queue
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                // Return the error on the main queue
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    /// Check document state and conflicts
    /// - Parameters:
    ///   - url: The URL of the document to check
    ///   - completion: Completion handler with document state information
    func checkDocumentState(at url: URL, completion: @escaping ([String: Any]?, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var stateInfo: [String: Any] = [:]
            
            // Check if file exists
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            stateInfo["exists"] = fileExists
            
            if fileExists {
                do {
                    // Get file attributes
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    
                    // File modification date
                    if let modificationDate = attributes[.modificationDate] as? Date {
                        stateInfo["modificationDate"] = modificationDate.timeIntervalSince1970
                    }
                    
                    // File size
                    if let fileSize = attributes[.size] as? Int64 {
                        stateInfo["fileSize"] = fileSize
                    }
                    
                    // Check for conflict versions
                    if let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
                        stateInfo["hasConflicts"] = !conflictVersions.isEmpty
                        stateInfo["conflictCount"] = conflictVersions.count
                        
                        // Get conflict version dates
                        let conflictDates = conflictVersions.compactMap { $0.modificationDate?.timeIntervalSince1970 }
                        if !conflictDates.isEmpty {
                            stateInfo["conflictDates"] = conflictDates
                        }
                    } else {
                        stateInfo["hasConflicts"] = false
                        stateInfo["conflictCount"] = 0
                    }
                    
                    // Check if file is downloaded
                    let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    if let downloadingStatus = resourceValues.ubiquitousItemDownloadingStatus {
                        stateInfo["isDownloaded"] = (downloadingStatus == .current)
                        stateInfo["downloadingStatus"] = downloadingStatus.rawValue
                    }
                    
                    DispatchQueue.main.async {
                        completion(stateInfo, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    let error = NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSFileNoSuchFileError,
                        userInfo: [NSLocalizedDescriptionKey: "File does not exist"]
                    )
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Create a new document with initial content
    /// - Parameters:
    ///   - url: The URL where the document should be created
    ///   - data: The initial data for the document
    ///   - completion: Completion handler with optional error
    func createDocument(at url: URL, data: Data, completion: @escaping (Error?) -> Void) {
        // Ensure parent directory exists
        let parentDirectory = url.deletingLastPathComponent()
        
        do {
            if !FileManager.default.fileExists(atPath: parentDirectory.path) {
                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Use writeDocument to create the file
            writeDocument(at: url, data: data, completion: completion)
        } catch {
            completion(error)
        }
    }
}