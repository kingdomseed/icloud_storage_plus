# Event Channels and Streaming

<details>
<summary>Relevant source files</summary>

The following files were used as context for generating this wiki page:

- [ios/Classes/iOSICloudStoragePlugin.swift](../../ios/Classes/iOSICloudStoragePlugin.swift)
- [lib/icloud_storage_method_channel.dart](../../lib/icloud_storage_method_channel.dart)
- [macos/Classes/macOSICloudStoragePlugin.swift](../../macos/Classes/macOSICloudStoragePlugin.swift)
- [test/icloud_storage_method_channel_test.dart](../../test/icloud_storage_method_channel_test.dart)

</details>



This document explains how the plugin uses Flutter's `EventChannel` mechanism to stream real-time data from native code to Dart, including progress updates for file transfers and live metadata changes during file system monitoring.

For the overall method channel communication architecture, see [Method Channel Implementation](#4.2). For specific details on progress monitoring behavior, see [Progress Monitoring](#6.1).

---

## Overview of Event Channel Usage

The plugin uses **dynamically created EventChannels** to stream two types of data:

1. **Transfer Progress** - Upload and download progress updates (0-100%) as operations execute
2. **Metadata Updates** - Real-time file list changes when using `gather()` with streaming enabled

Unlike the single static `MethodChannel` used for operations, EventChannels are created on-demand with unique names for each streaming operation. This allows multiple concurrent operations to each have their own progress stream without conflicts.

**Sources:** [lib/icloud_storage_method_channel.dart:27-58](), [lib/icloud_storage_method_channel.dart:69-129](), [ios/Classes/iOSICloudStoragePlugin.swift:5-8]()

---

## EventChannel Creation and Registration

### Dynamic Channel Name Generation

Each EventChannel receives a unique name generated from multiple components to prevent collisions:

| Component | Purpose | Example |
|-----------|---------|---------|
| Prefix | Fixed identifier | `icloud_storage_plus` |
| Type | Event category | `event` |
| Operation | Specific operation | `uploadFile`, `downloadFile`, `gather` |
| Container ID | Scope isolation | `iCloud.com.example.app` |
| Timestamp + Random | Uniqueness guarantee | `1234567890_123` |

**Example Generated Name:**
```
icloud_storage_plus/event/uploadFile/iCloud.com.example.app/1234567890_123
```

**Sources:** [lib/icloud_storage_method_channel.dart:390-405]()

---

### EventChannel Creation Flow

```mermaid
sequenceDiagram
    participant Dart as "Dart Layer<br/>(MethodChannelICloudStorage)"
    participant MC as "MethodChannel<br/>'icloud_storage_plus'"
    participant Plugin as "Native Plugin<br/>(SwiftICloudStoragePlugin)"
    participant Handler as "StreamHandler<br/>(Native)"
    participant EC as "EventChannel<br/>(Dynamic Name)"
    participant App as "Flutter App<br/>(onProgress callback)"

    Note over Dart,App: Setup Phase (before operation)
    
    Dart->>Dart: Generate unique<br/>eventChannelName
    Dart->>MC: invokeMethod('createEventChannel',<br/>{eventChannelName})
    MC->>Plugin: createEventChannel(call, result)
    Plugin->>Handler: new StreamHandler()
    Plugin->>EC: FlutterEventChannel(name, messenger)
    EC->>Handler: setStreamHandler(handler)
    Plugin->>Plugin: streamHandlers[name] = handler
    Plugin-->>MC: result(nil)
    MC-->>Dart: Future completes
    
    Dart->>EC: EventChannel(name)
    Dart->>EC: receiveBroadcastStream()
    Dart->>Dart: Transform stream
    Dart->>App: onProgress(stream)
    
    Note over Dart,App: Operation Phase
    
    Dart->>MC: invokeMethod('uploadFile',<br/>{..., eventChannelName})
    
    Note over Plugin,Handler: Stream is now ready to emit events
```

The critical ordering ensures:
1. **EventChannel exists before operation starts** - prevents missing early events
2. **StreamHandler is registered** - native code can look up handler by name
3. **Stream is passed to app** - caller can attach listener immediately

**Sources:** [lib/icloud_storage_method_channel.dart:78-90](), [ios/Classes/iOSICloudStoragePlugin.swift:1126-1146]()

---

## Native StreamHandler Implementation

### StreamHandler Class Structure

The `StreamHandler` class on the native side implements Flutter's `FlutterStreamHandler` protocol:

```mermaid
classDiagram
    class StreamHandler {
        -FlutterEventSink? _eventSink
        +(() -> Void)? onCancelHandler
        +Bool isCancelled
        
        +onListen(arguments, eventSink) FlutterError?
        +onCancel(arguments) FlutterError?
        +setEvent(data: Any)
    }
    
    class FlutterStreamHandler {
        <<protocol>>
        +onListen(arguments, eventSink) FlutterError?
        +onCancel(arguments) FlutterError?
    }
    
    FlutterStreamHandler <|.. StreamHandler : implements
    
    note for StreamHandler "Manages single event stream lifetime.\nStores event sink for emitting data.\nProvides cleanup hook via onCancelHandler."
```

**Key Responsibilities:**

| Method | Purpose | When Called |
|--------|---------|-------------|
| `onListen` | Stores event sink, marks stream active | When Dart code calls `stream.listen()` |
| `onCancel` | Cleans up resources, invokes cancel handler | When Dart cancels subscription or stream closes |
| `setEvent` | Emits data to Dart stream | Throughout operation lifetime |

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:1210-1237](), [macos/Classes/macOSICloudStoragePlugin.swift:1209-1236]()

