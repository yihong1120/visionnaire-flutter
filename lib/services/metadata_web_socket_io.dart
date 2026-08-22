import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectMetadataWebSocket(Uri uri, {required String token}) {
  return IOWebSocketChannel.connect(
    uri,
    headers: <String, dynamic>{'Authorization': 'Bearer $token'},
    pingInterval: const Duration(seconds: 20),
    connectTimeout: const Duration(seconds: 10),
  );
}
