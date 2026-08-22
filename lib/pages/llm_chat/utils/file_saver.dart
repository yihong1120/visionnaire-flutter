// Cross-platform file saving helper used by chat.
//
// - On IO platforms, saves to the temporary directory and returns the path.
// - On web, throws UnsupportedError.
export 'file_saver_stub.dart' if (dart.library.io) 'file_saver_io.dart';
