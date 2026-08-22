import 'warning_sse_service_common.dart';
import 'warning_sse_service_stub.dart'
    if (dart.library.io) 'warning_sse_service_io.dart'
    if (dart.library.js_interop) 'warning_sse_service_web.dart' as platform;

export 'warning_sse_service_common.dart';

Future<WarningSseConnection> connectWarningSse({
  required String baseUrl,
  required String label,
  required String streamId,
  required String streamKey,
  WarningSseTokenProvider? tokenProvider,
  required WarningSseMetadataCallback onMetadata,
  WarningSseErrorCallback? onError,
}) {
  return platform.connectWarningSse(
    baseUrl: baseUrl,
    label: label,
    streamId: streamId,
    streamKey: streamKey,
    tokenProvider: tokenProvider,
    onMetadata: onMetadata,
    onError: onError,
  );
}
