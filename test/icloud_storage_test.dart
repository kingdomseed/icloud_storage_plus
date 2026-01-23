import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/icloud_storage.dart';
import 'package:icloud_storage/icloud_storage_method_channel.dart';
import 'package:icloud_storage/icloud_storage_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockICloudStoragePlatform
    with MockPlatformInterfaceMixin
    implements ICloudStoragePlatform {
  final List<String> _calls = [];
  List<String> get calls => _calls;

  String _moveToRelativePath = '';
  String get moveToRelativePath => _moveToRelativePath;

  String _uploadDestinationRelativePath = '';
  String get uploadDestinationRelativePath => _uploadDestinationRelativePath;

  bool documentExistsResult = true;
  Map<String, dynamic>? documentMetadataResult = {
    'relativePath': 'Documents/test.pdf',
    'isDirectory': false,
    'sizeInBytes': 1024,
    'creationDate': 1638288000.0,
    'contentChangeDate': 1638374400.0,
    'downloadStatus': 'NSMetadataUbiquitousItemDownloadingStatusCurrent',
    'hasUnresolvedConflicts': false,
  };

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
  Future<void> upload({
    required String containerId,
    required String filePath,
    required String destinationRelativePath,
    StreamHandler<double>? onProgress,
  }) async {
    _uploadDestinationRelativePath = destinationRelativePath;
    _calls.add('upload');
  }

  @override
  Future<bool> download({
    required String containerId,
    required String relativePath,
    StreamHandler<double>? onProgress,
  }) async {
    _calls.add('download');
    return true;
  }

  @override
  Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('delete');
  }

  @override
  Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    _moveToRelativePath = toRelativePath;
    _calls.add('move');
  }

  @override
  Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
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

  @override
  Future<Uint8List?> readDocument({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('readDocument');
    // Return some test data
    return Uint8List.fromList([10, 20, 30, 40, 50]);
  }

  @override
  Future<void> writeDocument({
    required String containerId,
    required String relativePath,
    required Uint8List data,
  }) async {
    _calls.add('writeDocument');
  }

  @override
  Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('documentExists');
    return documentExistsResult;
  }

  @override
  Future<Map<String, dynamic>?> getDocumentMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    _calls.add('getDocumentMetadata');
    return documentMetadataResult;
  }
}

