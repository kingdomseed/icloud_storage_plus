import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
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
  Future<List<ICloudFile>> gather({
    required String containerId,
    StreamHandler<List<ICloudFile>>? onUpdate,
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
          .map<List<ICloudFile>>((event) {
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
  Future<void> upload({
    required String containerId,
    required String filePath,
    required String destinationRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('upload', containerId);

      await methodChannel.invokeMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final uploadEventChannel = EventChannel(eventChannelName);
      final stream = _receiveTransferProgressStream(uploadEventChannel);

      onProgress(stream);
    }

    await methodChannel.invokeMethod('upload', {
      'containerId': containerId,
      'localFilePath': filePath,
      'cloudFileName': destinationRelativePath,
      'eventChannelName': eventChannelName,
    });
  }

  @override
  Future<bool> download({
    required String containerId,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = _generateEventChannelName('download', containerId);

      await methodChannel.invokeMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final downloadEventChannel = EventChannel(eventChannelName);
      final stream = _receiveTransferProgressStream(downloadEventChannel);

      onProgress(stream);
    }

    final result = await methodChannel.invokeMethod<bool>('download', {
      'containerId': containerId,
      'cloudFileName': relativePath,
      'eventChannelName': eventChannelName,
    });
    return result ?? false;
  }

  @override
  Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    await methodChannel.invokeMethod('delete', {
      'containerId': containerId,
      'cloudFileName': relativePath,
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
  Future<Uint8List?> downloadAndRead({
    required String containerId,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName =
          _generateEventChannelName('downloadAndRead', containerId);

      await methodChannel.invokeMethod(
        'createEventChannel',
        {'eventChannelName': eventChannelName},
      );

      final downloadEventChannel = EventChannel(eventChannelName);
      final stream = _receiveTransferProgressStream(downloadEventChannel);

      onProgress(stream);
    }

    final result =
        await methodChannel.invokeMethod<Uint8List?>('downloadAndRead', {
      'containerId': containerId,
      'cloudFileName': relativePath,
      'eventChannelName': eventChannelName,
    });

    return result;
  }

  @override
  Future<Uint8List?> readDocument({
    required String containerId,
    required String relativePath,
  }) async {
    final result =
        await methodChannel.invokeMethod<Uint8List?>('readDocument', {
      'containerId': containerId,
      'relativePath': relativePath,
    });
    return result;
  }

  @override
  Future<void> writeDocument({
    required String containerId,
    required String relativePath,
    required Uint8List data,
  }) async {
    await methodChannel.invokeMethod('writeDocument', {
      'containerId': containerId,
      'relativePath': relativePath,
      'data': data,
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

    controller = StreamController<ICloudTransferProgress>.broadcast(
      onListen: () {
        subscription = eventChannel.receiveBroadcastStream().listen(
          (event) {
            if (controller.isClosed) return;
            if (event is num) {
              controller.add(
                ICloudTransferProgress.progress(event.toDouble()),
              );
            }
          },
          onError: (Object error) {
            if (controller.isClosed) return;
            final exception = error is PlatformException
                ? error
                : PlatformException(
                    code: 'E_STREAM',
                    message: 'Unexpected progress stream error',
                    details: error.toString(),
                  );
            controller.add(ICloudTransferProgress.error(exception));
            unawaited(subscription?.cancel());
            unawaited(controller.close());
          },
          onDone: () {
            if (controller.isClosed) return;
            controller.add(const ICloudTransferProgress.done());
            unawaited(controller.close());
          },
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );

    return controller.stream;
  }

  /// Private method to convert the list of maps from platform code to a list of
  /// ICloudFile object
  List<ICloudFile> _mapFilesFromDynamicList(
    List<dynamic>? mapList,
  ) {
    final files = <ICloudFile>[];
    if (mapList != null) {
      for (final entry in mapList) {
        if (entry is! Map<dynamic, dynamic>) {
          _logger.warning(
            'Skipping malformed metadata entry: expected Map, got '
            '${entry.runtimeType}',
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
        }
      }
    }
    return files;
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
