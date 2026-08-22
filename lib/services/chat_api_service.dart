import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_config_service.dart';
import 'auth_request_headers.dart';
import '../pages/llm_chat/models/chat_attachment_model.dart';

class ChatAPIService {
  static const int timeoutSeconds = 600;

  static Future<String> get baseUrl async {
    return await ApiConfigService.getApiUrl('chat');
  }

  static Map<String, String> _jsonHeaders(String token) => {
        'Content-Type': 'application/json',
        ...AuthRequestHeaders.forRequest(token),
      };

  Future<List<Map<String, dynamic>>> getChats(String token) async {
    final base = await baseUrl;
    final resp = await http.get(Uri.parse('$base/chats'), headers: {
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));

    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(body) as List);
    }
    throw Exception(_detail(body, 'Fetch chat list failed'));
  }

  Future<List<Map<String, dynamic>>> getChatHistory(
      String token, int chatId) async {
    final base = await baseUrl;
    final resp = await http.get(Uri.parse('$base/chats/$chatId'), headers: {
      ...AuthRequestHeaders.forRequest(token),
    }).timeout(const Duration(seconds: timeoutSeconds));

    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode == 200) {
      final decoded = json.decode(body);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(decoded);
      }
      if (decoded is Map) {
        final history = decoded['history'] ?? decoded['messages'] ?? decoded;
        if (history is List) {
          return List<Map<String, dynamic>>.from(history);
        }
      }
      return [];
    }
    throw Exception(_detail(body, 'Fetch chat history failed'));
  }

  Future<Map<String, dynamic>> createRoom(
    String token, {
    String? title,
    String? systemPrompt,
  }) async {
    final base = await baseUrl;
    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (systemPrompt != null) payload['system_prompt'] = systemPrompt;

    final resp = await http
        .post(
          Uri.parse('$base/chat/rooms'),
          headers: _jsonHeaders(token),
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return json.decode(body) as Map<String, dynamic>;
    }
    throw Exception(_detail(body, 'Create room failed'));
  }

  Future<void> updateRoom(String token, int roomId, String title) async {
    final base = await baseUrl;
    final resp = await http
        .put(
          Uri.parse('$base/chat/rooms/$roomId'),
          headers: _jsonHeaders(token),
          body: json.encode({'title': title}),
        )
        .timeout(const Duration(seconds: timeoutSeconds));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          _detail(utf8.decode(resp.bodyBytes), 'Update room failed'));
    }
  }

  Future<void> deleteRoom(String token, int roomId) async {
    final base = await baseUrl;
    final resp = await http.delete(
      Uri.parse('$base/chat/rooms/$roomId'),
      headers: {...AuthRequestHeaders.forRequest(token)},
    ).timeout(const Duration(seconds: timeoutSeconds));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          _detail(utf8.decode(resp.bodyBytes), 'Delete room failed'));
    }
  }

  Future<void> deleteMessage(String token, int roomId, int msgId) async {
    final base = await baseUrl;
    final resp = await http.delete(
      Uri.parse('$base/chat/rooms/$roomId/messages/$msgId'),
      headers: {...AuthRequestHeaders.forRequest(token)},
    ).timeout(const Duration(seconds: timeoutSeconds));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          _detail(utf8.decode(resp.bodyBytes), 'Delete message failed'));
    }
  }

  // ──────────────────────────── attachments ─────────────────────────────────

  /// `POST /chats/{chat_id}/attachments` — Upload files as draft attachments.
  Future<List<ChatAttachment>> uploadAttachments(
    String token,
    int chatId,
    List<LocalAttachmentBytes> files,
  ) async {
    final base = await baseUrl;
    final uri = Uri.parse('$base/chats/$chatId/attachments');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token));

    for (final f in files) {
      final parts = f.mime.split('/');
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          f.bytes,
          filename: f.name,
          contentType: MediaType(
            parts[0],
            parts.length > 1 ? parts[1] : 'octet-stream',
          ),
        ),
      );
    }

    final resp = await request.send();
    final bodyStr = await resp.stream.bytesToString();
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final data = json.decode(bodyStr) as List;
      return data
          .map((e) => ChatAttachment.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_detail(bodyStr, 'Upload attachments failed'));
  }

  /// `DELETE /chat/attachments/{attachmentId}` — Delete a draft attachment.
  Future<void> deleteAttachment(String token, int attachmentId) async {
    final base = await baseUrl;
    final resp = await http.delete(
      Uri.parse('$base/chat/attachments/$attachmentId'),
      headers: {...AuthRequestHeaders.forRequest(token)},
    ).timeout(const Duration(seconds: timeoutSeconds));

    if (resp.statusCode >= 300) {
      throw Exception(
          _detail(utf8.decode(resp.bodyBytes), 'Delete attachment failed'));
    }
  }

  // ──────────────────────────── streaming ─────────────────────────────────

  Stream<Map<String, dynamic>> streamMessage({
    required int chatId,
    required String token,
    required String text,
    List<int>? attachmentIds,
    http.Client? client,
  }) async* {
    final base = await baseUrl;
    final uri = Uri.parse('$base/chats/$chatId/stream');
    final request =
        _buildStreamMultipartRequest(uri, token, text, attachmentIds);
    final httpClient = client ?? http.Client();
    yield* _sendAndParseStream(httpClient, request, ownClient: client == null);
  }

  Stream<Map<String, dynamic>> streamEditMessage({
    required int chatId,
    required int msgId,
    required String token,
    required String text,
    List<int>? attachmentIds,
    http.Client? client,
  }) async* {
    final base = await baseUrl;
    final uri = Uri.parse('$base/chats/$chatId/messages/$msgId/stream');
    final request =
        _buildStreamMultipartRequest(uri, token, text, attachmentIds);
    final httpClient = client ?? http.Client();
    yield* _sendAndParseStream(httpClient, request, ownClient: client == null);
  }

  // ─────────────────── private helpers ────────────────────────────────────

  static http.MultipartRequest _buildStreamMultipartRequest(
    Uri uri,
    String token,
    String text,
    List<int>? attachmentIds,
  ) {
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token))
      ..headers['Accept'] = 'text/event-stream'
      ..fields['content'] = text;

    if (attachmentIds != null && attachmentIds.isNotEmpty) {
      request.fields['attachment_ids'] = jsonEncode(attachmentIds);
    }
    return request;
  }

  Stream<Map<String, dynamic>> _sendAndParseStream(
    http.Client httpClient,
    http.BaseRequest request, {
    required bool ownClient,
  }) async* {
    try {
      final streamedResp = await httpClient.send(request);

      if (streamedResp.statusCode != 200) {
        final body = await streamedResp.stream.bytesToString();
        throw Exception(
            'Stream request failed (${streamedResp.statusCode}): $body');
      }

      var buffer = '';
      await for (final chunk in streamedResp.stream.transform(utf8.decoder)) {
        buffer += chunk;

        while (true) {
          final delimIdx = buffer.indexOf('\n\n');
          if (delimIdx == -1) break;

          final rawEvent = buffer.substring(0, delimIdx);
          buffer = buffer.substring(delimIdx + 2);
          if (rawEvent.trim().isEmpty) continue;

          final lines = rawEvent.split('\n');
          var lastEventName = '';
          final dataLines = <String>[];

          for (final line in lines) {
            if (line.startsWith('event:')) {
              lastEventName = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              dataLines.add(line.substring(5).trimLeft());
            }
          }

          if (dataLines.isEmpty) continue;
          final data = dataLines.join('\n').trim();
          if (data.isEmpty) continue;

          if (lastEventName == 'error') {
            yield {'type': 'error', 'message': _safeDetail(data)};
            return;
          }

          if (data == '[DONE]') {
            yield {'type': 'done'};
            return;
          }

          try {
            final chunkObj = json.decode(data) as Map<String, dynamic>;
            final choices = chunkObj['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;

            final choice = choices.first as Map<String, dynamic>;
            final delta = choice['delta'] as Map<String, dynamic>?;

            if (delta != null) {
              final content = delta['content'];
              if (content is String && content.isNotEmpty) {
                yield {'type': 'token', 'content': content};
              }
            }
          } catch (e) {
            debugPrint('Failed to parse SSE chunk: $data, error: $e');
          }
        }
      }
      yield {'type': 'done'};
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  static String _detail(String rawBody, String fallback) {
    try {
      final obj = json.decode(rawBody);
      if (obj is Map && obj.containsKey('detail')) {
        return obj['detail'].toString();
      }
    } catch (_) {}
    return rawBody.isNotEmpty ? rawBody : fallback;
  }

  static String _safeDetail(String rawData) {
    try {
      final obj = json.decode(rawData);
      if (obj is Map && obj.containsKey('detail')) {
        return obj['detail'].toString();
      }
    } catch (_) {}
    return rawData;
  }
}
