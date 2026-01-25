import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
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

  Stream<ICloudTransferProgress> _receiveTransferProgressStream(
    EventChannel eventChannel,
  ) {
    late final StreamController<ICloudTransferProgress> controller;
    StreamSubscription<dynamic>? subscription;
    final bufferedEvents = <ICloudTransferProgress>[];
    var hasListener = false;
    var flushCompleted = false;
    var pendingClose = false;

    controller = StreamController<ICloudTransferProgress>.broadcast(
      onListen: () {
        if (hasListener) return;
        hasListener = true;
        if (!flushCompleted && bufferedEvents.isNotEmpty) {
          for (final event in bufferedEvents) {
            if (controller.isClosed) return;
            controller.add(event);
          }
          bufferedEvents.clear();
          flushCompleted = true;
        }
        if (pendingClose && !controller.isClosed) {
          unawaited(controller.close());
        }
      },
      onCancel: () async {
        await subscription?.cancel();
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );

    subscription = eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (controller.isClosed) return;
        if (event is num) {
          final progress = ICloudTransferProgress.progress(event.toDouble());
          if (hasListener) {
            controller.add(progress);
          } else {
            if (bufferedEvents.length >= 10) {
              bufferedEvents.removeAt(0);
            }
            bufferedEvents.add(progress);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (controller.isClosed) return;
        final exception = error is PlatformException
            ? error
            : () {
                _logger.severe(
                  'Unexpected progress stream error',
                  error,
                  stackTrace,
                );
                return PlatformException(
                  code: 'E_PLUGIN_INTERNAL',
                  message:
                      'Internal plugin error during progress stream processing',
                  details: error,
                  stacktrace: stackTrace.toString(),
                );
              }();
        final wrapped = ICloudTransferProgress.error(exception);
        if (hasListener) {
          controller.add(wrapped);
        } else {
          bufferedEvents.add(wrapped);
        }
        pendingClose = true;
        unawaited(subscription?.cancel());
        if (hasListener) {
          unawaited(controller.close());
        }
      },
      onDone: () {
        if (controller.isClosed) return;
        const done = ICloudTransferProgress.done();
        if (hasListener) {
          controller.add(done);
        } else {
          bufferedEvents.add(done);
        }
        pendingClose = true;
        if (hasListener) {
          unawaited(controller.close());
        }
      },
    );

    return controller.stream;
  }

  /// Private method to convert the list of maps from platform code to a list of
  /// ICloudFile object
  GatherResult _mapFilesFromDynamicList(
    List<dynamic>? mapList,
  ) {
    final files = <ICloudFile>[];
    final invalidEntries = <GatherInvalidEntry>[];
    if (mapList != null) {
      for (var index = 0; index < mapList.length; index += 1) {
        final entry = mapList[index];
        if (entry is! Map<dynamic, dynamic>) {
          _logger.warning(
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
          continue;
        }
        try {
          files.add(ICloudFile.fromMap(entry));
        } on Exception catch (error, stackTrace) {
          _logger.warning(
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