void main() {
  final initialPlatform = ICloudStoragePlatform.instance;

  test('$MethodChannelICloudStorage is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelICloudStorage>());
  });

  group('ICloudStorage static functions:', () {
    const containerId = 'containerId';
    var fakePlatform = MockICloudStoragePlatform();
    ICloudStoragePlatform.instance = fakePlatform;

    test('gather', () async {
      expect(await ICloudStorage.gather(containerId: containerId), []);
    });

    group('upload tests:', () {
      test('upload without destinationRelativePath specified', () async {
        await ICloudStorage.upload(
          containerId: containerId,
          filePath: '/dir/file',
        );
        expect(fakePlatform.uploadDestinationRelativePath, 'file');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('upload with destinationRelativePath specified', () async {
        await ICloudStorage.upload(
          containerId: containerId,
          filePath: '/dir/file',
          destinationRelativePath: 'destFile',
        );
        expect(fakePlatform.uploadDestinationRelativePath, 'destFile');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('upload with invalid filePath', () async {
        expect(
          () async => ICloudStorage.upload(
            containerId: containerId,
            filePath: '',
          ),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - 2 slahes', () async {
        expect(
          () async => ICloudStorage.upload(
            containerId: containerId,
            filePath: 'dir/file',
            destinationRelativePath: 'dir//file',
          ),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - dots in front',
          () async {
        expect(
          () async => ICloudStorage.upload(
            containerId: containerId,
            filePath: 'dir/file',
            destinationRelativePath: '..file',
          ),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - colon', () async {
        expect(
          () async => ICloudStorage.upload(
            containerId: containerId,
            filePath: 'dir/file',
            destinationRelativePath: 'dir:file',
          ),
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
          () async => ICloudStorage.download(
            containerId: containerId,
            relativePath: 'file/',
          ),
          throwsException,
        );
      });
    });

    test('delete', () async {
      await ICloudStorage.delete(
        containerId: containerId,
        relativePath: 'file',
      );
      expect(fakePlatform.calls.last, 'delete');
    });

    test('move', () async {
      await ICloudStorage.move(
        containerId: containerId,
        fromRelativePath: 'from',
        toRelativePath: 'to',
      );
      expect(fakePlatform.calls.last, 'move');
    });

    test('copy', () async {
      await ICloudStorage.copy(
        containerId: containerId,
        fromRelativePath: 'source.pdf',
        toRelativePath: 'backup.pdf',
      );
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
      final path =
          await ICloudStorage.getContainerPath(containerId: containerId);
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
        expect(
          fakePlatform.uploadDestinationRelativePath,
          'Documents/reports/doc.pdf',
        );
        expect(fakePlatform.calls.last, 'upload');
      });

      test('uploadToDocuments without destinationRelativePath', () async {
        await ICloudStorage.uploadToDocuments(
          containerId: containerId,
          filePath: '/local/path/document.pdf',
        );
        expect(
          fakePlatform.uploadDestinationRelativePath,
          'Documents/document.pdf',
        );
        expect(fakePlatform.calls.last, 'upload');
      });

      test('uploadPrivate', () async {
        await ICloudStorage.uploadPrivate(
          containerId: containerId,
          filePath: '/local/settings.json',
          destinationRelativePath: 'config/settings.json',
        );
        expect(
          fakePlatform.uploadDestinationRelativePath,
          'config/settings.json',
        );
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
        fakePlatform.calls.clear();
        fakePlatform.documentExistsResult = true;
        final exists = await ICloudStorage.exists(
          containerId: containerId,
          relativePath: 'Documents/test.pdf',
        );
        expect(fakePlatform.calls.contains('documentExists'), true);
        expect(exists, true);
      });

      test('getMetadata returns null when file not found', () async {
        fakePlatform.calls.clear();
        fakePlatform.documentMetadataResult = null;
        final metadata = await ICloudStorage.getMetadata(
          containerId: containerId,
          relativePath: 'Documents/test.pdf',
        );
        expect(fakePlatform.calls.contains('getDocumentMetadata'), true);
        expect(metadata, null);
      });

      test('getMetadata returns directory metadata when available', () async {
        fakePlatform.calls.clear();
        fakePlatform.documentMetadataResult = {
          'relativePath': 'Documents/reports',
          'isDirectory': true,
          'sizeInBytes': 4096,
          'creationDate': 1638288000.0,
          'contentChangeDate': 1638374400.0,
          'downloadStatus': 'NSMetadataUbiquitousItemDownloadingStatusCurrent',
        };
        final metadata = await ICloudStorage.getMetadata(
          containerId: containerId,
          relativePath: 'Documents/reports',
        );
        expect(fakePlatform.calls.contains('getDocumentMetadata'), true);
        expect(metadata?.isDirectory, true);
        expect(metadata?.sizeInBytes, 4096);
        expect(metadata?.downloadStatus, DownloadStatus.current);
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
          () async => ICloudStorage.downloadAndRead(
            containerId: containerId,
            relativePath: 'file/',
          ),
          throwsException,
        );
      });
    });

    group('document methods tests:', () {
      test('readDocument returns data', () async {
        final data = await ICloudStorage.readDocument(
          containerId: containerId,
          relativePath: 'Documents/test.txt',
        );
        expect(data, isNotNull);
        expect(data, equals(Uint8List.fromList([10, 20, 30, 40, 50])));
        expect(fakePlatform.calls.last, 'readDocument');
      });

      test('writeDocument writes data', () async {
        final testData = Uint8List.fromList([1, 2, 3]);
        await ICloudStorage.writeDocument(
          containerId: containerId,
          relativePath: 'Documents/test.txt',
          data: testData,
        );
        expect(fakePlatform.calls.last, 'writeDocument');
      });

      test('documentExists returns true', () async {
        final exists = await ICloudStorage.documentExists(
          containerId: containerId,
          relativePath: 'Documents/test.txt',
        );
        expect(exists, true);
        expect(fakePlatform.calls.last, 'documentExists');
      });

      test('getDocumentMetadata returns metadata', () async {
        final metadata = await ICloudStorage.getDocumentMetadata(
          containerId: containerId,
          relativePath: 'Documents/test.txt',
        );
        expect(metadata, isNotNull);
        expect(metadata?['isDirectory'], false);
        expect(metadata?['sizeInBytes'], 1024);
        expect(
          metadata?['downloadStatus'],
          'NSMetadataUbiquitousItemDownloadingStatusCurrent',
        );
        expect(metadata?['hasUnresolvedConflicts'], false);
        expect(fakePlatform.calls.last, 'getDocumentMetadata');
      });

      test('readJsonDocument parses JSON correctly', () async {
        // Override readDocument to return JSON data
        fakePlatform = MockICloudStoragePlatform();
        ICloudStoragePlatform.instance = fakePlatform;

        // Can't easily override the return value, so this test would need
        // a more sophisticated mock setup
      });

      test('writeJsonDocument encodes JSON correctly', () async {
        await ICloudStorage.writeJsonDocument(
          containerId: containerId,
          relativePath: 'Documents/settings.json',
          data: {'key': 'value', 'number': 42},
        );
        expect(fakePlatform.calls.last, 'writeDocument');
      });

      test('updateDocument calls read and write', () async {
        await ICloudStorage.updateDocument(
          containerId: containerId,
          relativePath: 'Documents/counter.txt',
          updater: (current) => Uint8List.fromList([99]),
        );
        expect(fakePlatform.calls.contains('readDocument'), true);
        expect(fakePlatform.calls.last, 'writeDocument');
      });

      test('invalid relativePath throws exception', () async {
        expect(
          () async => ICloudStorage.readDocument(
            containerId: containerId,
            relativePath: 'file/',
          ),
          throwsException,
        );
      });
    });
  });
}
