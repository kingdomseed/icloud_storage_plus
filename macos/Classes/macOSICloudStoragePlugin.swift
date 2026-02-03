import Cocoa
import FlutterMacOS

public class ICloudStoragePlugin: NSObject, FlutterPlugin {
  var listStreamHandler: StreamHandler?
  var messenger: FlutterBinaryMessenger?
  var streamHandlers: [String: StreamHandler] = [:]
  private var progressByEventChannel: [String: Double] = [:]
  let querySearchScopes = [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope];
  private var queryObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
  private let fileNotFoundReadError = FlutterError(
    code: "E_FNF_READ",
    message: "The file could not be read because it does not exist",
    details: nil
  )
  private let fileNotFoundWriteError = FlutterError(
    code: "E_FNF_WRITE",
    message: "The file could not be written because it does not exist",
    details: nil
  )

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
    case "readInPlace":
      readInPlace(call, result)
    case "readInPlaceBytes":
      readInPlaceBytes(call, result)
    case "writeInPlace":
      writeInPlace(call, result)
    case "writeInPlaceBytes":
      writeInPlaceBytes(call, result)
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

    // Verify event channel handler exists before registering observers
    if !eventChannelName.isEmpty {
      guard let streamHandler = self.streamHandlers[eventChannelName] else {
        result(FlutterError(code: "E_NO_HANDLER", message: "Event channel '\(eventChannelName)' not created. Call createEventChannel first.", details: nil))
        return
      }
    }

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
  
  /// Adds observers for metadata gather and update notifications.
  private func addGatherFilesObservers(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [self] _ in
      let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
      if eventChannelName.isEmpty {
        removeObservers(query)
        query.stop()
      }
      result(files)
    }
    
