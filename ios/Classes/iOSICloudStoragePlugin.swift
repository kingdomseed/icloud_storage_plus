import Flutter
import UIKit

@objc(ICloudStoragePlugin)
public class ICloudStoragePlugin: NSObject, FlutterPlugin {
  var listStreamHandler: StreamHandler?
  var messenger: FlutterBinaryMessenger?
  var streamHandlers: [String: StreamHandler] = [:]
  let querySearchScopes = [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope];
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: "icloud_storage", binaryMessenger: messenger)
    let instance = ICloudStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.messenger = messenger
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "icloudAvailable":
      icloudAvailable(result)
    case "gather":
      gather(call, result)
    case "upload":
      upload(call, result)
    case "download":
      download(call, result)
    case "delete":
      delete(call, result)
    case "move":
      move(call, result)
    case "copy":
      copy(call, result)
    case "createEventChannel":
      createEventChannel(call, result)
    case "getContainerPath":
      getContainerPath(call, result)
    case "downloadAndRead":
      downloadAndRead(call, result)
    case "readDocument":
      readDocument(call, result)
    case "writeDocument":
      writeDocument(call, result)
    case "documentExists":
      documentExists(call, result)
    case "getDocumentMetadata":
      getDocumentMetadata(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  /// Check if iCloud is available and user is logged in
  ///
  /// Returns true if iCloud is available and user is logged in, false otherwise
  private func icloudAvailable(_ result: @escaping FlutterResult) {
    let status = FileManager.default.ubiquityIdentityToken != nil
    result(status)
  }

  private func getContainerPath(_ call: FlutterMethodCall, _ result: @escaping FlutterResult){
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    result(containerURL.path)
  }
  
  private func gather(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K beginswith %@", NSMetadataItemPathKey, containerURL.path)
    addGatherFilesObservers(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
    
    if !eventChannelName.isEmpty {
      let streamHandler = self.streamHandlers[eventChannelName]!
      streamHandler.onCancelHandler = { [self] in
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
    }
    query.start()
  }
  
  private func addGatherFilesObservers(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) {
      [self] (notification) in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        removeObservers(query)
        if eventChannelName.isEmpty { query.stop() }
        result(files)
    }
    
    if !eventChannelName.isEmpty {
      NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) {
        [self] (notification) in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        let streamHandler = self.streamHandlers[eventChannelName]!
        streamHandler.setEvent(files)
      }
    }
  }
  
  private func mapFileAttributesFromQuery(query: NSMetadataQuery, containerURL: URL) -> [[String: Any?]] {
    var fileMaps: [[String: Any?]] = []
    for item in query.results {
      guard let fileItem = item as? NSMetadataItem else { continue }
      guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
      if fileURL.absoluteString.last == "/" { continue }

      let map: [String: Any?] = [
        "relativePath": String(fileURL.absoluteString.dropFirst(containerURL.absoluteString.count)),
        "sizeInBytes": fileItem.value(forAttribute: NSMetadataItemFSSizeKey),
        "creationDate": (fileItem.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date)?.timeIntervalSince1970,
        "contentChangeDate": (fileItem.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date)?.timeIntervalSince1970,
        "hasUnresolvedConflicts": (fileItem.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) ?? false,
        "downloadStatus": fileItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey),
        "isDownloading": (fileItem.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool) ?? false,
        "isUploaded": (fileItem.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) ?? false,
        "isUploading": (fileItem.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool) ?? false,
      ]
      fileMaps.append(map)
    }
    return fileMaps
  }
  
  private func upload(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let cloudFileName = args["cloudFileName"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
    let localFileURL = URL(fileURLWithPath: localFilePath)
    
    // Check if this is a text file that should use document-based approach
    let fileExtension = (cloudFileName as NSString).pathExtension.lowercased()
    let textExtensions = ["json", "txt", "xml", "plist", "yaml", "yml", "md", "log", "csv", "js", "ts", "jsx", "tsx", "swift", "dart", "py", "rb", "java", "kt", "go", "rs", "c", "cpp", "h", "hpp", "m", "mm", "sh", "bash", "zsh", "fish"]
    
    if textExtensions.contains(fileExtension) {
      // Use document-based approach for text files for better conflict resolution
      do {
        let data = try Data(contentsOf: localFileURL)
        
        // Create parent directories if needed
        let cloudFileDirURL = cloudFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: cloudFileDirURL.path) {
          try FileManager.default.createDirectory(at: cloudFileDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        writeDocument(at: cloudFileURL, data: data) { error in
          if let error = error {
            result(self.nativeCodeError(error))
          } else {
            // Set up progress monitoring if needed
            if !eventChannelName.isEmpty {
              self.setupUploadProgressMonitoring(cloudFileURL: cloudFileURL, eventChannelName: eventChannelName)
            }
            result(nil)
          }
        }
      } catch {
        result(nativeCodeError(error))
      }
    } else {
      // Use file coordinator for binary files (images, videos, etc.)
      let fileCoordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      
      fileCoordinator.coordinate(writingItemAt: cloudFileURL, options: .forReplacing, error: &coordinationError) { writingURL in
        do {
          // Create parent directories if needed
          let cloudFileDirURL = writingURL.deletingLastPathComponent()
          if !FileManager.default.fileExists(atPath: cloudFileDirURL.path) {
            try FileManager.default.createDirectory(at: cloudFileDirURL, withIntermediateDirectories: true, attributes: nil)
          }
          
          // Remove existing file if it exists
          if FileManager.default.fileExists(atPath: writingURL.path) {
            try FileManager.default.removeItem(at: writingURL)
          }
          
          // Copy the file to iCloud
          try FileManager.default.copyItem(at: localFileURL, to: writingURL)
        } catch {
          result(self.nativeCodeError(error))
        }
      }
      
      if let error = coordinationError {
        result(nativeCodeError(error))
        return
      }
      
      // Set up progress monitoring if needed
      if !eventChannelName.isEmpty {
        self.setupUploadProgressMonitoring(cloudFileURL: cloudFileURL, eventChannelName: eventChannelName)
      }
      
      result(nil)
    }
  }
  
  private func setupUploadProgressMonitoring(cloudFileURL: URL, eventChannelName: String) {
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
    
    let uploadStreamHandler = self.streamHandlers[eventChannelName]!
    uploadStreamHandler.onCancelHandler = { [self] in
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
    }
    addUploadObservers(query: query, eventChannelName: eventChannelName)
    
    query.start()
  }
  
  private func addUploadObservers(query: NSMetadataQuery, eventChannelName: String) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
      onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
    }
    
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
      onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
    }
  }
  
  private func onUploadQueryNotification(query: NSMetadataQuery, eventChannelName: String) {
    if query.results.count == 0 {
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemUploadingErrorKey]) else { return}
    guard let streamHandler = self.streamHandlers[eventChannelName] else { return }
    
    if let error = fileURLValues.ubiquitousItemUploadingError {
      streamHandler.setEvent(nativeCodeError(error))
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double {
      streamHandler.setEvent(progress)
      if (progress >= 100) {
        streamHandler.setEvent(FlutterEndOfEventStream)
        removeStreamHandler(eventChannelName)
      }
    }
  }
  
  private func download(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let cloudFileName = args["cloudFileName"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: cloudFileURL)
    } catch {
      result(nativeCodeError(error))
    }
    
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
    
    let downloadStreamHandler = self.streamHandlers[eventChannelName]
    downloadStreamHandler?.onCancelHandler = { [self] in
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
    }

    addDownloadObservers(query: query, eventChannelName: eventChannelName, result)
    
    query.start()
  }
  
  private func addDownloadObservers(query: NSMetadataQuery,eventChannelName: String, _ result: @escaping FlutterResult) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
      onDownloadQueryNotification(query: query, eventChannelName: eventChannelName, result)
    }
    
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
      onDownloadQueryNotification(query: query, eventChannelName: eventChannelName, result)
    }
  }
  
  private func onDownloadQueryNotification(query: NSMetadataQuery, eventChannelName: String, _ result: @escaping FlutterResult) {
    if query.results.count == 0 {
      result(false);
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey, .ubiquitousItemDownloadingStatusKey]) else { return }
    let streamHandler = self.streamHandlers[eventChannelName]
    
    if let error = fileURLValues.ubiquitousItemDownloadingError {
      streamHandler?.setEvent(nativeCodeError(error))
      result(nativeCodeError(error))
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
      streamHandler?.setEvent(progress)
    }
    
    if fileURLValues.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
      // Use NSFileCoordinator to read the file
      let fileCoordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      
      fileCoordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinationError) { (readingURL) in
        // File is now available for reading
        streamHandler?.setEvent(FlutterEndOfEventStream)
        removeStreamHandler(eventChannelName)
        result(true)
      }
      
      if let error = coordinationError {
        streamHandler?.setEvent(nativeCodeError(error))
        result(nativeCodeError(error))
      }
    }
  }
  
  /// Download a file from iCloud and safely read its contents
  /// This method combines download and reading to prevent permission errors
  private func downloadAndRead(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let cloudFileName = args["cloudFileName"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("downloadAndRead - containerURL: \(containerURL.path)")
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
    
    // First, start the download
    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: cloudFileURL)
    } catch {
      result(nativeCodeError(error))
      return
    }
    
    // Set up a query to monitor download progress
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
    
    let downloadStreamHandler = self.streamHandlers[eventChannelName]
    downloadStreamHandler?.onCancelHandler = { [self] in
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
    }
    
    // Add observers for download progress with content reading
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [weak self] (notification) in
      self?.handleDownloadAndRead(query: query, cloudFileURL: cloudFileURL, eventChannelName: eventChannelName, result: result)
    }
    
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [weak self] (notification) in
      self?.handleDownloadAndRead(query: query, cloudFileURL: cloudFileURL, eventChannelName: eventChannelName, result: result)
    }
    
    query.start()
  }
  
  /// Handle download progress and read file content when complete
  private func handleDownloadAndRead(query: NSMetadataQuery, cloudFileURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    if query.results.count == 0 {
      result(FlutterError(code: "E_FNF", message: "File not found in iCloud", details: nil))
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem,
          let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL,
          let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey, .ubiquitousItemDownloadingStatusKey]) else {
      return
    }
    
    let streamHandler = self.streamHandlers[eventChannelName]
    
    // Handle download errors
    if let error = fileURLValues.ubiquitousItemDownloadingError {
      streamHandler?.setEvent(nativeCodeError(error))
      result(nativeCodeError(error))
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
      return
    }
    
    // Report download progress
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
      streamHandler?.setEvent(progress)
    }
    
    // When download is complete, read the file using UIDocument
    if fileURLValues.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
      // Use our document wrapper to safely read the file
      readDocumentAt(url: cloudFileURL) { [weak self] (data, error) in
        guard let self = self else { return }
        
        // Clean up the query and observers
        self.removeObservers(query)
        query.stop()
        streamHandler?.setEvent(FlutterEndOfEventStream)
        self.removeStreamHandler(eventChannelName)
        
        if let error = error {
          result(self.nativeCodeError(error))
        } else if let data = data {
          // Return the file content as FlutterStandardTypedData
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(FlutterError(code: "E_READ", message: "Failed to read file content", details: nil))
        }
      }
    }
  }
  
  /// Read a document from iCloud using UIDocument
  /// Returns nil if file doesn't exist
  private func readDocument(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    
    let fileURL = containerURL.appendingPathComponent(relativePath)
    
    // Check if file exists first
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      result(nil) // Return nil for non-existent files
      return
    }
    
    // Use our UIDocument wrapper for safe reading
    readDocumentAt(url: fileURL) { (data, error) in
      if let error = error {
        result(self.nativeCodeError(error))
        return
      }
      
      guard let data = data else {
        result(nil)
        return
      }
      
      // Return as FlutterStandardTypedData
      result(FlutterStandardTypedData(bytes: data))
    }
  }
  
  /// Write a document to iCloud using UIDocument
  /// Creates the file if it doesn't exist, updates if it does
  private func writeDocument(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let flutterData = args["data"] as? FlutterStandardTypedData
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    
    let fileURL = containerURL.appendingPathComponent(relativePath)
    let data = flutterData.data
    
    // Create parent directories if needed
    let dirURL = fileURL.deletingLastPathComponent()
    do {
      if !FileManager.default.fileExists(atPath: dirURL.path) {
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
      }
    } catch {
      result(nativeCodeError(error))
      return
    }
    
    // Use our UIDocument wrapper for safe writing
    writeDocument(at: fileURL, data: data) { (error) in
      if let error = error {
        result(self.nativeCodeError(error))
        return
      }
      result(nil)
    }
  }
  
  /// Check if a document exists without downloading
  private func documentExists(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    
    let fileURL = containerURL.appendingPathComponent(relativePath)
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    result(exists)
  }
  
  /// Get document metadata without downloading content
  private func getDocumentMetadata(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    
    let fileURL = containerURL.appendingPathComponent(relativePath)
    
    // Check if file exists
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      result(nil)
      return
    }
    
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      var metadata: [String: Any] = [:]
      
      if let size = attributes[.size] as? Int64 {
        metadata["sizeInBytes"] = size
      }
      
      if let creationDate = attributes[.creationDate] as? Date {
        metadata["creationDate"] = creationDate.timeIntervalSince1970
      }
      
      if let modificationDate = attributes[.modificationDate] as? Date {
        metadata["modificationDate"] = modificationDate.timeIntervalSince1970
      }
      
      // Check download status
      let resourceValues = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemHasUnresolvedConflictsKey])
      
      if let downloadingStatus = resourceValues.ubiquitousItemDownloadingStatus {
        metadata["isDownloaded"] = (downloadingStatus == .current)
        metadata["downloadingStatus"] = downloadingStatus.rawValue
      }
      
      if let hasConflicts = resourceValues.ubiquitousItemHasUnresolvedConflicts {
        metadata["hasUnresolvedConflicts"] = hasConflicts
      }
      
      result(metadata)
    } catch {
      result(nativeCodeError(error))
    }
  }
  
  private func moveCloudFile(at: URL, to: URL) throws {
    do {
      if FileManager.default.fileExists(atPath: to.path) {
        try FileManager.default.removeItem(at: to)
      }
      try FileManager.default.copyItem(at: at, to: to)
    } catch {
      throw error
    }
  }
  
  private func delete(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let cloudFileName = args["cloudFileName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let fileURL = containerURL.appendingPathComponent(cloudFileName)
    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    fileCoordinator.coordinate(writingItemAt: fileURL, options: NSFileCoordinator.WritingOptions.forDeleting, error: nil) {
      writingURL in
      do {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: writingURL.path, isDirectory: &isDir) {
          result(fileNotFoundError)
          return
        }
        try FileManager.default.removeItem(at: writingURL)
        result(nil)
      } catch {
        DebugHelper.log("error: \(error.localizedDescription)")
        result(nativeCodeError(error))
      }
    }
  }
  
  private func move(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let atRelativePath = args["atRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let atURL = containerURL.appendingPathComponent(atRelativePath)
    let toURL = containerURL.appendingPathComponent(toRelativePath)
    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    fileCoordinator.coordinate(writingItemAt: atURL, options: NSFileCoordinator.WritingOptions.forMoving, writingItemAt: toURL, options: NSFileCoordinator.WritingOptions.forReplacing, error: nil) {
      atWritingURL, toWritingURL in
      do {
        let toDirURL = toWritingURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: toDirURL.path) {
          try FileManager.default.createDirectory(at: toDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        try FileManager.default.moveItem(at: atWritingURL, to: toWritingURL)
        result(nil)
      } catch {
        DebugHelper.log("error: \(error.localizedDescription)")
        result(nativeCodeError(error))
      }
    }
  }
  
  private func copy(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let fromRelativePath = args["fromRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let fromURL = containerURL.appendingPathComponent(fromRelativePath)
    let toURL = containerURL.appendingPathComponent(toRelativePath)
    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    
    // Use reading coordination for source and writing coordination for destination
    fileCoordinator.coordinate(readingItemAt: fromURL, options: .withoutChanges, writingItemAt: toURL, options: .forReplacing, error: nil) {
      fromReadingURL, toWritingURL in
      do {
        // Check if source file exists
        if !FileManager.default.fileExists(atPath: fromReadingURL.path) {
          result(fileNotFoundError)
          return
        }
        
        // Create destination directory if needed
        let toDirURL = toWritingURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: toDirURL.path) {
          try FileManager.default.createDirectory(at: toDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Remove destination file if it exists
        if FileManager.default.fileExists(atPath: toWritingURL.path) {
          try FileManager.default.removeItem(at: toWritingURL)
        }
        
        // Copy the file
        try FileManager.default.copyItem(at: fromReadingURL, to: toWritingURL)
        result(nil)
      } catch {
        DebugHelper.log("copy error: \(error.localizedDescription)")
        result(nativeCodeError(error))
      }
    }
  }
  
  private func removeObservers(_ query: NSMetadataQuery) {
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidUpdate, object: query)
  }
  
  private func createEventChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    let streamHandler = StreamHandler()
    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: self.messenger!)
    eventChannel.setStreamHandler(streamHandler)
    self.streamHandlers[eventChannelName] = streamHandler
    
    result(nil)
  }
  
  private func removeStreamHandler(_ eventChannelName: String) {
    self.streamHandlers[eventChannelName] = nil
  }
  
  let argumentError = FlutterError(code: "E_ARG", message: "Invalid Arguments", details: nil)
  let containerError = FlutterError(code: "E_CTR", message: "Invalid containerId, or user is not signed in, or user disabled iCloud permission", details: nil)
  let fileNotFoundError = FlutterError(code: "E_FNF", message: "The file does not exist", details: nil)
  
  private func nativeCodeError(_ error: Error) -> FlutterError {
    return FlutterError(code: "E_NAT", message: "Native Code Error", details: "\(error)")
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private var _eventSink: FlutterEventSink?
  var onCancelHandler: (() -> Void)?
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    _eventSink = events
    DebugHelper.log("on listen")
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelHandler?()
    _eventSink = nil
    DebugHelper.log("on cancel")
    return nil
  }
  
  func setEvent(_ data: Any) {
    _eventSink?(data)
  }
}

class DebugHelper {
  public static func log(_ message: String) {
    #if DEBUG
    print(message)
    #endif
  }
}