---

### StreamHandler Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: new StreamHandler()
    Created --> Registered: setStreamHandler()
    Registered --> Active: onListen() called
    Active --> Emitting: setEvent(data)
    Emitting --> Active: more events
    Emitting --> Closed: setEvent(FlutterEndOfEventStream)
    Active --> Cancelled: onCancel() called
    Closed --> CleanedUp: Remove from streamHandlers
    Cancelled --> CleanedUp: onCancelHandler() invoked
    CleanedUp --> [*]
    
    note right of Active
        _eventSink is set
        isCancelled = false
        Events can flow
    end note
    
    note right of Cancelled
        _eventSink = nil
        isCancelled = true
        onCancelHandler stops queries
    end note
```

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:1214-1236]()

---

## Progress Monitoring via EventChannels

### Upload Progress Flow

Upload progress monitoring uses `NSMetadataQuery` to track the file after it's written to the iCloud container:

```mermaid
graph TB
    subgraph DartLayer["Dart Layer"]
        UploadCall["uploadFile()<br/>(with onProgress)"]
        ProgressStream["Stream&lt;ICloudTransferProgress&gt;"]
        Listener["App Listener"]
    end
    
    subgraph NativeLayer["Native Layer"]
        UploadMethod["uploadFile(call, result)"]
        WriteDoc["writeDocument()<br/>(ICloudDocument)"]
        SetupMonitor["setupUploadProgressMonitoring()"]
        Query["NSMetadataQuery"]
        AddObservers["addUploadObservers()"]
        OnNotification["onUploadQueryNotification()"]
    end
    
    subgraph EventFlow["Event Channel"]
        StreamHandler["StreamHandler"]
        EmitProgress["emitProgress()"]
        EventSink["FlutterEventSink"]
    end
    
    UploadCall -->|1. Create EC| ProgressStream
    UploadCall -->|2. Invoke method| UploadMethod
    UploadMethod -->|3. Write file| WriteDoc
    WriteDoc -->|4. On success| SetupMonitor
    
    SetupMonitor -->|5. Create query| Query
    SetupMonitor -->|6. Setup| AddObservers
    SetupMonitor -->|7. Emit 10%| EmitProgress
    Query -->|8. Start monitoring| Query
    
    Query -.->|NSMetadataQueryDidUpdate| OnNotification
    OnNotification -->|9. Extract percent| EmitProgress
    
    EmitProgress -->|10. Lookup handler| StreamHandler
    StreamHandler -->|11. Call setEvent| EventSink
    EventSink -.->|12. Deliver event| ProgressStream
    ProgressStream -->|13. Transform| Listener
    
    OnNotification -->|On 100%| StreamHandler
    StreamHandler -->|FlutterEndOfEventStream| EventSink
