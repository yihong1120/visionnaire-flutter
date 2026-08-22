import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/widgets/detection_painter.dart';

import '../test_helpers.dart';

void main() {
  group('Synchronized Detection Widget Tests', () {
    Widget createTestApp(Widget child) {
      return createLocalizedTestApp(child);
    }

    Widget buildOverlayWidget({
      Key? key,
      required Uint8List rawBytes,
      required double originalWidth,
      required double originalHeight,
      required List<List<Offset>> conePolygons,
      required List<List<Offset>> polePolygons,
      required List<DetectionItem> detectionItems,
      required bool showOverlays,
    }) {
      return Builder(
        builder: (context) => DetectionOverlayWidget(
          key: key,
          rawBytes: rawBytes,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          conePolygons: conePolygons,
          polePolygons: polePolygons,
          detectionItems: detectionItems,
          showOverlays: showOverlays,
        ),
      );
    }

    testWidgets('should handle image and overlay updates synchronously',
        (WidgetTester tester) async {
      final Uint8List testImageData1 = MockDataGenerator.createMockImageBytes();
      final Uint8List testImageData2 =
          Uint8List.fromList(MockDataGenerator.createMockImageBytes());

      // Create test detection data
      final List<DetectionItem> detections1 = [
        DetectionItem(
            rect: const Rect.fromLTRB(10, 10, 50, 50), label: 'person'),
      ];

      final List<DetectionItem> detections2 = [
        DetectionItem(
            rect: const Rect.fromLTRB(20, 20, 60, 60), label: 'hardhat'),
      ];

      // Build initial widget
      await tester.pumpWidget(
        createTestApp(
          buildOverlayWidget(
            key: const ValueKey('test_1'),
            rawBytes: testImageData1,
            originalWidth: 640,
            originalHeight: 480,
            conePolygons: const [],
            polePolygons: const [],
            detectionItems: detections1,
            showOverlays: true,
          ),
        ),
      );

      // Wait for initial render
      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.byType(DetectionOverlayWidget), findsOneWidget);

      // Update with new data using different key to force rebuild
      await tester.pumpWidget(
        createTestApp(
          buildOverlayWidget(
            key: const ValueKey(
                'test_2'), // Different key ensures synchronous update
            rawBytes: testImageData2,
            originalWidth: 640,
            originalHeight: 480,
            conePolygons: const [],
            polePolygons: const [],
            detectionItems: detections2,
            showOverlays: true,
          ),
        ),
      );

      // Wait for update to complete
      await tester.pumpAndSettle();

      // Verify widget updated
      expect(find.byType(DetectionOverlayWidget), findsOneWidget);

      // The widget should now have the new key
      final widget = tester
          .widget<DetectionOverlayWidget>(find.byType(DetectionOverlayWidget));
      expect(widget.key, const ValueKey('test_2'));
    });

    testWidgets('should maintain aspect ratio during updates',
        (WidgetTester tester) async {
      final Uint8List testImageData = MockDataGenerator.createMockImageBytes();

      await tester.pumpWidget(
        createTestApp(
          buildOverlayWidget(
            rawBytes: testImageData,
            originalWidth: 1920,
            originalHeight: 1080,
            conePolygons: const [],
            polePolygons: const [],
            detectionItems: const [],
            showOverlays: false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the AspectRatio widget
      final aspectRatioFinder = find.byType(AspectRatio);
      expect(aspectRatioFinder, findsOneWidget);

      final AspectRatio aspectRatio = tester.widget(aspectRatioFinder);
      expect(aspectRatio.aspectRatio, closeTo(1920.0 / 1080.0, 0.001));
    });

    testWidgets('should handle overlay toggle correctly',
        (WidgetTester tester) async {
      final Uint8List testImageData = MockDataGenerator.createMockImageBytes();
      final List<DetectionItem> detections = [
        DetectionItem(
            rect: const Rect.fromLTRB(10, 10, 50, 50), label: 'person'),
      ];

      // Test with overlays enabled
      await tester.pumpWidget(
        createTestApp(
          buildOverlayWidget(
            rawBytes: testImageData,
            originalWidth: 640,
            originalHeight: 480,
            conePolygons: const [],
            polePolygons: const [],
            detectionItems: detections,
            showOverlays: true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final enabledOverlayPaints =
          tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where(
                (paint) => paint.painter is OverlayPainter,
              );
      expect(enabledOverlayPaints, isNotEmpty);

      // Test with overlays disabled
      await tester.pumpWidget(
        createTestApp(
          buildOverlayWidget(
            rawBytes: testImageData,
            originalWidth: 640,
            originalHeight: 480,
            conePolygons: const [],
            polePolygons: const [],
            detectionItems: detections,
            showOverlays: false,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final disabledOverlayPaints =
          tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where(
                (paint) => paint.painter is OverlayPainter,
              );
      expect(disabledOverlayPaints, isEmpty);
    });
  });
}
