import 'package:flutter/services.dart';

/// The state of a transfer progress stream event.
enum ICloudTransferProgressType {
  /// A progress update, where [ICloudTransferProgress.percent] is non-null.
  progress,

  /// The transfer finished successfully.
  done,

  /// The transfer failed with a platform error.
  error,
}

/// A typed progress event emitted from upload/download progress streams.
///
/// Native progress streams can deliver progress updates, terminal completion,
/// or errors. This wrapper makes it easy to handle all three as data events.
class ICloudTransferProgress {
  /// Creates an error event.
  const ICloudTransferProgress.error(PlatformException exception)
      : this._(type: ICloudTransferProgressType.error, exception: exception);

  const ICloudTransferProgress._({
    required this.type,
    this.percent,
    this.exception,
  });

  /// Creates a progress update event.
  const ICloudTransferProgress.progress(double percent)
      : this._(type: ICloudTransferProgressType.progress, percent: percent);

  /// Creates a completion event.
  const ICloudTransferProgress.done()
      : this._(type: ICloudTransferProgressType.done);

  /// The kind of event.
  final ICloudTransferProgressType type;

  /// Upload/download progress as a percentage.
  ///
  /// This is only set when [type] is [ICloudTransferProgressType.progress].
  final double? percent;

  /// The underlying platform exception.
  ///
  /// This is only set when [type] is [ICloudTransferProgressType.error].
  final PlatformException? exception;

  /// Whether this event represents a progress update.
  bool get isProgress => type == ICloudTransferProgressType.progress;

  /// Whether this event represents successful completion.
  bool get isDone => type == ICloudTransferProgressType.done;

  /// Whether this event represents a failure.
  bool get isError => type == ICloudTransferProgressType.error;
}
