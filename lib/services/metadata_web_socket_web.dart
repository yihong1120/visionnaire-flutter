import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectMetadataWebSocket(Uri uri, {required String token}) {
  // Browser WebSocket APIs do not allow custom Authorization headers.
  // Web auth for this endpoint must be handled by cookie/session, query token,
  // or a backend-supported subprotocol.
  return HtmlWebSocketChannel.connect(uri);
}