```

**Key Implementation Details:**

1. **Initial Progress** - 10% emitted immediately after file write completes [ios/Classes/iOSICloudStoragePlugin.swift:297]()
2. **Query Creation** - Predicate matches exact file path [ios/Classes/iOSICloudStoragePlugin.swift:292]()
3. **Observer Registration** - Listens to `DidFinishGathering` and `DidUpdate` notifications [ios/Classes/iOSICloudStoragePlugin.swift:309-328]()
4. **Progress Extraction** - `NSMetadataUbiquitousItemPercentUploadedKey` provides 0-100 value [ios/Classes/iOSICloudStoragePlugin.swift:363-364]()
5. **Monotonic Guarantee** - Progress can only increase, never decrease [ios/Classes/iOSICloudStoragePlugin.swift:1154-1160]()

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:236-285](), [ios/Classes/iOSICloudStoragePlugin.swift:287-306](), [ios/Classes/iOSICloudStoragePlugin.swift:309-375]()

---

### Download Progress Flow

Download progress follows a similar pattern but monitors download status instead:

```mermaid
sequenceDiagram
    participant App as "Flutter App"
    participant Dart as "MethodChannelICloudStorage"
    participant Native as "downloadFile()"
    participant Query as "NSMetadataQuery"
    participant Handler as "StreamHandler"
    
    App->>Dart: downloadFile(onProgress: ...)
    Dart->>Dart: Create EventChannel
    Dart->>App: onProgress(stream)
    Dart->>Native: invokeMethod('downloadFile')
    
    Native->>Native: startDownloadingUbiquitousItem()
    
    alt onProgress provided
        Native->>Query: Create query for file
        Native->>Query: addDownloadObservers()
        Native->>Handler: emitProgress(10.0)
        Handler-->>App: Stream: 10%
        Native->>Query: query.start()
    end
    
    Native->>Native: readDocumentAt() (async)
    
    loop Query notifications
        Query->>Native: NSMetadataQueryDidUpdate
        Native->>Native: Extract percentDownloaded
        Native->>Handler: emitProgress(percent)
        Handler-->>App: Stream: percent%
    end
    
    Native->>Native: readDocumentAt completes
    Native->>Handler: emitProgress(100.0)
    Handler-->>App: Stream: 100%
    Native->>Handler: setEvent(FlutterEndOfEventStream)
    Handler-->>App: Stream: done
    Native-->>Dart: Future completes
```

**Progress Attribute:** `NSMetadataUbiquitousItemPercentDownloadedKey` [ios/Classes/iOSICloudStoragePlugin.swift:723]()

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:377-482](), [ios/Classes/iOSICloudStoragePlugin.swift:688-726]()

---

### Progress Emission Details

The `emitProgress` function enforces monotonic progress and prevents duplicate events:

```mermaid
graph TD
    EmitCall["emitProgress(progress, eventChannelName)"]
    LookupHandler{"streamHandler<br/>exists?"}
    GetLast["lastProgress = progressByEventChannel[name] ?? 0"]
    Clamp["clamped = max(progress, lastProgress)"]
    Store["progressByEventChannel[name] = clamped"]
    Emit["streamHandler.setEvent(clamped)"]
    Return["return"]
    
    EmitCall --> LookupHandler
    LookupHandler -->|No| Return
    LookupHandler -->|Yes| GetLast
    GetLast --> Clamp
    Clamp --> Store
    Store --> Emit
    Emit --> Return