    if !eventChannelName.isEmpty {
      addObserver(
        for: query,
        name: NSNotification.Name.NSMetadataQueryDidUpdate
      ) { [self] _ in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        guard let streamHandler = self.streamHandlers[eventChannelName] else {
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

  /// Map URL resource values into a Flutter-friendly metadata dictionary.
  private func mapResourceValues(
    fileURL: URL,
    values: URLResourceValues,
    containerURL: URL
  ) -> [String: Any?] {
    return [
      "relativePath": relativePath(for: fileURL, containerURL: containerURL),
      "isDirectory": values.isDirectory ?? false,
      "sizeInBytes": values.fileSize,
      "creationDate": values.creationDate?.timeIntervalSince1970,
      "contentChangeDate": values.contentModificationDate?.timeIntervalSince1970,
      "hasUnresolvedConflicts": values.hasUnresolvedConflicts ?? false,
      "downloadStatus": values.ubiquitousItemDownloadingStatus?.rawValue,
      "isDownloading": values.ubiquitousItemIsDownloading ?? false,
      "isUploaded": values.ubiquitousItemIsUploaded ?? false,
      "isUploading": values.ubiquitousItemIsUploading ?? false,
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
  
  /// Copies a local file into the iCloud container (copy-in).
  /// iCloud uploads the container file automatically in the background.
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
      return
    }
    emitProgress(10.0, eventChannelName: eventChannelName)
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
    ) { [self] _ in
      onUploadQueryNotification(
        query: query,
        eventChannelName: eventChannelName
      )
    }
    
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidUpdate
    ) { [self] _ in
      onUploadQueryNotification(
        query: query,
        eventChannelName: eventChannelName
      )
    }
  }
  
  /// Emits upload progress updates to the event channel.
  private func onUploadQueryNotification(
    query: NSMetadataQuery,
    eventChannelName: String
  ) {
    if !query.isStarted {
      return
    }

    if query.results.count == 0 {
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(
      forKeys: [.ubiquitousItemUploadingErrorKey]
    ) else { return }
    guard self.streamHandlers[eventChannelName] != nil else { return }
    
    if let error = fileURLValues.ubiquitousItemUploadingError {
      guard let streamHandler = self.streamHandlers[eventChannelName] else {
        return
      }
      streamHandler.setEvent(nativeCodeError(error))
      streamHandler.setEvent(FlutterEndOfEventStream)
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double {
      emitProgress(progress, eventChannelName: eventChannelName)
      if (progress >= 100) {
        guard let streamHandler = self.streamHandlers[eventChannelName] else {
          return
        }
        streamHandler.setEvent(FlutterEndOfEventStream)
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
    }
  }
  
  /// Downloads an iCloud item if needed, then copies it out to a local path.
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
      let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
      result(mapped)
      return
    }
    
    var didComplete = false
    let completeOnce: (Any?) -> Void = { value in
      if didComplete {
        return
      }
      didComplete = true
      result(value)
    }

    let query: NSMetadataQuery? = eventChannelName.isEmpty
      ? nil
      : {
          let query = NSMetadataQuery()
          query.operationQueue = .main
          query.searchScopes = querySearchScopes
          query.predicate = NSPredicate(
            format: "%K == %@",
            NSMetadataItemPathKey,
            cloudFileURL.path
          )
          return query
        }()

    let downloadStreamHandler = self.streamHandlers[eventChannelName]
    downloadStreamHandler?.onCancelHandler = { [self] in
      if let query {
        removeObservers(query)
        query.stop()
      }
      removeStreamHandler(eventChannelName)
      completeOnce(
        FlutterError(
          code: "E_CANCEL",
          message: "Download canceled",
          details: nil
        )
      )
    }

    if let query {
      addDownloadObservers(
        query: query,
        eventChannelName: eventChannelName
      )
      query.start()
    }
    if downloadStreamHandler != nil {
      emitProgress(10.0, eventChannelName: eventChannelName)
    }

    readDocumentAt(url: cloudFileURL, destinationURL: localFileURL) { [self] error in
      if didComplete {
        return
      }
      if let error = error {
        let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
        downloadStreamHandler?.setEvent(mapped)
        downloadStreamHandler?.setEvent(FlutterEndOfEventStream)
        if let query {
          removeObservers(query)
          query.stop()
        }
        removeStreamHandler(eventChannelName)
        completeOnce(mapped)
        return
      }

      emitProgress(100.0, eventChannelName: eventChannelName)
      downloadStreamHandler?.setEvent(FlutterEndOfEventStream)
      if let query {
        removeObservers(query)
        query.stop()
      }
      removeStreamHandler(eventChannelName)
      completeOnce(nil)
    }
  }

  /// Read a file in place from the iCloud container using coordinated access.
  private func readInPlace(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
      return
    }

    let idleTimeouts = (args["idleTimeoutSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []
    let retryBackoff = (args["retryBackoffSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []

    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }

    let fileURL = containerURL.appendingPathComponent(relativePath)

    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
    } catch {
      let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
      result(mapped)
      return
    }

    waitForDownloadCompletion(
      fileURL: fileURL,
      idleTimeouts: idleTimeouts,
      retryBackoff: retryBackoff
    ) { [self] error in
      if let error {
        if let timeoutError = mapTimeoutError(error) {
          result(timeoutError)
          return
        }
        result(nativeCodeError(error))
        return
      }

      readInPlaceDocument(at: fileURL) { [self] contents, error in
        if let error = error {
          let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
          result(mapped)
          return
        }

        result(contents)
      }
    }
  }

  /// Write a file in place inside the iCloud container using coordinated access.
  private func writeInPlace(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let contents = args["contents"] as? String
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

    do {
      let dirURL = fileURL.deletingLastPathComponent()
      if !FileManager.default.fileExists(atPath: dirURL.path) {
        try FileManager.default.createDirectory(
          at: dirURL,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }
    } catch {
      result(nativeCodeError(error))
      return
    }

    writeInPlaceDocument(at: fileURL, contents: contents) { [self] error in
      if let error = error {
        let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
        result(mapped)
        return
      }
      result(nil)
    }
  }

  /// Read a file in place as bytes from the iCloud container using coordinated access.
  private func readInPlaceBytes(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
      result(argumentError)
      return
    }

    let idleTimeouts = (args["idleTimeoutSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []
    let retryBackoff = (args["retryBackoffSeconds"] as? [NSNumber])?
      .map { $0.doubleValue } ?? []

    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }

    let fileURL = containerURL.appendingPathComponent(relativePath)

    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
    } catch {
      let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
      result(mapped)
      return
    }

    waitForDownloadCompletion(
      fileURL: fileURL,
      idleTimeouts: idleTimeouts,
      retryBackoff: retryBackoff
    ) { [self] error in
      if let error {
        if let timeoutError = mapTimeoutError(error) {
          result(timeoutError)
          return
        }
        result(nativeCodeError(error))
        return
      }

      readInPlaceBinaryDocument(at: fileURL) { [self] contents, error in
        if let error = error {
          let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
          result(mapped)
          return
        }

        if let contents {
          result(FlutterStandardTypedData(bytes: contents))
        } else {
          result(nil)
        }
      }
    }
  }

  /// Write a file in place as bytes inside the iCloud container using coordinated access.
  private func writeInPlaceBytes(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let contents = args["contents"] as? FlutterStandardTypedData
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

    do {
      let dirURL = fileURL.deletingLastPathComponent()
      if !FileManager.default.fileExists(atPath: dirURL.path) {
        try FileManager.default.createDirectory(
          at: dirURL,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }
    } catch {
      result(nativeCodeError(error))
      return
    }

    writeInPlaceBinaryDocument(at: fileURL, contents: contents.data) { [self] error in
      if let error = error {
        let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
        result(mapped)
        return
      }
      result(nil)
    }
  }
  
  /// Adds observers for download progress updates.
  private func addDownloadObservers(
    query: NSMetadataQuery,
    eventChannelName: String
  ) {
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering
    ) { [self] _ in
      emitDownloadProgress(
        query: query,
        eventChannelName: eventChannelName
      )
    }
    
    addObserver(
      for: query,
      name: NSNotification.Name.NSMetadataQueryDidUpdate
    ) { [self] _ in
      emitDownloadProgress(
        query: query,
        eventChannelName: eventChannelName
      )
    }
  }
  
  /// Emits download progress updates.
  private func emitDownloadProgress(
    query: NSMetadataQuery,
    eventChannelName: String
  ) {
    if !query.isStarted {
      return
    }
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
      emitProgress(progress, eventChannelName: eventChannelName)
    }
  }

  /// Waits for an iCloud download to reach "current" or fail.
  ///
  /// Uses an idle watchdog timer that resets only when download progress
  /// advances. This avoids hard timeouts while still escaping stalled
  /// downloads.
  private func waitForDownloadCompletion(
    fileURL: URL,
    idleTimeouts: [TimeInterval],
    retryBackoff: [TimeInterval],
    completion: @escaping (Error?) -> Void
  ) {
    if let values = try? fileURL.resourceValues(
      forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey]
    ) {
      if let error = values.ubiquitousItemDownloadingError {
        completion(error)
        return
      }
      if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
        completion(nil)
        return
      }
    }

    let idleSchedule = idleTimeouts.isEmpty ? [60, 90, 180] : idleTimeouts
    let backoffSchedule = retryBackoff.isEmpty ? [2, 4] : retryBackoff

    var didComplete = false
    let completeOnce: (Error?) -> Void = { error in
      if didComplete {
        return
      }
      didComplete = true
      completion(error)
    }

    func startAttempt(index: Int) {
      if didComplete { return }
      let query = NSMetadataQuery()
      query.operationQueue = .main
      query.searchScopes = querySearchScopes
      query.predicate = NSPredicate(
        format: "%K == %@",
        NSMetadataItemPathKey,
        fileURL.path
      )

      var watchdogTimer: Timer?
      var lastProgress = -1.0

      let resetWatchdog: () -> Void = {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(
          withTimeInterval: idleSchedule[index],
          repeats: false
        ) { [self] _ in
          removeObservers(query)
          query.stop()
          if index < idleSchedule.count - 1 {
            let delayIndex = min(index, backoffSchedule.count - 1)
            let delay = backoffSchedule[delayIndex]
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
              startAttempt(index: index + 1)
            }
            return
          }
          completeOnce(timeoutNativeError())
        }
      }

      let handleEvaluation: () -> Void = { [self] in
        let evaluation = evaluateDownloadStatus(query: query, fileURL: fileURL)
        if evaluation.completed {
          watchdogTimer?.invalidate()
          removeObservers(query)
          query.stop()
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

      addObserver(
        for: query,
        name: NSNotification.Name.NSMetadataQueryDidFinishGathering
      ) { _ in
        handleEvaluation()
      }

      addObserver(
        for: query,
        name: NSNotification.Name.NSMetadataQueryDidUpdate
      ) { _ in
        handleEvaluation()
      }

      resetWatchdog()
      query.start()
    }

    startAttempt(index: 0)
  }

  /// Checks if the file is fully downloaded and available for access.
  ///
  /// Strategy:
  /// 1) Index check: resolve via `NSMetadataQuery` results (handles recent moves/renames).
  /// 2) Filesystem fallback: if query returns no results, use the original `fileURL`
  ///    to avoid hanging on metadata indexing latency.
  private func evaluateDownloadStatus(
    query: NSMetadataQuery,
    fileURL: URL
  ) -> (completed: Bool, error: Error?) {
    let resolvedURL = (query.results.first as? NSMetadataItem)
      .flatMap { $0.value(forAttribute: NSMetadataItemURLKey) as? URL }
      ?? fileURL
    guard let values = try? resolvedURL.resourceValues(
      forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey]
    ) else {
      return (false, nil)
    }

    if let error = values.ubiquitousItemDownloadingError {
      return (true, error)
    }

    if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
      return (true, nil)
    }
    return (false, nil)
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

