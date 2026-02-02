import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';
import 'package:logging/logging.dart';

/// An implementation of [ICloudStoragePlatform] that uses method channels.
class MethodChannelICloudStorage extends ICloudStoragePlatform {
  static final Logger _logger = Logger('ICloudStorage');

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('icloud_storage_plus');

  @override
  Future<bool> icloudAvailable() async {
    final result = await methodChannel.invokeMethod<bool>('icloudAvailable');
    return result ?? false;
  }

  @override
  Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    final eventChannelName = onUpdate == null
        ? ''
        : _generateEventChannelName('gather', containerId);

    if (onUpdate != null) {
      await methodChannel.invokeMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final gatherEventChannel = EventChannel(eventChannelName);
      final stream = gatherEventChannel
          .receiveBroadcastStream()
          .where((event) => event is List)
          .map<GatherResult>((event) {
        return _mapFilesFromDynamicList(event as List);
      });

      onUpdate(stream);
    }

    final mapList = await methodChannel.invokeListMethod<dynamic>('gather', {
      'containerId': containerId,
      'eventChannelName': eventChannelName,
    });

    return _mapFilesFromDynamicList(mapList);
  }

  @override
  Future<String?> getContainerPath({required String containerId}) async {
    final result = await methodChannel.invokeMethod<String>(
      'getContainerPath',
      {'containerId': containerId},
    );
    return result;
  }

  @override
  Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String cloudRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('uploadFile', containerId);

      await methodChannel.invokeMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final uploadEventChannel = EventChannel(eventChannelName);
      final stream = _receiveTransferProgressStream(uploadEventChannel);

      onProgress(stream);
    }

    await methodChannel.invokeMethod('uploadFile', {
      'containerId': containerId,
      'localFilePath': localPath,
      'cloudRelativePath': cloudRelativePath,
      'eventChannelName': eventChannelName,
    });
  }

  @override
  Future<void> downloadFile({
    required String containerId,
    required String cloudRelativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('downloadFile', containerId);

      await methodChannel.invokeMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final downloadEventChannel = EventChannel(eventChannelName);
      final stream = _receiveTransferProgressStream(downloadEventChannel);

      onProgress(stream);
    }

    await methodChannel.invokeMethod('downloadFile', {
      'containerId': containerId,
      'cloudRelativePath': cloudRelativePath,
      'localFilePath': localPath,
      'eventChannelName': eventChannelName,
    });
  }

  @override
  Future<String?> readInPlace({
    required String containerId,
    required String relativePath,
  }) async {
    final result = await methodChannel.invokeMethod<String>('readInPlace', {
      'containerId': containerId,
      'relativePath': relativePath,
    });
    return result;
  }

  @override
  Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    await methodChannel.invokeMethod('writeInPlace', {
      'containerId': containerId,
      'relativePath': relativePath,
      'contents': contents,
    });
  }

  @override
  Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    await methodChannel.invokeMethod('delete', {
      'containerId': containerId,
      'relativePath': relativePath,
    });
  }

  @override
  Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    await methodChannel.invokeMethod('move', {
      'containerId': containerId,
      'atRelativePath': fromRelativePath,
      'toRelativePath': toRelativePath,
    });
  }

  @override
  Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    await methodChannel.invokeMethod('copy', {
      'containerId': containerId,
      'fromRelativePath': fromRelativePath,
      'toRelativePath': toRelativePath,
    });
  }

  @override
  Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    final result = await methodChannel.invokeMethod<bool>('documentExists', {
      'containerId': containerId,
      'relativePath': relativePath,
    });
    return result ?? false;
  }

  @override
  Future<Map<String, dynamic>?> getDocumentMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    final result = await methodChannel
        .invokeMethod<Map<dynamic, dynamic>?>('getDocumentMetadata', {
      'containerId': containerId,
      'relativePath': relativePath,
    });

    if (result == null) return null;

    // Convert dynamic map to properly typed map
    return result.map((key, value) => MapEntry(key.toString(), value));
  }

  /// Creates a progress stream backed by the native event channel.
  ///
  /// The stream subscribes lazily when a listener attaches. Callers should
  /// listen immediately in the `onProgress` callback to avoid missing early
  /// progress events.
  ///
  /// **Note on Error Handling:**
  /// This stream does **not** emit Dart errors via `onError`. Failures are
  /// delivered as data events with `type == ICloudTransferProgressType.error`.
  /// You must check `event.isError` (or `event.type`) inside the data listener
  /// to handle failures. See [ICloudTransferProgress] for details.
  Stream<ICloudTransferProgress> _receiveTransferProgressStream(
    EventChannel eventChannel,
  ) {
    final transformer =
        StreamTransformer<Object?, ICloudTransferProgress>.fromHandlers(
      handleData: (event, sink) {
        if (event is num) {
          sink.add(ICloudTransferProgress.progress(event.toDouble()));
          return;
        }

        final exception = PlatformException(
          code: PlatformExceptionCode.invalidEvent,
          message: 'Unexpected progress event type: ${event.runtimeType}',
          details: event,
        );
        sink
          ..add(ICloudTransferProgress.error(exception))
          ..close();
      },
      handleError: (Object error, StackTrace stackTrace, sink) {
        final exception = error is PlatformException
            ? error
            : () {
                _logger.severe(
                  'Unexpected progress stream error',
                  error,
                  stackTrace,
                );
                return PlatformException(
                  code: PlatformExceptionCode.pluginInternal,
                  message: 'Internal plugin error during progress '
                      'stream processing',
                  details: error,
                  stacktrace: stackTrace.toString(),
                );
              }();

        sink
          ..add(ICloudTransferProgress.error(exception))
          ..close();
      },
      handleDone: (sink) {
        sink
          ..add(const ICloudTransferProgress.done())
          ..close();
      },
    );

    return eventChannel.receiveBroadcastStream().transform(transformer);
  }

  /// Private method to convert the list of maps from platform code to a list of
  /// ICloudFile object
  GatherResult _mapFilesFromDynamicList(
    List<dynamic>? mapList,
  ) {
    final files = <ICloudFile>[];
    final invalidEntries = <GatherInvalidEntry>[];
    if (mapList != null) {
      var index = 0;
      for (final entry in mapList) {
        if (entry is! Map<dynamic, dynamic>) {
          _logger.fine(
            'Skipping malformed metadata entry: expected Map, got '
            '${entry.runtimeType}',
          );
          invalidEntries.add(
            GatherInvalidEntry(
              error: 'Expected map, got ${entry.runtimeType}',
              rawEntry: entry,
              index: index,
            ),
          );
        } else {
          try {
            files.add(ICloudFile.fromMap(entry));
          } on Exception catch (error, stackTrace) {
            _logger.fine(
              'Skipping malformed metadata entry: $error',
              error,
              stackTrace,
            );
            invalidEntries.add(
              GatherInvalidEntry(
                error: error.toString(),
                rawEntry: entry,
                index: index,
              ),
            );
          }
        }
        index++;
      }
    }
    if (invalidEntries.isNotEmpty) {
      _logger.warning(
        'Skipped ${invalidEntries.length} malformed metadata '
        '${invalidEntries.length == 1 ? 'entry' : 'entries'} during gather.',
      );
    }
    return GatherResult(files: files, invalidEntries: invalidEntries);
  }

  /// Private method to generate event channel names
  String _generateEventChannelName(
    String eventType,
    String containerId, [
    String? additionalIdentifier,
  ]) =>
      [
        'icloud_storage_plus',
        'event',
        eventType,
        containerId,
        ...(additionalIdentifier == null
            ? <String>[]
            : <String>[additionalIdentifier]),
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}',
      ].join('/');
}