```

**Monotonic Progress Logic:**
- Stores last emitted progress per channel in `progressByEventChannel` dictionary
- New progress is clamped to `max(new, last)` to prevent backwards movement
- Protects against query race conditions or out-of-order notifications

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:1154-1161]()

---

## Metadata Update Streaming

### Gather with Real-Time Updates

The `gather()` operation can optionally stream updates when files change in the container:

```mermaid
graph TB
    subgraph Setup["Initial Setup"]
        GatherCall["gather(containerId,<br/>onUpdate: ...)"]
        CreateEC["createEventChannel"]
        SetupQuery["NSMetadataQuery"]
    end
    
    subgraph Observers["Observer Registration"]
        DidFinishGathering["NSMetadataQueryDidFinishGathering"]
        DidUpdate["NSMetadataQueryDidUpdate"]
    end
    
    subgraph EventEmission["Event Emission"]
        MapFiles["mapFileAttributesFromQuery()"]
        EmitInitial["result(files) - Future"]
        EmitUpdates["streamHandler.setEvent(files)"]
    end
    
    subgraph Lifecycle["Lifecycle Management"]
        OnCancel["onCancelHandler"]
        RemoveObservers["removeObservers()"]
        StopQuery["query.stop()"]
        Cleanup["removeStreamHandler()"]
    end
    
    GatherCall --> CreateEC
    CreateEC --> SetupQuery
    SetupQuery --> DidFinishGathering
    SetupQuery --> DidUpdate
    
    DidFinishGathering --> MapFiles
    MapFiles --> EmitInitial
    
    DidUpdate --> MapFiles
    MapFiles --> EmitUpdates
    
    EmitUpdates -.->|App cancels| OnCancel
    OnCancel --> RemoveObservers
    RemoveObservers --> StopQuery
    StopQuery --> Cleanup
```

**Key Differences from Progress Monitoring:**

| Aspect | Progress Streams | Metadata Streams |
|--------|-----------------|------------------|
| **Data Type** | `Double` (0-100) | `List<Map>` (file metadata) |
| **Frequency** | On query updates | On file system changes |
| **Completion** | Automatic at 100% | Continues until cancelled |
| **Initial Event** | Via `result()` callback | Via `result()` callback |
| **Subsequent Events** | Via EventChannel | Via EventChannel |

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:94-162](), [macos/Classes/macOSICloudStoragePlugin.swift:94-162]()

---

## Event Transformation on Dart Side

### Raw Event to ICloudTransferProgress

The Dart side transforms raw EventChannel data into type-safe `ICloudTransferProgress` objects:

```mermaid
graph TD
    RawStream["EventChannel.receiveBroadcastStream()"]
    Transformer["StreamTransformer"]
    
    subgraph HandleData["handleData(event, sink)"]
        CheckNum{"event is num?"}
        EmitProgress["sink.add(ICloudTransferProgress.progress())"]
        CreateException["Create E_INVALID_EVENT exception"]
        EmitError["sink.add(ICloudTransferProgress.error())"]
        Close["sink.close()"]
    end
    
    subgraph HandleError["handleError(error, stack, sink)"]
        IsPlatform{"error is<br/>PlatformException?"}
        WrapError["Wrap in E_PLUGIN_INTERNAL"]
        EmitWrapped["sink.add(ICloudTransferProgress.error())"]
        CloseErr["sink.close()"]
    end
    
    subgraph HandleDone["handleDone(sink)"]
        EmitDone["sink.add(ICloudTransferProgress.done())"]
        CloseDone["sink.close()"]
    end
    
    RawStream --> Transformer
    
    Transformer -->|Data| CheckNum
    CheckNum -->|Yes| EmitProgress
    CheckNum -->|No| CreateException
    CreateException --> EmitError
    EmitError --> Close
    
    Transformer -->|Error| IsPlatform
    IsPlatform -->|Yes| EmitWrapped
    IsPlatform -->|No| WrapError
    WrapError --> EmitWrapped
    EmitWrapped --> CloseErr
    
    Transformer -->|Done| EmitDone
    EmitDone --> CloseDone
```

**Important:** Errors are delivered as **data events** with `type: error`, not as stream errors. This design choice ensures:
- Errors don't terminate the stream unexpectedly
- App can handle errors inline with progress updates
- Single listener pattern works correctly

**Sources:** [lib/icloud_storage_method_channel.dart:286-336]()

---

### ICloudTransferProgress Event Types

The transformed stream emits three types of events:

```mermaid
classDiagram
    class ICloudTransferProgress {
        +ICloudTransferProgressType type
        +double? percent
        +PlatformException? exception
        +bool isProgress
        +bool isError
        +bool isDone
    }
    
    class ICloudTransferProgressType {
        <<enumeration>>
        progress
        error
        done
    }
    
    ICloudTransferProgress --> ICloudTransferProgressType
    
    note for ICloudTransferProgress "All events delivered as data, never as stream errors.\nCheck 'type' or boolean helpers to determine event kind."
