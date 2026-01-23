/// An exception class used for development. It's ued when invalid argument
/// is passed to the API
class InvalidArgumentException implements Exception {
  /// Constructor takes the exception message as an argument
  InvalidArgumentException(this._message);
  final String _message;

  /// Method to print the error message
  @override
  String toString() => 'InvalidArgumentException: $_message';
}

/// A class contains the error code from PlatformException
class PlatformExceptionCode {
  /// The code indicates iCloud container ID is not valid, or user is not signed
  /// in to iCloud, or user denied iCloud permission for this app
  static const String iCloudConnectionOrPermission = 'E_CTR';

  /// The code indicates file not found
  static const String fileNotFound = 'E_FNF';

  /// The code indicates other error from native code
  static const String nativeCodeError = 'E_NAT';

  /// The code indicates a metadata query operation timed out
  static const String timeout = 'E_TIMEOUT';
}
