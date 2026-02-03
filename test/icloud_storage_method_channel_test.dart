import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';

void main() {
  final platform = MethodChannelICloudStorage();
  const channel = MethodChannel('icloud_storage_plus');
  late MethodCall mockMethodCall;
  const containerId = 'containerId';
  MockStreamHandler? mockStreamHandler;
  String? lastEventChannelName;
  Map<String, Object?> mockArguments() =>
      (mockMethodCall.arguments as Map).cast<String, Object?>();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      mockMethodCall = methodCall;
      switch (methodCall.method) {
        case 'createEventChannel':
          final args = mockArguments();
          lastEventChannelName = args['eventChannelName'] as String?;
          if (lastEventChannelName != null && mockStreamHandler != null) {
            final eventChannel = EventChannel(lastEventChannelName!);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockStreamHandler(eventChannel, mockStreamHandler);
          }
          return null;
        case 'gather':
          return [
            {
              'relativePath': 'relativePath',
              'isDirectory': false,
              'sizeInBytes': 100,
              'creationDate': 1.0,
              'contentChangeDate': 1.0,
              'isDownloading': true,
              'downloadStatus':
                  'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded',
              'isUploading': false,
              'isUploaded': false,
              'hasUnresolvedConflicts': false,
            }
          ];
        case 'downloadFile':
          return null;
        case 'documentExists':
          return true;
        case 'getDocumentMetadata':
          return {
            'relativePath': 'meta.txt',
            'isDirectory': false,
          };
        case 'getContainerPath':
          return '/container/path';
        case 'readInPlace':
          return 'contents';
        case 'writeInPlace':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (lastEventChannelName != null) {
      final eventChannel = EventChannel(lastEventChannelName!);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
      lastEventChannelName = null;
    }
    mockStreamHandler = null;
  });

  group('gather tests:', () {
    test('maps meta data correctly', () async {
      final result = await platform.gather(containerId: containerId);
      final file = result.files.last;
      expect(file.relativePath, 'relativePath');
      expect(file.isDirectory, false);
      expect(file.sizeInBytes, 100);
      expect(
        file.creationDate,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(
        file.contentChangeDate,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(file.isDownloading, true);
      expect(file.downloadStatus, DownloadStatus.notDownloaded);
      expect(file.isUploading, false);
      expect(file.isUploaded, false);
      expect(file.hasUnresolvedConflicts, false);
    });

    test('directory paths preserve trailing slashes', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'gather') {
          return [
            {
              'relativePath': 'Documents/folder/',
              'isDirectory': true,
              'sizeInBytes': null,
            }
          ];
        }
        return null;
      });

      final result = await platform.gather(containerId: containerId);
      final directory = result.files.first;

      expect(directory.isDirectory, true);
      expect(directory.relativePath, 'Documents/folder/');
      expect(
        directory.relativePath.endsWith('/'),
        true,
        reason: 'Directory paths may include trailing slashes',
      );
    });

    test('gather with update', () async {
      await platform.gather(
        containerId: containerId,
        onUpdate: (stream) {},
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });
  });

  group('uploadFile tests:', () {
    test('uploadFile', () async {
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        cloudRelativePath: 'dest',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['localFilePath'], '/dir/file');
      expect(args['cloudRelativePath'], 'dest');
      expect(args['eventChannelName'], '');
    });

    test('uploadFile with onProgress', () async {
      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        cloudRelativePath: 'dest',
        onProgress: (stream) => {},
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });
  });

  group('downloadFile tests:', () {
    test('downloadFile', () async {
      await platform.downloadFile(
        containerId: containerId,
        cloudRelativePath: 'file',
        localPath: '/tmp/file',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['cloudRelativePath'], 'file');
      expect(args['localFilePath'], '/tmp/file');
      expect(args['eventChannelName'], '');
    });

    test('downloadFile with onProgress', () async {
      await platform.downloadFile(
        containerId: containerId,
        cloudRelativePath: 'file',
        localPath: '/tmp/file',
        onProgress: (stream) => {},
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });
  });

  group('readInPlace tests:', () {
    test('readInPlace', () async {
      final result = await platform.readInPlace(
        containerId: containerId,
        relativePath: 'Documents/test.json',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/test.json');
      expect(result, 'contents');
    });

    test('passes idle timeout and retry backoff settings', () async {
      await platform.readInPlace(
        containerId: containerId,
        relativePath: 'Documents/test.json',
        idleTimeouts: const [
          Duration(seconds: 60),
          Duration(seconds: 90),
          Duration(seconds: 180),
        ],
        retryBackoff: const [
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
      );
      final args = mockArguments();
      expect(args['idleTimeoutSeconds'], [60, 90, 180]);
      expect(args['retryBackoffSeconds'], [2, 4]);
    });
  });

  group('writeInPlace tests:', () {
    test('writeInPlace', () async {
      await platform.writeInPlace(
        containerId: containerId,
        relativePath: 'Documents/test.json',
        contents: '{"ok":true}',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'Documents/test.json');
      expect(args['contents'], '{"ok":true}');
    });
  });

  group('transfer progress stream tests:', () {
    test('maps numeric events and completion', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(0.25)
            ..success(1.0)
            ..endOfStream();
        },
      );

      late Stream<ICloudTransferProgress> progressStream;

      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        cloudRelativePath: 'dest',
        onProgress: (stream) {
          progressStream = stream;
        },
      );

      final events = await progressStream.toList();
      expect(events, hasLength(3));
      expect(events[0].isProgress, isTrue);
      expect(events[0].percent, 0.25);
      expect(events[1].isProgress, isTrue);
      expect(events[1].percent, 1.0);
      expect(events[2].isDone, isTrue);
    });

    test('maps error events to error progress', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.error(
            code: 'E_TEST',
            message: 'Boom',
            details: 'details',
          );
        },
      );

      late Stream<ICloudTransferProgress> progressStream;

      await platform.downloadFile(
        containerId: containerId,
        cloudRelativePath: 'file',
        localPath: '/tmp/file',
        onProgress: (stream) {
          progressStream = stream;
        },
      );

      final events = await progressStream.toList();
      expect(events, hasLength(1));
      final event = events.first;
      expect(event.isError, isTrue);
      expect(event.exception?.code, 'E_TEST');
      expect(event.exception?.message, 'Boom');
      expect(event.exception?.details, 'details');
    });

    test('delivers events after listener attaches', () async {
      mockStreamHandler = MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(0.1)
            ..endOfStream();
        },
      );

      late Stream<ICloudTransferProgress> progressStream;

      await platform.uploadFile(
        containerId: containerId,
        localPath: '/dir/file',
        cloudRelativePath: 'dest',
        onProgress: (stream) {
          progressStream = stream;
        },
      );

      final events = await progressStream.toList();
      expect(events, hasLength(2));
      expect(events[0].isProgress, isTrue);
      expect(events[0].percent, 0.1);
      expect(events[1].isDone, isTrue);
    });
  });

  test('delete', () async {
    await platform.delete(
      containerId: containerId,
      relativePath: 'file',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['relativePath'], 'file');
  });

  test('move', () async {
    await platform.move(
      containerId: containerId,
      fromRelativePath: 'file',
      toRelativePath: 'file2',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['atRelativePath'], 'file');
    expect(args['toRelativePath'], 'file2');
  });

  test('copy', () async {
    await platform.copy(
      containerId: containerId,
      fromRelativePath: 'file',
      toRelativePath: 'file2',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['fromRelativePath'], 'file');
    expect(args['toRelativePath'], 'file2');
  });

  test('documentExists', () async {
    final exists = await platform.documentExists(
      containerId: containerId,
      relativePath: 'file',
    );
    expect(exists, true);
  });

  test('getDocumentMetadata', () async {
    final metadata = await platform.getDocumentMetadata(
      containerId: containerId,
      relativePath: 'file',
    );
    expect(metadata?['relativePath'], 'meta.txt');
  });

  test('getContainerPath', () async {
    final path = await platform.getContainerPath(containerId: containerId);
    expect(path, '/container/path');
  });
}
