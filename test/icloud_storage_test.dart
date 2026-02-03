import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';
import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockICloudStoragePlatform
    with MockPlatformInterfaceMixin
    implements ICloudStoragePlatform {
  final List<String> _calls = [];
  List<String> get calls => _calls;

  String _moveToRelativePath = '';
  String get moveToRelativePath => _moveToRelativePath;

  String _uploadCloudRelativePath = '';
  String get uploadCloudRelativePath => _uploadCloudRelativePath;

  String _downloadCloudRelativePath = '';
  String get downloadCloudRelativePath => _downloadCloudRelativePath;

  String _downloadLocalPath = '';
  String get downloadLocalPath => _downloadLocalPath;

  String _readInPlaceRelativePath = '';
  String get readInPlaceRelativePath => _readInPlaceRelativePath;

  String? readInPlaceResult = 'contents';

  String _writeInPlaceRelativePath = '';
  String get writeInPlaceRelativePath => _writeInPlaceRelativePath;

  String _writeInPlaceContents = '';
  String get writeInPlaceContents => _writeInPlaceContents;

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
  Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    _calls.add('gather');
    return const GatherResult(files: [], invalidEntries: []);
  }

  @override
  Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String cloudRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    _uploadCloudRelativePath = cloudRelativePath;
    _calls.add('uploadFile');
  }

  @override
  Future<void> downloadFile({
    required String containerId,
    required String cloudRelativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    _downloadCloudRelativePath = cloudRelativePath;
    _downloadLocalPath = localPath;
    _calls.add('downloadFile');
  }

  @override
  Future<String?> readInPlace({
    required String containerId,
    required String relativePath,
    List<Duration>? idleTimeouts,
    List<Duration>? retryBackoff,
  }) async {
    _readInPlaceRelativePath = relativePath;
    _calls.add('readInPlace');
    return readInPlaceResult;
  }

  @override
  Future<Uint8List?> readInPlaceBytes({
    required String containerId,
    required String relativePath,
    List<Duration>? idleTimeouts,
    List<Duration>? retryBackoff,
  }) async {
    _readInPlaceRelativePath = relativePath;
    _calls.add('readInPlaceBytes');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    _writeInPlaceRelativePath = relativePath;
    _writeInPlaceContents = contents;
    _calls.add('writeInPlace');
  }

  @override
  Future<void> writeInPlaceBytes({
    required String containerId,
    required String relativePath,
    required Uint8List contents,
  }) async {
    _writeInPlaceRelativePath = relativePath;
    _calls.add('writeInPlaceBytes');
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
    final fakePlatform = MockICloudStoragePlatform();
    ICloudStoragePlatform.instance = fakePlatform;

    setUp(() {
      fakePlatform
        ..documentExistsResult = true
        ..documentMetadataResult = {
          'relativePath': 'Documents/test.pdf',
          'isDirectory': false,
          'sizeInBytes': 1024,
          'creationDate': 1638288000.0,
          'contentChangeDate': 1638374400.0,
          'downloadStatus': 'NSMetadataUbiquitousItemDownloadingStatusCurrent',
          'hasUnresolvedConflicts': false,
        }
        ..readInPlaceResult = 'contents';
    });

    test('gather', () async {
      final result = await ICloudStorage.gather(containerId: containerId);
      expect(result.files, isEmpty);
      expect(result.invalidEntries, isEmpty);
    });

    group('uploadFile tests:', () {
      test('uploadFile', () async {
        await ICloudStorage.uploadFile(
          containerId: containerId,
          localPath: '/dir/file',
          cloudRelativePath: 'dest',
        );
        expect(fakePlatform.uploadCloudRelativePath, 'dest');
        expect(fakePlatform.calls.last, 'uploadFile');
      });

      test('uploadFile rejects trailing slash cloudRelativePath', () async {
        expect(
          () async => ICloudStorage.uploadFile(
            containerId: containerId,
            localPath: '/dir/file',
            cloudRelativePath: 'Documents/folder/',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('uploadFile with invalid localPath', () async {
        expect(
          () async => ICloudStorage.uploadFile(
            containerId: containerId,
            localPath: '',
            cloudRelativePath: 'dest',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('uploadFile with invalid cloudRelativePath', () async {
        expect(
          () async => ICloudStorage.uploadFile(
            containerId: containerId,
            localPath: '/dir/file',
            cloudRelativePath: 'dir//file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('downloadFile tests:', () {
      test('downloadFile', () async {
        await ICloudStorage.downloadFile(
          containerId: containerId,
          cloudRelativePath: 'file',
          localPath: '/tmp/file',
        );
        expect(fakePlatform.downloadCloudRelativePath, 'file');
        expect(fakePlatform.downloadLocalPath, '/tmp/file');
        expect(fakePlatform.calls.last, 'downloadFile');
      });

      test('downloadFile rejects trailing slash cloudRelativePath', () async {
        expect(
          () async => ICloudStorage.downloadFile(
            containerId: containerId,
            cloudRelativePath: 'Documents/folder/',
            localPath: '/tmp/file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('downloadFile with invalid localPath', () async {
        expect(
          () async => ICloudStorage.downloadFile(
            containerId: containerId,
            cloudRelativePath: 'file',
            localPath: '',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('downloadFile with invalid cloudRelativePath', () async {
        expect(
          () async => ICloudStorage.downloadFile(
            containerId: containerId,
            cloudRelativePath: 'dir//file',
            localPath: '/tmp/file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('readInPlace tests:', () {
      test('readInPlace', () async {
        final result = await ICloudStorage.readInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
        );
        expect(result, 'contents');
        expect(fakePlatform.readInPlaceRelativePath, 'Documents/test.json');
        expect(fakePlatform.calls.last, 'readInPlace');
      });

      test('readInPlaceBytes', () async {
        final result = await ICloudStorage.readInPlaceBytes(
          containerId: containerId,
          relativePath: 'Documents/data.bin',
        );
        expect(result, isNotNull);
        expect(result, Uint8List.fromList([1, 2, 3]));
        expect(fakePlatform.readInPlaceRelativePath, 'Documents/data.bin');
        expect(fakePlatform.calls.last, 'readInPlaceBytes');
      });

      test('readInPlace rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlace(
            containerId: containerId,
            relativePath: 'Documents/folder/',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('readInPlace with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlace(
            containerId: containerId,
            relativePath: 'dir//file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('readInPlaceBytes rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlaceBytes(
            containerId: containerId,
            relativePath: 'Documents/folder/',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('readInPlaceBytes with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.readInPlaceBytes(
            containerId: containerId,
            relativePath: 'dir//file',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('writeInPlace tests:', () {
      test('writeInPlace', () async {
        await ICloudStorage.writeInPlace(
          containerId: containerId,
          relativePath: 'Documents/test.json',
          contents: '{"ok":true}',
        );
        expect(fakePlatform.writeInPlaceRelativePath, 'Documents/test.json');
        expect(fakePlatform.writeInPlaceContents, '{"ok":true}');
        expect(fakePlatform.calls.last, 'writeInPlace');
      });

      test('writeInPlaceBytes', () async {
        await ICloudStorage.writeInPlaceBytes(
          containerId: containerId,
          relativePath: 'Documents/data.bin',
          contents: Uint8List.fromList([4, 5, 6]),
        );
        expect(fakePlatform.writeInPlaceRelativePath, 'Documents/data.bin');
        expect(fakePlatform.calls.last, 'writeInPlaceBytes');
      });

      test('writeInPlace rejects trailing slash relativePath', () async {
        expect(
          () async => ICloudStorage.writeInPlace(
            containerId: containerId,
            relativePath: 'Documents/folder/',
            contents: 'data',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('writeInPlace with invalid relativePath', () async {
        expect(
          () async => ICloudStorage.writeInPlace(
            containerId: containerId,
            relativePath: 'dir//file',
            contents: 'data',
          ),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    test('rename uses move with derived path', () async {
      await ICloudStorage.rename(
        containerId: containerId,
        relativePath: 'Documents/config.json',
        newName: 'renamed.json',
      );
      expect(fakePlatform.moveToRelativePath, 'Documents/renamed.json');
    });

    test('rename on directory strips trailing slash for parent', () async {
      await ICloudStorage.rename(
        containerId: containerId,
        relativePath: 'Documents/folder/',
        newName: 'renamedFolder',
      );
      expect(fakePlatform.moveToRelativePath, 'Documents/renamedFolder');
    });

    test('rename handles root-level files', () async {
      await ICloudStorage.rename(
        containerId: containerId,
        relativePath: 'config.json',
        newName: 'renamed.json',
      );
      expect(fakePlatform.moveToRelativePath, 'renamed.json');
    });

    test('documentExists', () async {
      final result = await ICloudStorage.documentExists(
        containerId: containerId,
        relativePath: 'file',
      );
      expect(result, true);
    });

    test('delete accepts trailing slash', () async {
      await ICloudStorage.delete(
        containerId: containerId,
        relativePath: 'Documents/folder/',
      );
      expect(fakePlatform.calls.last, 'delete');
    });

    test('getMetadata accepts trailing slash', () async {
      await ICloudStorage.getMetadata(
        containerId: containerId,
        relativePath: 'Documents/folder/',
      );
      expect(fakePlatform.calls.last, 'getDocumentMetadata');
    });

    test('getMetadata returns ICloudFile', () async {
      final metadata = await ICloudStorage.getMetadata(
        containerId: containerId,
        relativePath: 'Documents/test.pdf',
      );
      expect(metadata?.relativePath, 'Documents/test.pdf');
    });

    test('getMetadata maps NSURL download status constants', () async {
      fakePlatform.documentMetadataResult = {
        'relativePath': 'Documents/test.pdf',
        'isDirectory': false,
        'downloadStatus': 'NSURLUbiquitousItemDownloadingStatusCurrent',
      };

      final metadata = await ICloudStorage.getMetadata(
        containerId: containerId,
        relativePath: 'Documents/test.pdf',
      );

      expect(metadata?.downloadStatus, DownloadStatus.current);
    });

    test('getDocumentMetadata returns raw map', () async {
      final metadata = await ICloudStorage.getDocumentMetadata(
        containerId: containerId,
        relativePath: 'Documents/test.pdf',
      );
      expect(metadata?['relativePath'], 'Documents/test.pdf');
    });
  });
}
