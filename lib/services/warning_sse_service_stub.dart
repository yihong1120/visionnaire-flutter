import 'warning_sse_service_common.dart';

Future<WarningSseConnection> connectWarningSse({
  required String baseUrl,
  required String label,
  required String streamId,
  required String streamKey,
  WarningSseTokenProvider? tokenProvider,
  required WarningSseMetadataCallback onMetadata,
  WarningSseErrorCallback? onError,
}) async {
  throw UnsupportedError('Warning SSE is not supported on this platform.');
}
