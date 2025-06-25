import UIKit

/// UIDocument subclass for handling iCloud documents with proper file coordination
/// This class provides automatic conflict resolution, version tracking, and safe file operations
class ICloudDocument: UIDocument {
    /// The raw data content of the document
    var data: Data?
    
    /// Error occurred during the last operation (if any)
    var lastError: Error?
    
    // MARK: - UIDocument Override Methods
    
    /// Returns the document contents to be written to disk
    /// - Parameter typeName: The uniform type identifier for the document
    /// - Returns: The document data to be saved
    override func contents(forType typeName: String) throws -> Any {
        guard let data = data else {
            // Return empty data if no content is set
            return Data()
        }
        return data
    }
    
    /// Loads the document contents from disk
    /// - Parameters:
    ///   - contents: The document data loaded from disk
    ///   - typeName: The uniform type identifier for the document
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load document: Invalid data format"]
            )
        }
        self.data = data
    }
    
    // MARK: - Conflict Resolution
    
    /// Called when the document state changes (including conflict detection)
    override func stateChanged(from oldState: UIDocument.State, to newState: UIDocument.State) {
        super.stateChanged(from: oldState, to: newState)
        
        // Handle conflict state
        if newState.contains(.inConflict) {
            resolveConflicts()
        }
        
        // Log other state changes for debugging
        if newState.contains(.savingError) {
            DebugHelper.log("Document saving error: \(fileURL.lastPathComponent)")
        }
        
        if newState.contains(.editingDisabled) {
            DebugHelper.log("Document editing disabled: \(fileURL.lastPathComponent)")
        }
    }
    
    /// Automatically resolve conflicts by choosing the most recent version
    private func resolveConflicts() {
        guard let fileURL = fileURL else { return }
        
        DebugHelper.log("Resolving conflicts for: \(fileURL.lastPathComponent)")
        
        // Get all conflicting versions
        if let conflictVersions = NSFileVersion.unresolvedConflictVersions(of: fileURL),
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
}

// MARK: - Extension for Document Operations

extension ICloudStoragePlugin {
    /// Read a document from iCloud using UIDocument
    /// - Parameters:
    ///   - url: The URL of the document to read
    ///   - completion: Completion handler with the document data or error
    func readDocumentAt(url: URL, completion: @escaping (Data?, Error?) -> Void) {
        let document = ICloudDocument(fileURL: url)
        
        document.open { success in
            if success {
                // Successfully opened the document
                completion(document.data, nil)
                
                // Close the document after reading
                document.close { _ in
                    DebugHelper.log("Document closed: \(url.lastPathComponent)")
                }
            } else {
                // Failed to open the document
                let error = document.lastError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to open document"]
                )
                completion(nil, error)
            }
        }
    }
    
    /// Write a document to iCloud using UIDocument
    /// - Parameters:
    ///   - url: The URL where the document should be saved
    ///   - data: The data to write to the document
    ///   - completion: Completion handler with optional error
    func writeDocument(at url: URL, data: Data, completion: @escaping (Error?) -> Void) {
        let document = ICloudDocument(fileURL: url)
        document.data = data
        
        // Determine if this is a new document or overwriting existing
        let saveOperation: UIDocument.SaveOperation = FileManager.default.fileExists(atPath: url.path) ? .forOverwriting : .forCreating
        
        document.save(to: url, for: saveOperation) { success in
            if success {
                // Successfully saved the document
                document.close { _ in
                    completion(nil)
                }
            } else {
                // Failed to save the document
                let error = document.lastError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to save document"]
                )
                completion(error)
            }
        }
    }
    
    /// Check document state and conflicts
    /// - Parameters:
    ///   - url: The URL of the document to check
    ///   - completion: Completion handler with document state information
    func checkDocumentState(at url: URL, completion: @escaping ([String: Any]?, Error?) -> Void) {
        let document = ICloudDocument(fileURL: url)
        
        document.open { success in
            if success {
                var stateInfo: [String: Any] = [:]
                
                // Document state flags
                stateInfo["hasConflicts"] = document.documentState.contains(.inConflict)
                stateInfo["hasUnsavedChanges"] = document.hasUnsavedChanges
                stateInfo["isEditingDisabled"] = document.documentState.contains(.editingDisabled)
                stateInfo["isClosed"] = document.documentState.contains(.closed)
                stateInfo["isNormal"] = document.documentState.contains(.normal)
                stateInfo["isSavingError"] = document.documentState.contains(.savingError)
                
                // File modification date
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    stateInfo["modificationDate"] = modificationDate.timeIntervalSince1970
                }
                
                // Check for conflict versions
                if let conflictVersions = NSFileVersion.unresolvedConflictVersions(of: url) {
                    stateInfo["conflictCount"] = conflictVersions.count
                }
                
                document.close { _ in
                    completion(stateInfo, nil)
                }
            } else {
                let error = document.lastError ?? NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to check document state"]
                )
                completion(nil, error)
            }
        }
    }
}