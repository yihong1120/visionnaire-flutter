import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectMetadataWebSocket(Uri uri, {required String token}) {
  return WebSocketChannel.connect(uri);
}