```

**Usage Pattern:**
```dart
onProgress: (stream) {
  stream.listen((event) {
    if (event.isProgress) {
      print('Progress: ${event.percent}%');
    } else if (event.isError) {
      print('Error: ${event.exception}');
    } else if (event.isDone) {
      print('Complete');
    }
  });
}
```

**Sources:** [lib/models/transfer_progress.dart](), [lib/icloud_storage_method_channel.dart:291-305]()

---

## Observer Management and Cleanup

### Observer Registration Pattern

The plugin tracks all notification observers per query to ensure proper cleanup:

```mermaid
graph LR
    subgraph Registration["addObserver()"]
        AddCall["addObserver(query, name, block)"]
        Subscribe["NotificationCenter.addObserver()"]
        GetToken["token: NSObjectProtocol"]
        GetKey["key = ObjectIdentifier(query)"]
        StoreToken["queryObservers[key].append(token)"]
    end
    
    subgraph Cleanup["removeObservers()"]
        RemoveCall["removeObservers(query)"]
        GetKey2["key = ObjectIdentifier(query)"]
        GetTokens["tokens = queryObservers[key]"]
        RemoveLoop["For each token:<br/>NotificationCenter.removeObserver(token)"]
        RemoveEntry["queryObservers.removeValue(key)"]
    end
    
    AddCall --> Subscribe
    Subscribe --> GetToken
    GetToken --> GetKey
    GetKey --> StoreToken
    
    RemoveCall --> GetKey2
    GetKey2 --> GetTokens
    GetTokens --> RemoveLoop
    RemoveLoop --> RemoveEntry
```

**Data Structure:**
- `queryObservers: [ObjectIdentifier: [NSObjectProtocol]]` - Maps query to its observer tokens
- Each query may have multiple observers (e.g., DidFinishGathering + DidUpdate)
- All observers removed atomically when query stops

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:1098-1124](), [macos/Classes/macOSICloudStoragePlugin.swift:1097-1123]()

---

### Cancel Handler Flow

When a stream is cancelled, cleanup occurs through the cancel handler:

```mermaid
sequenceDiagram
    participant App as "Flutter App"
    participant Stream as "Dart Stream"
    participant Handler as "StreamHandler<br/>(Native)"
    participant Cancel as "onCancelHandler<br/>(Closure)"
    participant Query as "NSMetadataQuery"
    participant Plugin as "Plugin"
    
    App->>Stream: subscription.cancel()
    Stream->>Handler: onCancel(arguments)
    Handler->>Handler: isCancelled = true
    Handler->>Cancel: Invoke closure
    
    alt Upload/Download Progress
        Cancel->>Query: removeObservers()
        Cancel->>Query: query.stop()
        Cancel->>Plugin: removeStreamHandler(name)
    end
    
    alt Gather Streaming
        Cancel->>Query: removeObservers()
        Cancel->>Query: query.stop()
        Cancel->>Plugin: removeStreamHandler(name)
    end
    
    Handler->>Handler: _eventSink = nil
    Handler-->>Stream: FlutterError? (nil)
```

**Cancel Handler Setup Examples:**

**Upload Progress:** [ios/Classes/iOSICloudStoragePlugin.swift:298-302]()
```swift
uploadStreamHandler.onCancelHandler = { [self] in
  removeObservers(query)
  query.stop()
  removeStreamHandler(eventChannelName)
}
```

**Gather Streaming:** [ios/Classes/iOSICloudStoragePlugin.swift:127-131]()
```swift
streamHandler.onCancelHandler = { [self] in
  removeObservers(query)
  query.stop()
  removeStreamHandler(eventChannelName)
}
```

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:1223-1229]()

---

## StreamHandler Dictionary Management

The plugin maintains a registry of active stream handlers:

```mermaid
graph TD
    subgraph PluginState["Plugin State"]
        StreamHandlers["streamHandlers: [String: StreamHandler]"]
        ProgressTracking["progressByEventChannel: [String: Double]"]
    end
    
    subgraph Lifecycle["Handler Lifecycle"]
        Create["createEventChannel()"]
        Register["streamHandlers[name] = handler"]
        Use["Operations emit events via handler"]
        Remove["removeStreamHandler(name)"]
        Cleanup["streamHandlers[name] = nil<br/>progressByEventChannel[name] = nil"]
    end
    
    StreamHandlers -.->|Storage| Create
    Create --> Register
    Register --> Use
    Use --> Remove
    Remove --> Cleanup
    Cleanup -.->|Update| StreamHandlers
    Cleanup -.->|Clear| ProgressTracking
