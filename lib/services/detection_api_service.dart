import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config_service.dart';
import 'auth_request_headers.dart';

/// Service class for object detection API integration.
///
/// Provides static methods for sending images to the backend detection API and parsing results.
class DetectionAPIService {
  /// Timeout for HTTP requests, in seconds.
  static const int timeoutSeconds = 600;

  /// Get the base URL from configuration service
  static Future<String> get baseUrl async {
    return await ApiConfigService.getApiUrl('detection');
  }

  /// Sends an image to the backend detection API and returns detection results.
  ///
  /// [imageFile] The image file to send (XFile or similar, must support readAsBytes and .path).
  /// [model] The detection model to use (e.g. 'yolo26n').
  /// [token] The authentication token.
  ///
  /// Returns a list of detection results, e.g. [[x1, y1, x2, y2, conf, classId], ...].
  static Future<List<dynamic>> detectObjects({
    required dynamic imageFile,
    Uint8List? imageBytes,
    String? filename,
    required String model,
    required String token,
  }) async {
    final baseUrlValue = await baseUrl;
    final Uri uri = Uri.parse("$baseUrlValue/detect");

    // Prepare multipart file for upload (web and non-web platforms differ)
    http.MultipartFile multipartFile;
    if (imageBytes != null) {
      multipartFile = http.MultipartFile.fromBytes(
        "image",
        imageBytes,
        filename: filename ?? "upload.png",
      );
    } else if (kIsWeb) {
      final List<int> bytes = await imageFile.readAsBytes();
      multipartFile = http.MultipartFile.fromBytes(
        "image",
        bytes,
        filename: filename ?? "upload.png",
      );
    } else {
      multipartFile =
          await http.MultipartFile.fromPath("image", imageFile.path);
    }

    // Build multipart request
    final http.MultipartRequest request = http.MultipartRequest("POST", uri)
      ..headers.addAll(AuthRequestHeaders.forRequest(token))
      ..fields["model"] = model
      ..files.add(multipartFile);

    // Send request and await response
    final http.StreamedResponse streamedResponse =
        await request.send().timeout(const Duration(seconds: timeoutSeconds));
    final http.Response response =
        await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final String decoded = utf8.decode(response.bodyBytes);
      return json.decode(decoded)
          as List<dynamic>; // e.g. [[x1,y1,x2,y2,conf,classId], ...]
    } else {
      final String decoded = utf8.decode(response.bodyBytes);
      final dynamic error = json.decode(decoded);
      // If backend returns 401/403, expects {"detail": "Unauthorized"} or similar
      throw Exception(error["detail"] ?? "Detection failed");
    }
  }
}