    let fileURL = containerURL.appendingPathComponent(relativePath)
    result(FileManager.default.fileExists(atPath: fileURL.path))
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

    let fileURL = containerURL.appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(nil)
      return
    }

    do {
      let values = try fileURL.resourceValues(forKeys: [
        .isDirectoryKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey,
        .ubiquitousItemHasUnresolvedConflictsKey,
      ])
      result(mapResourceValues(
        fileURL: fileURL,
        values: values,
        containerURL: containerURL
      ))
    } catch {
      result(nativeCodeError(error))
    }
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
    DebugHelper.log("containerURL: \(containerURL.path)")

    let fileURL = containerURL.appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(fileNotFoundError)
      return
    }

    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    fileCoordinator.coordinate(
      writingItemAt: fileURL,
      options: NSFileCoordinator.WritingOptions.forDeleting,
      error: nil
    ) { writingURL in
      do {
        try FileManager.default.removeItem(at: writingURL)
        result(nil)
      } catch {
        DebugHelper.log("error: \(error.localizedDescription)")
        let mapped = mapFileNotFoundError(error) ?? nativeCodeError(error)
        result(mapped)
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

    let atURL = containerURL.appendingPathComponent(atRelativePath)
    guard FileManager.default.fileExists(atPath: atURL.path) else {
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
    
    let fromURL = containerURL.appendingPathComponent(fromRelativePath)
    guard FileManager.default.fileExists(atPath: fromURL.path) else {
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
    progressByEventChannel.removeValue(forKey: eventChannelName)
  }

  /// Emits a monotonic progress update to the Flutter stream.
  private func emitProgress(_ progress: Double, eventChannelName: String) {
    guard let streamHandler = streamHandlers[eventChannelName] else { return }
    let lastProgress = progressByEventChannel[eventChannelName] ?? 0
    let clamped = max(progress, lastProgress)
    progressByEventChannel[eventChannelName] = clamped
    streamHandler.setEvent(clamped)
  }
  
  let argumentError = FlutterError(code: "E_ARG", message: "Invalid Arguments", details: nil)
  let containerError = FlutterError(code: "E_CTR", message: "Invalid containerId, or user is not signed in, or user disabled iCloud permission", details: nil)
  let fileNotFoundError = FlutterError(code: "E_FNF", message: "The file does not exist", details: nil)
  let initializationError = FlutterError(code: "E_INIT", message: "Plugin not properly initialized", details: nil)
  let timeoutError = FlutterError(
    code: "E_TIMEOUT",
    message: "The download did not make progress before timing out",
    details: nil
  )

  /// Maps file-not-found errors to specific Flutter error codes.
  private func mapFileNotFoundError(_ error: Error) -> FlutterError? {
    let nsError = error as NSError
    guard nsError.domain == NSCocoaErrorDomain else { return nil }

    switch nsError.code {
    case NSFileNoSuchFileError:
      return fileNotFoundError
    case NSFileReadNoSuchFileError:
      return fileNotFoundReadError
    case NSFileWriteNoSuchFileError:
      return fileNotFoundWriteError
    default:
      return nil
    }
  }

  /// Wraps a native Error into a FlutterError.
  private func nativeCodeError(_ error: Error) -> FlutterError {
    return FlutterError(code: "E_NAT", message: "Native Code Error", details: "\(error)")
  }

  private func timeoutNativeError() -> NSError {
    return NSError(
      domain: "ICloudStorageTimeout",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Download idle timeout"]
    )
  }

  private func mapTimeoutError(_ error: Error) -> FlutterError? {
    let nsError = error as NSError
    guard nsError.domain == "ICloudStorageTimeout" else { return nil }
    return timeoutError
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private var _eventSink: FlutterEventSink?
  var onCancelHandler: (() -> Void)?
  var isCancelled = false

  /// Starts listening for events from the native side.
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    isCancelled = false
    _eventSink = events
    DebugHelper.log("on listen")
    return nil
  }

  /// Stops listening for events from the native side.
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    isCancelled = true
    onCancelHandler?()
    _eventSink = nil
    DebugHelper.log("on cancel")
    return nil
  }

  /// Emits an event to the Flutter stream.
  func setEvent(_ data: Any) {
    if isCancelled { return }
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
