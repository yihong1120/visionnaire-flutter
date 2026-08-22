import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/models/detection_item.dart';

void main() {
  group('DetectionItem Model Tests', () {
    test('should create detection item with valid data', () {
      final detectionItem = DetectionItem(
        rect: const Rect.fromLTWH(10, 20, 100, 150),
        label: 'helmet',
      );

      expect(detectionItem.rect, equals(const Rect.fromLTWH(10, 20, 100, 150)));
      expect(detectionItem.label, equals('helmet'));
    });

    test('should handle different detection labels', () {
      final detectionItem = DetectionItem(
        rect: const Rect.fromLTWH(50, 60, 80, 120),
        label: 'safety_vest',
      );

      expect(detectionItem.label, equals('safety_vest'));
      expect(detectionItem.rect.left, equals(50));
      expect(detectionItem.rect.top, equals(60));
      expect(detectionItem.rect.width, equals(80));
      expect(detectionItem.rect.height, equals(120));
    });

    test('should handle bounding box properties', () {
      final detectionItem = DetectionItem(
        rect: const Rect.fromLTWH(0, 0, 200, 300),
        label: 'person',
      );

      expect(detectionItem.rect.left, equals(0));
      expect(detectionItem.rect.top, equals(0));
      expect(detectionItem.rect.right, equals(200));
      expect(detectionItem.rect.bottom, equals(300));
      expect(detectionItem.rect.width, equals(200));
      expect(detectionItem.rect.height, equals(300));
    });

    test('should handle small bounding boxes', () {
      final detectionItem = DetectionItem(
        rect: const Rect.fromLTWH(100, 150, 10, 15),
        label: 'small_object',
      );

      expect(detectionItem.rect.width, equals(10));
      expect(detectionItem.rect.height, equals(15));
      expect(detectionItem.label, equals('small_object'));
    });

    test('should handle large bounding boxes', () {
      final detectionItem = DetectionItem(
        rect: const Rect.fromLTWH(0, 0, 1920, 1080),
        label: 'full_screen',
      );

      expect(detectionItem.rect.width, equals(1920));
      expect(detectionItem.rect.height, equals(1080));
      expect(detectionItem.label, equals('full_screen'));
    });

    test('should create with different rect constructors', () {
      final detectionItem1 = DetectionItem(
        rect: Rect.fromPoints(const Offset(10, 20), const Offset(110, 170)),
        label: 'construction_cone',
      );

      expect(detectionItem1.rect.left, equals(10));
      expect(detectionItem1.rect.top, equals(20));
      expect(detectionItem1.rect.right, equals(110));
      expect(detectionItem1.rect.bottom, equals(170));
    });

    test('should handle center and size calculations', () {
      final detectionItem = DetectionItem(
        rect: const Rect.fromLTWH(50, 60, 100, 80),
        label: 'hazard',
      );

      expect(detectionItem.rect.center.dx, equals(100)); // 50 + 100/2
      expect(detectionItem.rect.center.dy, equals(100)); // 60 + 80/2
      expect(detectionItem.rect.size.width, equals(100));
      expect(detectionItem.rect.size.height, equals(80));
    });

    test('should handle const constructor', () {
      const detectionItem = DetectionItem(
        rect: Rect.fromLTWH(10, 20, 30, 40),
        label: 'const_item',
      );

      expect(detectionItem.rect.left, equals(10));
      expect(detectionItem.label, equals('const_item'));
    });

    test('should handle different safety equipment labels', () {
      final helmets = DetectionItem(
        rect: const Rect.fromLTWH(10, 10, 50, 50),
        label: 'helmet',
      );

      final vest = DetectionItem(
        rect: const Rect.fromLTWH(20, 60, 80, 120),
        label: 'safety_vest',
      );

      final boots = DetectionItem(
        rect: const Rect.fromLTWH(15, 180, 60, 40),
        label: 'safety_boots',
      );

      expect(helmets.label, equals('helmet'));
      expect(vest.label, equals('safety_vest'));
      expect(boots.label, equals('safety_boots'));
    });

    test('should handle edge case - zero-size rect', () {
      final detectionItem = DetectionItem(
        rect: const Rect.fromLTWH(100, 100, 0, 0),
        label: 'point',
      );

      expect(detectionItem.rect.width, equals(0));
      expect(detectionItem.rect.height, equals(0));
      expect(detectionItem.rect.isEmpty, isTrue);
    });
  });
}
