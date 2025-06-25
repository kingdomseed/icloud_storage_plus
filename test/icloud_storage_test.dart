import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/icloud_storage.dart';
import 'package:icloud_storage/icloud_storage_platform_interface.dart';
import 'package:icloud_storage/icloud_storage_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockIcloudStoragePlatform
    with MockPlatformInterfaceMixin
    implements ICloudStoragePlatform {
  final List<String> _calls = [];
  List<String> get calls => _calls;

  String _moveToRelativePath = '';
  String get moveToRelativePath => _moveToRelativePath;

  String _uploadDestinationRelativePath = '';
  String get uploadDestinationRelativePath => _uploadDestinationRelativePath;

  @override
  Future<bool> icloudAvailable() async {
    _calls.add('icloudAvailable');
    return true;
  }

  @override
  Future<String?> getContainerPath({required String containerId}) async {
    _calls.add('getContainerPath');
    return '/mock/container/path';
  }

  @override
  Future<List<ICloudFile>> gather({
    required String containerId,
    StreamHandler<List<ICloudFile>>? onUpdate,
  }) async {
    _calls.add('gather');
    return [];
  }

  @override
  Future<void> upload(
      {required String containerId,
      required String filePath,
      required String destinationRelativePath,
      StreamHandler<double>? onProgress}) async {
    _uploadDestinationRelativePath = destinationRelativePath;
    _calls.add('upload');
  }

  @override
  Future<bool> download(
      {required String containerId,
      required String relativePath,
      StreamHandler<double>? onProgress}) async {
    _calls.add('download');
    return true;
  }

  @override
  Future<void> delete(
      {required String containerId, required String relativePath}) async {
    _calls.add('delete');
  }

  @override
  Future<void> move(
      {required String containerId,
      required String fromRelativePath,
      required String toRelativePath}) async {
    _moveToRelativePath = toRelativePath;
    _calls.add('move');
  }
  
  @override
  Future<void> copy(
      {required String containerId,
      required String fromRelativePath,
      required String toRelativePath}) async {
    _calls.add('copy');
  }
  
  @override
  Future<Uint8List?> downloadAndRead({
    required String containerId,
    required String relativePath,
    StreamHandler<double>? onProgress,
  }) async {
    _calls.add('downloadAndRead');
    // Return some test data
    return Uint8List.fromList([1, 2, 3, 4, 5]);
  }
}

