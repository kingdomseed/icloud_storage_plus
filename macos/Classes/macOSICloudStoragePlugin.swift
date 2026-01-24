import Cocoa
import FlutterMacOS

public class ICloudStoragePlugin: NSObject, FlutterPlugin {
  var listStreamHandler: StreamHandler?
  var messenger: FlutterBinaryMessenger?
  var streamHandlers: [String: StreamHandler] = [:]
  let querySearchScopes = [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope];
  private var queryObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
  private let queryMetadataItemTimeoutSeconds = 30
  private let queryMetadataItemWarningSeconds = 10

  /// Registers the plugin with the Flutter registrar.
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "icloud_storage_plus", binaryMessenger: registrar.messenger)
    let instance = ICloudStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.messenger = registrar.messenger
  }

  /// Routes Flutter method calls to native handlers.
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "icloudAvailable":
      icloudAvailable(result)
    case "gather":
      gather(call, result)
    case "uploadFile":
      uploadFile(call, result)
    case "downloadFile":
      downloadFile(call, result)
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
  /// Returns whether iCloud is available for the current user.
  private func icloudAvailable(_ result: @escaping FlutterResult) {
    let status = FileManager.default.ubiquityIdentityToken != nil
    result(status)
  }

  /// Returns the filesystem path for the iCloud container.
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
  
  /// Lists all items in the container using NSMetadataQuery.
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
      guard let streamHandler = self.streamHandlers[eventChannelName] else {
        result(FlutterError(code: "E_NO_HANDLER", message: "Event channel '\(eventChannelName)' not created. Call createEventChannel first.", details: nil))
        return
      }
      streamHandler.onCancelHandler = { [self] in
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
    }
    query.start()
  }
  
  /// Adds observers for metadata gather and update notifications.
  private func addGatherFilesObservers(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [self] _ in
      let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
      removeObservers(query)
      if eventChannelName.isEmpty { query.stop() }
      result(files)
    }
    
    if !eventChannelName.isEmpty {
      addObserver(
        for: query,
        name: NSNotification.Name.NSMetadataQueryDidUpdate
      ) { [self] _ in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        guard let streamHandler = self.streamHandlers[eventChannelName] else {
          DebugHelper.log("Warning: streamHandler not found for \(eventChannelName) in gather update")
          return
        }
        streamHandler.setEvent(files)
      }
    }
  }
  
  /// Maps query results into metadata dictionaries.
  private func mapFileAttributesFromQuery(query: NSMetadataQuery, containerURL: URL) -> [[String: Any?]] {
    var fileMaps: [[String: Any?]] = []
    for item in query.results {
      guard let fileItem = item as? NSMetadataItem else { continue }
      guard let map = mapMetadataItem(fileItem, containerURL: containerURL) else {
        continue
      }
      fileMaps.append(map)
    }
    return fileMaps
  }

  /// Map an NSMetadataItem into a Flutter-friendly metadata dictionary.
  /// Includes directories and sets `isDirectory` for caller interpretation.
  private func mapMetadataItem(_ item: NSMetadataItem, containerURL: URL) -> [String: Any?]? {
    guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
      return nil
    }

    return [
      "relativePath": relativePath(for: fileURL, containerURL: containerURL),
      "isDirectory": fileURL.hasDirectoryPath,
      "sizeInBytes": item.value(forAttribute: NSMetadataItemFSSizeKey),
      "creationDate": (item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date)?.timeIntervalSince1970,
      "contentChangeDate": (item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date)?.timeIntervalSince1970,
      "hasUnresolvedConflicts": (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) ?? false,
      "downloadStatus": item.value(
        forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
      ) as? String,
      "isDownloading": (item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool) ?? false,
      "isUploaded": (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) ?? false,
      "isUploading": (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool) ?? false,
    ]
  }

  /// Computes the container-relative path for a URL.
  private func relativePath(for fileURL: URL, containerURL: URL) -> String {
    let containerPath = containerURL.standardizedFileURL.path
    let filePath = fileURL.standardizedFileURL.path
    guard filePath.hasPrefix(containerPath) else {
      return fileURL.lastPathComponent
    }
    var relative = String(filePath.dropFirst(containerPath.count))
    if relative.hasPrefix("/") {
      relative.removeFirst()
    }
    return relative
  }
  
  /// Uploads a local file into the iCloud container.
  private func uploadFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let cloudRelativePath = args["cloudRelativePath"] as? String,
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
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudRelativePath)
    let localFileURL = URL(fileURLWithPath: localFilePath)

    do {
      // Create parent directories if needed
      let cloudFileDirURL = cloudFileURL.deletingLastPathComponent()
      if !FileManager.default.fileExists(atPath: cloudFileDirURL.path) {
        try FileManager.default.createDirectory(
          at: cloudFileDirURL,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }

      writeDocument(at: cloudFileURL, sourceURL: localFileURL) { error in
        if let error = error {
          result(self.nativeCodeError(error))
        } else {
          // Set up progress monitoring if needed
          if !eventChannelName.isEmpty {
            self.setupUploadProgressMonitoring(
              cloudFileURL: cloudFileURL,
              eventChannelName: eventChannelName
            )
          }
          result(nil)
        }
      }
    } catch {
      result(nativeCodeError(error))
    }
  }
  
  /// Starts a metadata query to report upload progress.
  private func setupUploadProgressMonitoring(cloudFileURL: URL, eventChannelName: String) {
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)

    guard let uploadStreamHandler = self.streamHandlers[eventChannelName] else {
      DebugHelper.log("Warning: streamHandler not found for \(eventChannelName) in upload monitoring")
      return
    }
    uploadStreamHandler.onCancelHandler = { [self] in
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
    }
    addUploadObservers(query: query, eventChannelName: eventChannelName)

    query.start()
  }
  
  /// Adds observers for upload progress updates.
  private func addUploadObservers(query: NSMetadataQuery, eventChannelName: String) {
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [self] notification in
      onUploadQueryNotification(
        notification: notification,
        query: query,
        eventChannelName: eventChannelName
      )
    }
    
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidUpdate
    ) { [self] notification in
      onUploadQueryNotification(
        notification: notification,
        query: query,
        eventChannelName: eventChannelName
      )
    }
  }
  
  /// Emits upload progress updates to the event channel.
  private func onUploadQueryNotification(
    notification: Notification,
    query: NSMetadataQuery,
    eventChannelName: String
  ) {
    if !query.isStarted {
      return
    }

    if query.results.count == 0 {
      // `NSMetadataQuery` can send update notifications with no results while the
      // query is still gathering. Only treat it as terminal when the initial
      // gathering finished and we still have no match.
      if notification.name == NSNotification.Name.NSMetadataQueryDidFinishGathering {
        self.streamHandlers[eventChannelName]?.setEvent(FlutterEndOfEventStream)
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemUploadingErrorKey]) else { return}
    guard let streamHandler = self.streamHandlers[eventChannelName] else { return }
    
    if let error = fileURLValues.ubiquitousItemUploadingError {
      streamHandler.setEvent(nativeCodeError(error))
      streamHandler.setEvent(FlutterEndOfEventStream)
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double {
      streamHandler.setEvent(progress)
      if (progress >= 100) {
        streamHandler.setEvent(FlutterEndOfEventStream)
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
    }
  }
  
  /// Downloads a remote item to a local file, optionally reporting progress.
  private func downloadFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let cloudRelativePath = args["cloudRelativePath"] as? String,
          let localFilePath = args["localFilePath"] as? String,
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
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudRelativePath)
    let localFileURL = URL(fileURLWithPath: localFilePath)
    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: cloudFileURL)
    } catch {
      result(nativeCodeError(error))
      return
    }
    
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
    
    var didComplete = false
    let completeOnce: (Any?) -> Void = { value in
      if didComplete {
        return
      }
      didComplete = true
      result(value)
    }

    let downloadStreamHandler = self.streamHandlers[eventChannelName]
    downloadStreamHandler?.onCancelHandler = { [self] in
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
      completeOnce(
        FlutterError(
          code: "E_CANCEL",
          message: "Download canceled",
          details: nil
        )
      )
    }

    addDownloadObservers(
      query: query,
      localFileURL: localFileURL,
      eventChannelName: eventChannelName,
      completeOnce
    )
    
    query.start()
  }
  
  /// Adds observers for download progress updates.
  private func addDownloadObservers(
    query: NSMetadataQuery,
    localFileURL: URL,
    eventChannelName: String,
    _ result: @escaping FlutterResult
  ) {
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [self] _ in
      onDownloadQueryNotification(
        query: query,
        localFileURL: localFileURL,
        eventChannelName: eventChannelName,
        result
      )
    }
    
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidUpdate
    ) { [self] _ in
      onDownloadQueryNotification(
        query: query,
        localFileURL: localFileURL,
        eventChannelName: eventChannelName,
        result
      )
    }
  }
  
  /// Emits download progress and completion updates.
  private func onDownloadQueryNotification(
    query: NSMetadataQuery,
    localFileURL: URL,
    eventChannelName: String,
    _ result: @escaping FlutterResult
  ) {
    if !query.isStarted {
      return
    }
    let streamHandler = self.streamHandlers[eventChannelName]
    if query.results.count == 0 {
      streamHandler?.setEvent(FlutterEndOfEventStream)
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
      result(
        FlutterError(
          code: "E_FNF",
          message: "File not found in iCloud",
          details: nil
        )
      )
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey, .ubiquitousItemDownloadingStatusKey]) else { return }
    if let error = fileURLValues.ubiquitousItemDownloadingError {
      streamHandler?.setEvent(nativeCodeError(error))
      streamHandler?.setEvent(FlutterEndOfEventStream)
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
      result(nativeCodeError(error))
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
      streamHandler?.setEvent(progress)
    }
    
    if fileURLValues.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
      readDocumentAt(url: fileURL, destinationURL: localFileURL) { error in
        if let error = error {
          streamHandler?.setEvent(nativeCodeError(error))
          removeObservers(query)
          query.stop()
          removeStreamHandler(eventChannelName)
          result(self.nativeCodeError(error))
          return
        }

        streamHandler?.setEvent(FlutterEndOfEventStream)
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
        result(nil)
      }
    }
  }
  
  /// Check if an item exists without downloading.
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
    
    queryMetadataItem(containerURL: containerURL, relativePath: relativePath) { item, didTimeout in
      // For documentExists, timeout is treated the same as "not found" (both return false)
      result(item != nil)
    }
  }

  /// Get file or directory metadata without downloading content.
  /// Returns a map that includes `isDirectory` when the item exists.
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

    queryMetadataItem(containerURL: containerURL, relativePath: relativePath) { item, didTimeout in
      // Check for timeout
      if didTimeout {
        result(self.queryTimeoutError)
        return
      }

      guard let item = item else {
        result(nil)
        return
      }
      result(self.mapMetadataItem(item, containerURL: containerURL))
    }
  }

  /// Runs a metadata query for a single item path with timeout protection.
  /// - Parameters:
  ///   - containerURL: The iCloud container URL
  ///   - relativePath: The relative path of the item to query
  ///   - completion: Called with (item, didTimeout) where item is the metadata item or nil, and didTimeout indicates if the query timed out
  private func queryMetadataItem(
    containerURL: URL,
    relativePath: String,
    completion: @escaping (NSMetadataItem?, Bool) -> Void
  ) {
    let query = NSMetadataQuery()
    query.operationQueue = .main
    query.searchScopes = querySearchScopes

    let fileURL = containerURL.appendingPathComponent(relativePath)
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, fileURL.path)

    // State tracking for race condition prevention
    var hasCompleted = false
    var observer: NSObjectProtocol?
    var warningTimer: DispatchSourceTimer?
    var timeoutTimer: DispatchSourceTimer?

    // Resource cleanup helper (called from success, timeout, and warning paths)
    let cleanup = {
      guard !hasCompleted else { return }
      hasCompleted = true

      query.disableUpdates()
      query.stop()

      if let observer = observer {
        NotificationCenter.default.removeObserver(observer)
      }

      if let timer = warningTimer {
        timer.cancel()
      }

      if let timer = timeoutTimer {
        timer.cancel()
      }
    }

    // Set up notification observer
    observer = NotificationCenter.default.addObserver(
      forName: NSNotification.Name.NSMetadataQueryDidFinishGathering,
      object: query,
      queue: query.operationQueue
    ) { _ in
      guard !hasCompleted else { return }
      cleanup()

      if query.resultCount > 0,
         let item = query.result(at: 0) as? NSMetadataItem {
        completion(item, false)  // Found item, not a timeout
      } else {
        completion(nil, false)  // No item found, but query completed (not a timeout)
      }
    }

    // Set up warning timer (fires at 10 seconds)
    let warning = DispatchSource.makeTimerSource(queue: .main)
    warning.schedule(deadline: .now() + .seconds(queryMetadataItemWarningSeconds))
    warning.setEventHandler {
      guard !hasCompleted else { return }
      DebugHelper.log("queryMetadataItem taking longer than expected (\(self.queryMetadataItemWarningSeconds)s): \(relativePath)")
      // Note: This can be surfaced to the UI layer via logging or custom notifications
    }
    warningTimer = warning
    warning.resume()

    // Set up timeout timer (fires at 30 seconds)
    let timeout = DispatchSource.makeTimerSource(queue: .main)
    timeout.schedule(deadline: .now() + .seconds(queryMetadataItemTimeoutSeconds))
    timeout.setEventHandler { [weak query] in
      guard !hasCompleted else { return }
      cleanup()

      DebugHelper.log("queryMetadataItem timed out after \(self.queryMetadataItemTimeoutSeconds)s: \(relativePath)")
      completion(nil, true)  // Return nil with timeout flag
    }

    timeoutTimer = timeout
    timeout.resume()
    query.start()
  }
  
  /// Moves a file by copying and removing the original.
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
  
  /// Deletes an item from the container with coordination.
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

    queryMetadataItem(containerURL: containerURL, relativePath: cloudFileName) { item, didTimeout in
      // Check for timeout
      if didTimeout {
        result(self.queryTimeoutError)
        return
      }

      guard let item = item,
            let itemURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
        result(fileNotFoundError)
        return
      }

      let fileCoordinator = NSFileCoordinator(filePresenter: nil)
      fileCoordinator.coordinate(
        writingItemAt: itemURL,
        options: NSFileCoordinator.WritingOptions.forDeleting,
        error: nil
      ) { writingURL in
        do {
          try FileManager.default.removeItem(at: writingURL)
          result(nil)
        } catch {
          DebugHelper.log("error: \(error.localizedDescription)")
          result(nativeCodeError(error))
        }
      }
    }
  }
  
  /// Moves an item within the container.
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

    queryMetadataItem(containerURL: containerURL, relativePath: atRelativePath) { item, didTimeout in
      // Check for timeout
      if didTimeout {
        result(self.queryTimeoutError)
        return
      }

      guard let item = item,
            let atURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
        result(fileNotFoundError)
        return
      }

      let toURL = containerURL.appendingPathComponent(toRelativePath)
      let fileCoordinator = NSFileCoordinator(filePresenter: nil)
      fileCoordinator.coordinate(
        writingItemAt: atURL,
        options: NSFileCoordinator.WritingOptions.forMoving,
        writingItemAt: toURL,
        options: NSFileCoordinator.WritingOptions.forReplacing,
        error: nil
      ) { atWritingURL, toWritingURL in
        do {
          let toDirURL = toWritingURL.deletingLastPathComponent()
          if !FileManager.default.fileExists(atPath: toDirURL.path) {
            try FileManager.default.createDirectory(
              at: toDirURL,
              withIntermediateDirectories: true,
              attributes: nil
            )
          }
          try FileManager.default.moveItem(at: atWritingURL, to: toWritingURL)
          result(nil)
        } catch {
          DebugHelper.log("error: \(error.localizedDescription)")
          result(nativeCodeError(error))
        }
      }
    }
  }
  
  /// Copies an item within the container.
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
    
    queryMetadataItem(containerURL: containerURL, relativePath: fromRelativePath) { item, didTimeout in
      // Check for timeout
      if didTimeout {
        result(self.queryTimeoutError)
        return
      }

      guard let item = item,
            let fromURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
        result(fileNotFoundError)
        return
      }

      let toURL = containerURL.appendingPathComponent(toRelativePath)
      let fileCoordinator = NSFileCoordinator(filePresenter: nil)
      
      // Use reading coordination for source and writing coordination for destination
      fileCoordinator.coordinate(
        readingItemAt: fromURL,
        options: .withoutChanges,
        writingItemAt: toURL,
        options: .forReplacing,
        error: nil
      ) { fromReadingURL, toWritingURL in
        do {
          // Create destination directory if needed
          let toDirURL = toWritingURL.deletingLastPathComponent()
          if !FileManager.default.fileExists(atPath: toDirURL.path) {
            try FileManager.default.createDirectory(
              at: toDirURL,
              withIntermediateDirectories: true,
              attributes: nil
            )
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
  }
  
  /// Adds an observers for a metadata query.
  private func addObserver(
    for query: NSMetadataQuery,
    name: Notification.Name,
    using block: @escaping (Notification) -> Void
  ) {
    let token = NotificationCenter.default.addObserver(
      forName: name,
      object: query,
      queue: query.operationQueue,
      using: block
    )
    let key = ObjectIdentifier(query)
    var tokens = queryObservers[key] ?? []
    tokens.append(token)
    queryObservers[key] = tokens
  }

  /// Removes all observers for a metadata query.
  private func removeObservers(_ query: NSMetadataQuery) {
    let key = ObjectIdentifier(query)
    guard let tokens = queryObservers[key] else { return }
    for token in tokens {
      NotificationCenter.default.removeObserver(token)
    }
    queryObservers.removeValue(forKey: key)
  }
  
  /// Creates and registers a stream handler for an event channel.
  private func createEventChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }

    guard let messenger = self.messenger else {
      result(initializationError)
      return
    }

    let streamHandler = StreamHandler()
    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(streamHandler)
    self.streamHandlers[eventChannelName] = streamHandler

    result(nil)
  }
  
  /// Removes a stream handler for the given event channel.
  private func removeStreamHandler(_ eventChannelName: String) {
    self.streamHandlers[eventChannelName] = nil
  }
  
  let argumentError = FlutterError(code: "E_ARG", message: "Invalid Arguments", details: nil)
  let containerError = FlutterError(code: "E_CTR", message: "Invalid containerId, or user is not signed in, or user disabled iCloud permission", details: nil)
  let fileNotFoundError = FlutterError(code: "E_FNF", message: "The file does not exist", details: nil)
  let queryTimeoutError = FlutterError(code: "E_TIMEOUT", message: "Metadata query operation timed out after 30 seconds", details: nil)
  let initializationError = FlutterError(code: "E_INIT", message: "Plugin not properly initialized", details: nil)

  /// Wraps a native Error into a FlutterError.
  private func nativeCodeError(_ error: Error) -> FlutterError {
    return FlutterError(code: "E_NAT", message: "Native Code Error", details: "\(error)")
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private var _eventSink: FlutterEventSink?
  var onCancelHandler: (() -> Void)?

  /// Starts listening for events from the native side.
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    _eventSink = events
    DebugHelper.log("on listen")
    return nil
  }

  /// Stops listening for events from the native side.
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelHandler?()
    _eventSink = nil
    DebugHelper.log("on cancel")
    return nil
  }

  /// Emits an event to the Flutter stream.
  func setEvent(_ data: Any) {
    _eventSink?(data)
  }
}

class DebugHelper {
  /// Logs debug output in DEBUG builds.
  public static func log(_ message: String) {
    #if DEBUG
    print(message)
    #endif
  }
}