```

**Key Methods:**

| Method | Purpose | When Called |
|--------|---------|-------------|
| `createEventChannel()` | Creates and registers handler | Before operation starts |
| `removeStreamHandler()` | Removes handler and progress state | Operation completes or is cancelled |
| `emitProgress()` | Looks up handler to emit event | During operation |

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:1126-1152](), [ios/Classes/iOSICloudStoragePlugin.swift:1148-1161]()

---

## Error Handling in Event Streams

### Native Error Emission

When errors occur during streaming operations, they're emitted as events:

```mermaid
graph TD
    ErrorOccurs["Error occurs in<br/>NSMetadataQuery notification"]
    CheckType{"Error type?"}
    
    UploadError["ubiquitousItemUploadingError"]
    NativeCodeError["nativeCodeError(error)"]
    EmitError["streamHandler.setEvent(error)"]
    EmitEnd["streamHandler.setEvent(FlutterEndOfEventStream)"]
    Cleanup["Stop query, remove handler"]
    
    ErrorOccurs --> CheckType
    CheckType -->|Upload error| UploadError
    CheckType -->|Other| NativeCodeError
    
    UploadError --> EmitError
    NativeCodeError --> EmitError
    EmitError --> EmitEnd
    EmitEnd --> Cleanup
```

**Upload Error Example:** [ios/Classes/iOSICloudStoragePlugin.swift:351-360]()

**Download Error Example:** [ios/Classes/iOSICloudStoragePlugin.swift:460-470]()

**Sources:** [ios/Classes/iOSICloudStoragePlugin.swift:351-375](), [ios/Classes/iOSICloudStoragePlugin.swift:456-481]()

---

### Dart Error Transformation

Errors flow through the transformer and become error progress events:

```mermaid
graph LR
    subgraph NativeError["Native Error Event"]
        PlatformError["PlatformException<br/>(via setEvent)"]
    end
    
    subgraph Transformer["Stream Transformer"]
        HandleError["handleError(error, stack, sink)"]
        CheckPlatform{"Is PlatformException?"}
        Wrap["Wrap as E_PLUGIN_INTERNAL"]
        CreateProgress["ICloudTransferProgress.error(exception)"]
    end
    
    subgraph AppReceives["App Receives"]
        DataEvent["stream.listen((event) => ...)"]
        CheckType["if (event.isError)"]
        HandleAppError["Handle error"]
    end
    
    PlatformError --> HandleError
    HandleError --> CheckPlatform
    CheckPlatform -->|Yes| CreateProgress
    CheckPlatform -->|No| Wrap
    Wrap --> CreateProgress
    CreateProgress --> DataEvent
    DataEvent --> CheckType
    CheckType --> HandleAppError
```

**Critical Design Decision:** Errors are data events, not stream errors, because:
1. Stream errors terminate the stream
2. Progress operations emit multiple events over time
3. App needs to handle errors without losing stream
4. Consistent with Flutter plugin patterns

**Sources:** [lib/icloud_storage_method_channel.dart:306-327]()

---

## Testing EventChannel Behavior

### Mock StreamHandler for Tests

The test suite uses `MockStreamHandler` to simulate native event emission:

```mermaid
classDiagram
    class MockStreamHandler {
        +onListen(arguments, events)
        +success(data)
        +error(code, message, details)
        +endOfStream()
    }
    
    class MockStreamHandlerEvents {
        +success(data)
        +error(code, message, details)
        +endOfStream()
    }
    
    MockStreamHandler --> MockStreamHandlerEvents : provides
    
    note for MockStreamHandler "Test implementation that emits events\nwhen onListen is called.\nAllows synchronous event testing."
```

**Test Example - Progress Events:** [test/icloud_storage_method_channel_test.dart:297-325]()
```dart
mockStreamHandler = MockStreamHandler.inline(
  onListen: (arguments, events) {
    events
      ..success(0.25)
      ..success(1.0)
      ..endOfStream();
  },
);

