import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';

void main() {
  final platform = MethodChannelICloudStorage();
  const channel = MethodChannel('icloud_storage');
  late MethodCall mockMethodCall;
  const containerId = 'containerId';
  Map<String, Object?> mockArguments() =>
      (mockMethodCall.arguments as Map).cast<String, Object?>();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      mockMethodCall = methodCall;
      switch (methodCall.method) {
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
        case 'download':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('gather tests:', () {
    test('maps meta data correctly', () async {
      final files = await platform.gather(containerId: containerId);
      expect(files.last.relativePath, 'relativePath');
      expect(files.last.isDirectory, false);
      expect(files.last.sizeInBytes, 100);
      expect(
        files.last.creationDate,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(
        files.last.contentChangeDate,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(files.last.isDownloading, true);
      expect(files.last.downloadStatus, DownloadStatus.notDownloaded);
      expect(files.last.isUploading, false);
      expect(files.last.isUploaded, false);
      expect(files.last.hasUnresolvedConflicts, false);
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

  group('upload tests:', () {
    test('upload', () async {
      await platform.upload(
        containerId: containerId,
        filePath: '/dir/file',
        destinationRelativePath: 'dest',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['localFilePath'], '/dir/file');
      expect(args['cloudFileName'], 'dest');
      expect(args['eventChannelName'], '');
    });

    test('upload with onProgress', () async {
      await platform.upload(
        containerId: containerId,
        filePath: '/dir/file',
        destinationRelativePath: 'dest',
        onProgress: (stream) => {},
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });
  });

  group('download tests:', () {
    test('download', () async {
      final result = await platform.download(
        containerId: containerId,
        relativePath: 'file',
      );
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['cloudFileName'], 'file');
      expect(args['eventChannelName'], '');
      expect(result, true);
    });

    test('download with onProgress', () async {
      await platform.download(
        containerId: containerId,
        relativePath: 'file',
        onProgress: (stream) => {},
      );
      final args = mockArguments();
      final eventChannelName = args['eventChannelName'] as String?;
      expect(eventChannelName, isNotNull);
      expect(eventChannelName, isNotEmpty);
    });
  });

  test('delete', () async {
    await platform.delete(
      containerId: containerId,
      relativePath: 'file',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['cloudFileName'], 'file');
  });

  test('move', () async {
    await platform.move(
      containerId: containerId,
      fromRelativePath: 'from',
      toRelativePath: 'to',
    );
    final args = mockArguments();
    expect(args['containerId'], containerId);
    expect(args['atRelativePath'], 'from');
    expect(args['toRelativePath'], 'to');
  });
}
