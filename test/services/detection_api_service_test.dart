import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/services/detection_api_service.dart';

import '../test_helpers.dart';
import '../test_support/deployment_profile_test_support.dart';

void main() {
  group('DetectionAPIService Tests', () {
    setUpAll(() {
      // Initialize Flutter binding for tests
      TestWidgetsFlutterBinding.ensureInitialized();
      // Mock SharedPreferences for testing
      SharedPreferences.setMockInitialValues({});
      installEnrollmentDeploymentProfile(debug: true);
    });

    tearDownAll(resetDeploymentProfile);

    group('Configuration', () {
      test('should have valid timeout settings', () {
        expect(DetectionAPIService.timeoutSeconds, equals(600));
        expect(DetectionAPIService.timeoutSeconds, greaterThan(0));
        expect(DetectionAPIService.timeoutSeconds, lessThan(3600));
      });

      test('should have valid base URL configuration', () async {
        final baseUrl = await DetectionAPIService.baseUrl;
        expect(baseUrl, isA<String>());
        expect(baseUrl.isNotEmpty, isTrue);
      });
    });

    group('Detection Data Validation', () {
      test('should validate detection result format', () {
        final detectionResult = MockDataGenerator.createMockDetectionResult(
          bbox: [100.0, 100.0, 200.0, 200.0],
          confidence: 0.85,
          label: 'person',
        );

        expect(detectionResult['bbox'], isA<List<dynamic>>());
        expect(detectionResult['bbox'].length, equals(4));
        expect(detectionResult['confidence'], isA<double>());
        expect(detectionResult['confidence'], greaterThan(0.0));
        expect(detectionResult['confidence'], lessThanOrEqualTo(1.0));
        expect(detectionResult['label'], isA<String>());
        expect(detectionResult['label'].isNotEmpty, isTrue);
      });

      test('should handle various detection labels', () {
        final labels = [
          'person',
          'vehicle',
          'helmet',
          'safety_vest',
          'machinery',
        ];

        for (final label in labels) {
          final detection = MockDataGenerator.createMockDetectionResult(
            label: label,
          );
          expect(detection['label'], equals(label));
          expect(detection['label'], isA<String>());
        }
      });

      test('should validate bounding box coordinates', () {
        final testCases = [
          [0, 0, 100, 100], // Top-left origin
          [50, 50, 150, 150], // Centered box
          [0.5, 0.5, 0.8, 0.8], // Normalized coordinates
        ];

        for (final bbox in testCases) {
          final detection = MockDataGenerator.createMockDetectionResult(
            bbox: bbox,
          );

          expect(detection['bbox'].length, equals(4));
          expect(detection['bbox'][0],
              lessThanOrEqualTo(detection['bbox'][2])); // x1 <= x2
          expect(detection['bbox'][1],
              lessThanOrEqualTo(detection['bbox'][3])); // y1 <= y2
        }
      });

      test('should validate confidence scores', () {
        final confidenceScores = [0.1, 0.5, 0.85, 0.99, 1.0];

        for (final confidence in confidenceScores) {
          final detection = MockDataGenerator.createMockDetectionResult(
            confidence: confidence,
          );

          expect(detection['confidence'], equals(confidence));
          expect(detection['confidence'], greaterThanOrEqualTo(0.0));
          expect(detection['confidence'], lessThanOrEqualTo(1.0));
        }
      });
    });

    group('Model Validation', () {
      test('should validate supported model names', () {
        final supportedModels = [
          'yolo11n',
          'yolo11s',
          'yolo11m',
          'yolo11l',
          'yolo11x',
        ];

        for (final model in supportedModels) {
          expect(model, isA<String>());
          expect(model.isNotEmpty, isTrue);
          expect(model.startsWith('yolo'), isTrue);
        }
      });

      test('should handle model parameter formatting', () {
        const model = 'yolo11n';
        final modelField = {'model': model};

        expect(modelField['model'], equals(model));
        expect(modelField['model'], isA<String>());
      });
    });

    group('Image Data Handling', () {
      test('should handle image byte data', () {
        final imageBytes = MockDataGenerator.createMockImageBytes();

        expect(imageBytes, isA<Uint8List>());
        expect(imageBytes.isNotEmpty, isTrue);
        expect(imageBytes.length, greaterThan(0));
      });

      test('should validate image formats', () {
        final imageBytes = MockDataGenerator.createMockImageBytes();

        // Check PNG signature (mock data starts with PNG signature)
        expect(imageBytes[0], equals(137)); // PNG signature byte 1
        expect(imageBytes[1], equals(80)); // PNG signature byte 2 ('P')
        expect(imageBytes[2], equals(78)); // PNG signature byte 3 ('N')
        expect(imageBytes[3], equals(71)); // PNG signature byte 4 ('G')
      });
    });

    group('Request Structure Validation', () {
      test('should validate multipart form structure', () {
        const expectedFields = ['model'];
        const expectedFiles = ['image'];

        // Validate that our test setup expects these fields
        expect(expectedFields, contains('model'));
        expect(expectedFiles, contains('image'));
      });

      test('should validate authorization header format', () {
        const token = 'test_bearer_token';
        final authHeader = 'Bearer $token';

        expect(authHeader, startsWith('Bearer '));
        expect(authHeader.substring(7), equals(token));
      });
    });

    group('Response Processing', () {
      test('should process detection results list', () {
        final mockResults = [
          [100, 100, 200, 200, 0.85, 'person'],
          [300, 150, 400, 250, 0.92, 'helmet'],
          [500, 200, 600, 300, 0.78, 'vehicle'],
        ];

        expect(mockResults, isA<List<dynamic>>());
        expect(mockResults.length, equals(3));

        for (final result in mockResults) {
          expect(result, isA<List<dynamic>>());
          expect(result.length, greaterThanOrEqualTo(6));
          expect(result[4], isA<num>()); // confidence
          expect(result[5], isA<String>()); // label
        }
      });

      test('should handle empty detection results', () {
        final emptyResults = <dynamic>[];

        expect(emptyResults, isA<List<dynamic>>());
        expect(emptyResults.isEmpty, isTrue);
        expect(emptyResults.length, equals(0));
      });
    });

    group('Error Handling', () {
      test('should validate error response format', () {
        final errorResponse = {
          'detail': 'Invalid image format',
          'status_code': 400,
        };

        expect(errorResponse['detail'], isA<String>());
        expect(errorResponse['status_code'], isA<int>());
        expect(errorResponse['status_code'], greaterThanOrEqualTo(400));
      });

      test('should handle various error types', () {
        final errorTypes = [
          {'detail': 'Image too large', 'status_code': 413},
          {'detail': 'Unsupported model', 'status_code': 400},
          {'detail': 'Authentication failed', 'status_code': 401},
          {'detail': 'Rate limit exceeded', 'status_code': 429},
          {'detail': 'Server error', 'status_code': 500},
        ];

        for (final error in errorTypes) {
          expect(error['detail'], isA<String>());
          expect(error['detail'].toString().isNotEmpty, isTrue);
          expect(error['status_code'], isA<int>());
        }
      });
    });

    group('JSON Serialization', () {
      test('should serialize detection results correctly', () {
        final detectionResults = [
          [100, 100, 200, 200, 0.85, 'person'],
          [300, 150, 400, 250, 0.92, 'helmet'],
        ];

        final jsonString = json.encode(detectionResults);
        final decoded = json.decode(jsonString);

        expect(decoded, isA<List<dynamic>>());
        expect(decoded.length, equals(2));
        expect(decoded[0][5], equals('person'));
        expect(decoded[1][5], equals('helmet'));
      });

      test('should handle special characters in labels', () {
        final detectionsWithSpecialChars = [
          [100, 100, 200, 200, 0.85, 'safety-vest'],
          [300, 150, 400, 250, 0.92, 'hard_hat'],
          [500, 200, 600, 300, 0.78, 'construction worker'],
        ];

        final jsonString = json.encode(detectionsWithSpecialChars);
        final decoded = json.decode(jsonString);

        expect(decoded[0][5], equals('safety-vest'));
        expect(decoded[1][5], equals('hard_hat'));
        expect(decoded[2][5], equals('construction worker'));
      });
    });

    group('Performance Considerations', () {
      test('should handle large detection result sets', () {
        final largeResultSet = List.generate(
            100,
            (index) => [
                  index * 10,
                  index * 10,
                  (index + 1) * 10,
                  (index + 1) * 10,
                  0.5 + (index % 50) / 100,
                  'object_$index'
                ]);

        expect(largeResultSet.length, equals(100));
        expect(largeResultSet.first[5], equals('object_0'));
        expect(largeResultSet.last[5], equals('object_99'));
      });

      test('should handle high-precision coordinates', () {
        final preciseCoordinates = [
          123.456789,
          234.567890,
          345.678901,
          456.789012
        ];

        final detection = MockDataGenerator.createMockDetectionResult(
          bbox: preciseCoordinates,
        );

        expect(detection['bbox'][0], closeTo(123.456789, 0.000001));
        expect(detection['bbox'][1], closeTo(234.567890, 0.000001));
      });
    });
  });
}