await platform.uploadFile(
  containerId: containerId,
  localPath: '/dir/file',
  cloudRelativePath: 'dest',
  onProgress: (stream) {
    progressStream = stream;
  },
);

final events = await progressStream.toList();
expect(events[0].percent, 0.25);
expect(events[1].percent, 1.0);
expect(events[2].isDone, isTrue);
```

**Test Example - Error Events:** [test/icloud_storage_method_channel_test.dart:327-356]()

**Sources:** [test/icloud_storage_method_channel_test.dart:296-384]()

---

## Stream Subscription Timing

### Lazy Stream Creation

EventChannel streams use lazy subscription - events only flow when a listener attaches:

```mermaid
sequenceDiagram
    participant App as "Flutter App"
    participant Dart as "Dart API"
    participant Native as "Native Plugin"
    
    Note over App,Native: Phase 1: Setup (before listen)
    
    App->>Dart: uploadFile(onProgress: (stream) => ...)
    Dart->>Native: createEventChannel
    Native->>Native: Create StreamHandler
    Native-->>Dart: Handler ready
    Dart->>Dart: eventChannel.receiveBroadcastStream()
    Dart->>App: onProgress(stream)
    
    Note over App,Native: Phase 2: Activation (on listen)
    
    App->>Dart: stream.listen(...)
    Dart->>Native: StreamHandler.onListen()
    Native->>Native: _eventSink = events
    Note over Native: Now ready to emit
    
    Dart->>Native: invokeMethod('uploadFile')
    
    Note over App,Native: Phase 3: Event Flow
    
    Native->>Native: Operation progresses
    Native->>Native: streamHandler.setEvent(0.5)
    Native-->>App: Event delivered
```

**Critical Timing Rule:** Apps must call `stream.listen()` in the `onProgress` callback to avoid race conditions:

❌ **Wrong:**
```dart
Stream<ICloudTransferProgress>? progressStream;

await ICloudStorage.uploadFile(
  onProgress: (stream) {
    progressStream = stream;  // Store for later
  },
);

// Listen after upload completes - MISSES EVENTS
progressStream?.listen(...);
```

✅ **Correct:**
```dart
await ICloudStorage.uploadFile(
  onProgress: (stream) {
    stream.listen((event) {  // Listen immediately
      print('Progress: ${event.percent}%');
    });
  },
);
```

**Sources:** [lib/icloud_storage_method_channel.dart:275-285]()

---

## Comparison: MethodChannel vs EventChannel

| Aspect | MethodChannel | EventChannel |
|--------|---------------|--------------|
| **Instance** | Single static channel | Dynamic per-operation |
| **Communication** | Bidirectional request/response | Unidirectional stream |
| **Lifecycle** | Plugin lifetime | Operation lifetime |
| **Data Flow** | Future-based (1 response) | Stream-based (multiple events) |
| **Concurrency** | Sequential method calls | Parallel streams |
| **Cleanup** | Not needed | Automatic on cancel |
| **Use Cases** | Operations, queries | Progress, updates |
| **Channel Name** | `icloud_storage_plus` | `icloud_storage_plus/event/...` |

**Sources:** [lib/icloud_storage_method_channel.dart:16-18](), [lib/icloud_storage_method_channel.dart:86](), [lib/icloud_storage_method_channel.dart:117]()

---

## Summary

The plugin's EventChannel architecture provides:

1. **Dynamic Isolation** - Each operation gets its own channel with unique name
2. **Type Safety** - Raw events transformed to typed `ICloudTransferProgress` objects
3. **Error Resilience** - Errors delivered as data events, not stream errors
4. **Resource Management** - Automatic cleanup via cancel handlers
5. **Monotonic Progress** - Progress only increases, never decreases
6. **Lazy Activation** - Streams only activate when listeners attach

This design enables multiple concurrent file operations with independent progress tracking while maintaining clean resource lifecycle management.

**Sources:** [lib/icloud_storage_method_channel.dart](), [ios/Classes/iOSICloudStoragePlugin.swift:1-1247](), [macos/Classes/macOSICloudStoragePlugin.swift:1-1246]()