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

  group('icloudAvailable tests:', () {
    test('returns true when iCloud is available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'icloudAvailable') {
          return true;
        }
        return null;
      });

      final result = await platform.icloudAvailable();

      expect(mockMethodCall.method, 'icloudAvailable');
      expect(result, true);
    });

    test('returns false when iCloud is unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'icloudAvailable') {
          return false;
        }
        return null;
      });

      final result = await platform.icloudAvailable();

      expect(mockMethodCall.method, 'icloudAvailable');
      expect(result, false);
    });

    test('returns false when platform returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'icloudAvailable') {
          return null;
        }
        return null;
      });

      final result = await platform.icloudAvailable();

      expect(mockMethodCall.method, 'icloudAvailable');
      expect(result, false);
    });
  });

  group('copy tests:', () {
    test('copy calls platform method with correct arguments', () async {
      await platform.copy(
        containerId: containerId,
        fromRelativePath: 'source.txt',
        toRelativePath: 'destination.txt',
      );

      final args = mockArguments();
      expect(mockMethodCall.method, 'copy');
      expect(args['containerId'], containerId);
      expect(args['fromRelativePath'], 'source.txt');
      expect(args['toRelativePath'], 'destination.txt');
    });

    test('copy with nested paths', () async {
      await platform.copy(
        containerId: containerId,
        fromRelativePath: 'folder/source.txt',
        toRelativePath: 'another/folder/dest.txt',
      );

      final args = mockArguments();
      expect(mockMethodCall.method, 'copy');
      expect(args['containerId'], containerId);
      expect(args['fromRelativePath'], 'folder/source.txt');
      expect(args['toRelativePath'], 'another/folder/dest.txt');
    });
  });

  group('readDocument tests:', () {
    test('readDocument returns Uint8List when document exists', () async {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'readDocument') {
          return testData;
        }
        return null;
      });

      final result = await platform.readDocument(
        containerId: containerId,
        relativePath: 'document.txt',
      );

      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'document.txt');
      expect(result, testData);
    });

    test('readDocument returns null when document does not exist', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'readDocument') {
          return null;
        }
        return null;
      });

      final result = await platform.readDocument(
        containerId: containerId,
        relativePath: 'nonexistent.txt',
      );

      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'nonexistent.txt');
      expect(result, isNull);
    });
  });

  group('writeDocument tests:', () {
    test('writeDocument sends correct arguments', () async {
      final testData = Uint8List.fromList([10, 20, 30, 40, 50]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'writeDocument') {
          return null;
        }
        return null;
      });

      await platform.writeDocument(
        containerId: containerId,
        relativePath: 'document.txt',
        data: testData,
      );

      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'document.txt');
      expect(args['data'], testData);
    });
  });

  group('documentExists tests:', () {
    test('documentExists returns true when document exists', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'documentExists') {
          return true;
        }
        return null;
      });

      final result = await platform.documentExists(
        containerId: containerId,
        relativePath: 'existing.txt',
      );

      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'existing.txt');
      expect(result, true);
    });

    test('documentExists returns false when document does not exist', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'documentExists') {
          return false;
        }
        return null;
      });

      final result = await platform.documentExists(
        containerId: containerId,
        relativePath: 'nonexistent.txt',
      );

      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'nonexistent.txt');
      expect(result, false);
    });

    test('documentExists returns false when platform returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'documentExists') {
          return null;
        }
        return null;
      });

      final result = await platform.documentExists(
        containerId: containerId,
        relativePath: 'document.txt',
      );

      expect(result, false);
    });
  });

  group('getContainerPath tests:', () {
    test('getContainerPath returns path when available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'getContainerPath') {
          return '/Users/test/Library/Mobile Documents/iCloud~com~example~app';
        }
        return null;
      });

      final result = await platform.getContainerPath(containerId: containerId);

      expect(mockMethodCall.method, 'getContainerPath');
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(result, isNotNull);
      expect(
        result,
        equals('/Users/test/Library/Mobile Documents/iCloud~com~example~app'),
      );
    });

    test('getContainerPath returns null when path unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'getContainerPath') {
          return null;
        }
        return null;
      });

      final result = await platform.getContainerPath(containerId: containerId);

      expect(mockMethodCall.method, 'getContainerPath');
      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(result, isNull);
    });
  });

  group('getDocumentMetadata tests:', () {
    test('getDocumentMetadata returns metadata map when document exists',
        () async {
      final testMetadata = <dynamic, dynamic>{
        'sizeInBytes': 1024,
        'creationDate': 1234567890.0,
        'modificationDate': 1234567900.0,
        'isDirectory': false,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'getDocumentMetadata') {
          return testMetadata;
        }
        return null;
      });

      final result = await platform.getDocumentMetadata(
        containerId: containerId,
        relativePath: 'document.txt',
      );

      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'document.txt');
      expect(result, isNotNull);
      expect(result!['sizeInBytes'], 1024);
      expect(result['creationDate'], 1234567890.0);
      expect(result['modificationDate'], 1234567900.0);
      expect(result['isDirectory'], false);
    });

    test('getDocumentMetadata returns null when document does not exist',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'getDocumentMetadata') {
          return null;
        }
        return null;
      });

      final result = await platform.getDocumentMetadata(
        containerId: containerId,
        relativePath: 'nonexistent.txt',
      );

      final args = mockArguments();
      expect(args['containerId'], containerId);
      expect(args['relativePath'], 'nonexistent.txt');
      expect(result, isNull);
    });

    test('getDocumentMetadata correctly converts keys to strings', () async {
      final testMetadata = <dynamic, dynamic>{
        'name': 'test.txt',
        'size': 2048,
        123: 'numeric_key',
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method == 'getDocumentMetadata') {
          return testMetadata;
        }
        return null;
      });

      final result = await platform.getDocumentMetadata(
        containerId: containerId,
        relativePath: 'document.txt',
      );

      expect(result, isNotNull);
      expect(result!['name'], 'test.txt');
      expect(result['size'], 2048);
      expect(result['123'], 'numeric_key');
      // Verify all keys are strings (result.keys is already Iterable<String>)
      expect(result.keys, everyElement(isA<String>()));
    });
  });

  group(
    'downloadAndRead tests:',
    () {
      test('downloadAndRead with progress: verify progress stream emissions',
          () async {
        // Set up mock for createEventChannel and downloadAndRead
        var eventChannelName = '';

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          mockMethodCall = methodCall;
          switch (methodCall.method) {
            case 'createEventChannel':
              eventChannelName =
                  (methodCall.arguments as Map)['eventChannelName'] as String;
              return null;
            case 'downloadAndRead':
              // Return mock file content
              return Uint8List.fromList([1, 2, 3, 4, 5]);
            default:
              return null;
          }
        });

        // Capture the stream passed to onProgress callback
        Stream<ICloudTransferProgress>? capturedStream;
        final progressCallback = expectAsync1(
          (Stream<ICloudTransferProgress> stream) {
            capturedStream = stream;
          },
        );

        // Call downloadAndRead with onProgress
        final resultFuture = platform.downloadAndRead(
          containerId: containerId,
          relativePath: 'test.txt',
          onProgress: progressCallback,
        );

        // Wait for the event channel to be created
        await Future<void>.delayed(Duration.zero);

        // Set up mock stream handler for the created event channel
        final eventChannel = EventChannel(eventChannelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (Object? arguments, MockStreamHandlerEventSink events) {
              // Simulate progress updates
              events
                ..success(0.0)
                ..success(0.25)
                ..success(0.50)
                ..success(0.75)
                ..success(1.0)
                ..endOfStream();
            },
          ),
        );

        // Verify stream emissions
        await expectLater(
          capturedStream,
          emitsInOrder([
            isA<ICloudTransferProgress>()
                .having((e) => e.isProgress, 'isProgress', true)
                .having((e) => e.percent, 'percent', 0.0),
            isA<ICloudTransferProgress>()
                .having((e) => e.isProgress, 'isProgress', true)
                .having((e) => e.percent, 'percent', 0.25),
            isA<ICloudTransferProgress>()
                .having((e) => e.isProgress, 'isProgress', true)
                .having((e) => e.percent, 'percent', 0.50),
            isA<ICloudTransferProgress>()
                .having((e) => e.isProgress, 'isProgress', true)
                .having((e) => e.percent, 'percent', 0.75),
            isA<ICloudTransferProgress>()
                .having((e) => e.isProgress, 'isProgress', true)
                .having((e) => e.percent, 'percent', 1.0),
            isA<ICloudTransferProgress>()
                .having((e) => e.isDone, 'isDone', true),
            emitsDone,
          ]),
        );

        // Verify the method returns file content
        final result = await resultFuture;
        expect(result, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
      });

      test(
        'downloadAndRead with progress: verify file '
        'content returned after progress',
        () async {
          // Set up mock for createEventChannel and downloadAndRead
          var eventChannelName = '';

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            mockMethodCall = methodCall;
            switch (methodCall.method) {
              case 'createEventChannel':
                eventChannelName =
                    (methodCall.arguments as Map)['eventChannelName'] as String;
                return null;
              case 'downloadAndRead':
                final args =
                    (methodCall.arguments as Map).cast<String, Object?>();
                expect(args['containerId'], containerId);
                expect(args['cloudFileName'], 'document.pdf');
                expect(args['eventChannelName'], isNotEmpty);
                // Return mock file content
                return Uint8List.fromList(
                  [0xFF, 0xD8, 0xFF, 0xE0],
                ); // JPEG header
              default:
                return null;
            }
          });

          // Capture the stream and track progress
          Stream<ICloudTransferProgress>? capturedStream;
          final progressValues = <double>[];
          final progressCallback = expectAsync1(
            (Stream<ICloudTransferProgress> stream) {
              capturedStream = stream;
            },
          );

          // Call downloadAndRead
          final resultFuture = platform.downloadAndRead(
            containerId: containerId,
            relativePath: 'document.pdf',
            onProgress: progressCallback,
          );

          // Wait for event channel setup
          await Future<void>.delayed(Duration.zero);

          // Set up mock stream handler
          final eventChannel = EventChannel(eventChannelName);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (Object? arguments, MockStreamHandlerEventSink events) {
                // Simulate progress
                events
                  ..success(0.0)
                  ..success(0.33)
                  ..success(0.66)
                  ..success(1.0)
                  ..endOfStream();
              },
            ),
          );

          // Listen to stream and collect values
          capturedStream!.listen((event) {
            if (event.isProgress) {
              progressValues.add(event.percent!);
            }
          });

          // Wait for result
          final result = await resultFuture;

          // Verify file content is returned
          expect(result, isNotNull);
          expect(result, equals(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])));

          // Wait for all stream events to be processed
          await Future<void>.delayed(const Duration(milliseconds: 10));

          // Verify progress was tracked
          expect(progressValues, isNotEmpty);
          expect(progressValues.first, 0.0);
          expect(progressValues.last, 1.0);
        },
      );

      test(
        'downloadAndRead with progress: surfaces platform errors as events',
        () async {
          // Arrange: set up method channel to create an event channel and
          // respond to downloadAndRead.
          var eventChannelName = '';
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            mockMethodCall = methodCall;
            switch (methodCall.method) {
              case 'createEventChannel':
                eventChannelName =
                    (methodCall.arguments as Map)['eventChannelName'] as String;
                return null;
              case 'downloadAndRead':
                return Uint8List.fromList([1, 2, 3]);
              default:
                return null;
            }
          });

          Stream<ICloudTransferProgress>? capturedStream;
          final progressCallback = expectAsync1(
            (Stream<ICloudTransferProgress> stream) {
              capturedStream = stream;
            },
          );

          // Act: call downloadAndRead and then emit an error from the event
          // channel.
          await platform.downloadAndRead(
            containerId: containerId,
            relativePath: 'test.txt',
            onProgress: progressCallback,
          );

          await Future<void>.delayed(Duration.zero);

          final eventChannel = EventChannel(eventChannelName);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (Object? arguments, MockStreamHandlerEventSink events) {
                events.error(
                  code: 'E_NAT',
                  message: 'Native Code Error',
                  details: 'boom',
                );
              },
            ),
          );

          // Assert: the progress stream delivers an error event and then ends.
          await expectLater(
            capturedStream,
            emitsInOrder([
              isA<ICloudTransferProgress>()
                  .having((e) => e.isError, 'isError', true)
                  .having((e) => e.exception?.code, 'code', 'E_NAT'),
              emitsDone,
            ]),
          );
        },
      );
    },
  );

  group('Timeout error handling', () {
    test('readDocument handles E_TIMEOUT error code', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
          code: 'E_TIMEOUT',
          message: 'Metadata query operation timed out after 30 seconds',
        );
      });

      await expectLater(
        platform.readDocument(
          containerId: containerId,
          relativePath: 'test.txt',
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'E_TIMEOUT',
          ),
        ),
      );
    });

    test('delete handles E_TIMEOUT error code', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
          code: 'E_TIMEOUT',
          message: 'Metadata query operation timed out after 30 seconds',
        );
      });

      await expectLater(
        platform.delete(containerId: containerId, relativePath: 'test.txt'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'E_TIMEOUT',
          ),
        ),
      );
    });

    test('move handles E_TIMEOUT error code', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
          code: 'E_TIMEOUT',
          message: 'Metadata query operation timed out after 30 seconds',
        );
      });

      await expectLater(
        platform.move(
          containerId: containerId,
          fromRelativePath: 'test.txt',
          toRelativePath: 'moved.txt',
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'E_TIMEOUT',
          ),
        ),
      );
    });

    test('getDocumentMetadata handles E_TIMEOUT error code', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
          code: 'E_TIMEOUT',
          message: 'Metadata query operation timed out after 30 seconds',
        );
      });

      await expectLater(
        platform.getDocumentMetadata(
          containerId: containerId,
          relativePath: 'test.txt',
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'E_TIMEOUT',
          ),
        ),
      );
    });
  });
}