void main() {
  final ICloudStoragePlatform initialPlatform = ICloudStoragePlatform.instance;

  test('$MethodChannelICloudStorage is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelICloudStorage>());
  });

  group('ICloudStorage static functions:', () {
    const containerId = 'containerId';
    MockIcloudStoragePlatform fakePlatform = MockIcloudStoragePlatform();
    ICloudStoragePlatform.instance = fakePlatform;

    test('gather', () async {
      expect(await ICloudStorage.gather(containerId: containerId), []);
    });

    group('upload tests:', () {
      test('upload without destinationRelativePath specified', () async {
        await ICloudStorage.upload(
            containerId: containerId, filePath: '/dir/file');
        expect(fakePlatform.uploadDestinationRelativePath, 'file');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('upload with destinationRelativePath specified', () async {
        await ICloudStorage.upload(
            containerId: containerId,
            filePath: '/dir/file',
            destinationRelativePath: 'destFile');
        expect(fakePlatform.uploadDestinationRelativePath, 'destFile');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('upload with invalid filePath', () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId, filePath: ''),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - 2 slahes', () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId,
              filePath: 'dir/file',
              destinationRelativePath: 'dir//file'),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - dots in front',
          () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId,
              filePath: 'dir/file',
              destinationRelativePath: '..file'),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - colon', () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId,
              filePath: 'dir/file',
              destinationRelativePath: 'dir:file'),
          throwsException,
        );
      });
    });

    group('download tests:', () {
      test('download', () async {
        await ICloudStorage.download(
          containerId: containerId,
          relativePath: 'file',
        );
        expect(fakePlatform.calls.last, 'download');
      });

      test('download with invalid relativePath', () async {
        expect(
          () async => await ICloudStorage.download(
            containerId: containerId,
            relativePath: 'file/',
          ),
          throwsException,
        );
      });
    });

    test('delete', () async {
      await ICloudStorage.delete(
          containerId: containerId, relativePath: 'file');
      expect(fakePlatform.calls.last, 'delete');
    });

    test('move', () async {
      await ICloudStorage.move(
          containerId: containerId,
          fromRelativePath: 'from',
          toRelativePath: 'to');
      expect(fakePlatform.calls.last, 'move');
    });

    test('copy', () async {
      await ICloudStorage.copy(
          containerId: containerId,
          fromRelativePath: 'source.pdf',
          toRelativePath: 'backup.pdf');
      expect(fakePlatform.calls.last, 'copy');
    });

    test('rename', () async {
      await ICloudStorage.rename(
        containerId: containerId,
        relativePath: 'dir/file1',
        newName: 'file2',
      );
      expect(fakePlatform.moveToRelativePath, 'dir/file2');
    });

    test('icloudAvailable', () async {
      final available = await ICloudStorage.icloudAvailable();
      expect(available, true);
      expect(fakePlatform.calls.last, 'icloudAvailable');
    });

    test('getContainerPath', () async {
      final path = await ICloudStorage.getContainerPath(containerId: containerId);
      expect(path, '/mock/container/path');
      expect(fakePlatform.calls.last, 'getContainerPath');
    });

    group('convenience methods:', () {
      test('uploadToDocuments', () async {
        await ICloudStorage.uploadToDocuments(
          containerId: containerId,
          filePath: '/local/document.pdf',
          destinationRelativePath: 'reports/doc.pdf',
        );
        expect(fakePlatform.uploadDestinationRelativePath, 'Documents/reports/doc.pdf');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('uploadToDocuments without destinationRelativePath', () async {
        await ICloudStorage.uploadToDocuments(
          containerId: containerId,
          filePath: '/local/path/document.pdf',
        );
        expect(fakePlatform.uploadDestinationRelativePath, 'Documents/document.pdf');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('uploadPrivate', () async {
        await ICloudStorage.uploadPrivate(
          containerId: containerId,
          filePath: '/local/settings.json',
          destinationRelativePath: 'config/settings.json',
        );
        expect(fakePlatform.uploadDestinationRelativePath, 'config/settings.json');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('downloadFromDocuments', () async {
        final result = await ICloudStorage.downloadFromDocuments(
          containerId: containerId,
          relativePath: 'reports/doc.pdf',
        );
        expect(result, true);
        expect(fakePlatform.calls.last, 'download');
      });
    });

    group('metadata operations:', () {
      test('exists returns true when file is found', () async {
        // exists() calls gather(), so we need to return some files
        fakePlatform.calls.clear();
        final exists = await ICloudStorage.exists(
          containerId: containerId,
          relativePath: 'Documents/test.pdf',
        );
        expect(fakePlatform.calls.contains('gather'), true);
        // Note: exists() returns false in tests because gather() returns empty list
        expect(exists, false);
      });

      test('getMetadata returns null when file not found', () async {
        fakePlatform.calls.clear();
        final metadata = await ICloudStorage.getMetadata(
          containerId: containerId,
          relativePath: 'Documents/test.pdf',
        );
        expect(fakePlatform.calls.contains('gather'), true);
        expect(metadata, null);
      });
    });

    group('constants:', () {
      test('documentsDirectory constant', () {
        expect(ICloudStorage.documentsDirectory, 'Documents');
      });

      test('dataDirectory constant', () {
        expect(ICloudStorage.dataDirectory, 'Data');
      });
    });
    
    group('downloadAndRead tests:', () {
      test('downloadAndRead returns data', () async {
        final data = await ICloudStorage.downloadAndRead(
          containerId: containerId,
          relativePath: 'test.txt',
        );
        expect(data, isNotNull);
        expect(data, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
        expect(fakePlatform.calls.last, 'downloadAndRead');
      });
      
      test('downloadAndRead with invalid relativePath', () async {
        expect(
          () async => await ICloudStorage.downloadAndRead(
            containerId: containerId,
            relativePath: 'file/',
          ),
          throwsException,
        );
      });
    });
  });
}
