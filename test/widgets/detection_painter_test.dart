import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:visionnaire/l10n/app_localizations.dart';
import 'package:visionnaire/widgets/detection_painter.dart';

import '../test_helpers.dart';

// Minimal 1x1 transparent PNG bytes (static to keep tests stable and fast)
const List<int> _kPng1x1Transparent = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  1,
  115,
  82,
  71,
  66,
  0,
  174,
  206,
  28,
  233,
  0,
  0,
  0,
  10,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  0,
  1,
  0,
  0,
  5,
  0,
  1,
  13,
  10,
  42,
  186,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130
];

Future<Uint8List> _makePng({Color colour = Colors.white}) async {
  // Colour parameter unused; keep signature flexible for future changes
  return Uint8List.fromList(_kPng1x1Transparent);
}

Widget _wrapWithLocalizations(Widget child) {
  return createLocalizedTestApp(child);
}

void main() {
  group('OverlayPainter.mapLabelToLocalString', () {
    testWidgets('maps numeric and string labels to localised strings',
        (WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
          _wrapWithLocalizations(Builder(builder: (BuildContext context) {
        ctx = context;
        return const SizedBox.shrink();
      })));

      final AppLocalizations local = AppLocalizations.of(ctx)!;

      expect(OverlayPainter.mapLabelToLocalString('0', local), local.hardhat);
      expect(OverlayPainter.mapLabelToLocalString('1', local), local.mask);
      expect(
          OverlayPainter.mapLabelToLocalString('2', local), local.no_hardhat);
      expect(OverlayPainter.mapLabelToLocalString('3', local), local.no_mask);
      expect(OverlayPainter.mapLabelToLocalString('4', local), local.no_vest);
      expect(OverlayPainter.mapLabelToLocalString('5', local), local.person);
      expect(OverlayPainter.mapLabelToLocalString('6', local), local.cone);
      expect(OverlayPainter.mapLabelToLocalString('7', local), local.vest);
      expect(OverlayPainter.mapLabelToLocalString('8', local), local.machinery);
      expect(
          OverlayPainter.mapLabelToLocalString('9', local), local.utility_pole);
      expect(OverlayPainter.mapLabelToLocalString('10', local), local.vehicle);

      expect(OverlayPainter.mapLabelToLocalString('hardhat', local),
          local.hardhat);
      expect(OverlayPainter.mapLabelToLocalString('vehicle', local),
          local.vehicle);
      // Unknown remains unchanged
      expect(OverlayPainter.mapLabelToLocalString('unknown_label', local),
          'unknown_label');
      expect(
          OverlayPainter.mapLabelToLocalString('8.0', local), local.machinery);
      expect(OverlayPainter.mapLabelToLocalString('4.0', local), local.no_vest);
      expect(OverlayPainter.mapLabelToLocalString('7.0', local), local.vest);
      expect(OverlayPainter.mapLabelToLocalString('7.5', local), '7.5');

      final DetectionOverlayLabels labels =
          DetectionOverlayLabels.fromLocalizations(local);
      expect(labels.colorFor('8.0'), Colors.orangeAccent);
      expect(labels.colorFor('4.0'), Colors.red);
      expect(labels.colorFor('7.0'), Colors.green);

      const Map<int, String> classKeys = <int, String>{
        0: 'hardhat',
        1: 'mask',
        2: 'no_hardhat',
        3: 'no_mask',
        4: 'no_vest',
        5: 'person',
        6: 'cone',
        7: 'vest',
        8: 'machinery',
        9: 'utility_pole',
        10: 'vehicle',
      };
      for (final MapEntry<int, String> entry in classKeys.entries) {
        expect(
          DetectionOverlayLabels.canonicalKey('${entry.key}.0'),
          entry.value,
        );
      }
    });
  });

  group('OverlayPainter.sortPointsByAngle', () {
    test('returns same list for <= 2 points', () {
      final List<Offset> pts1 = <Offset>[const Offset(1, 2)];
      final List<Offset> pts2 = <Offset>[
        const Offset(0, 0),
        const Offset(1, 0)
      ];
      expect(OverlayPainter.sortPointsByAngle(pts1), pts1);
      expect(OverlayPainter.sortPointsByAngle(pts2), pts2);
    });

    test('sorts by angle for > 2 points (no throw, contains same elements)',
        () {
      final List<Offset> pts = <Offset>[
        const Offset(1, 0),
        const Offset(0, 1),
        const Offset(-1, 0),
        const Offset(0, -1),
      ];
      final List<Offset> out = OverlayPainter.sortPointsByAngle(pts);
      expect(out.length, 4);
      for (final Offset p in pts) {
        expect(out.contains(p), isTrue);
      }
    });
  });

  group('OverlayPainter.drawOverlays', () {
    testWidgets('executes drawing for polygons and detections across branches',
        (WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
          _wrapWithLocalizations(Builder(builder: (BuildContext context) {
        ctx = context;
        return const SizedBox.shrink();
      })));

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      const Size size = Size(200, 100);

      final List<List<Offset>> cones = <List<Offset>>[
        <Offset>[
          const Offset(10, 10),
          const Offset(20, 10),
          const Offset(15, 20)
        ],
        const <Offset>[], // hit the early-continue branch
      ];
      final List<List<Offset>> poles = <List<Offset>>[
        <Offset>[
          const Offset(50, 20),
          const Offset(60, 20),
          const Offset(60, 40),
          const Offset(50, 40)
        ],
        const <Offset>[], // hit the early-continue branch
      ];

      // Detections designed to exercise multiple label placement branches
      final List<DetectionItem> detections = <DetectionItem>[
        // Above-box label placement
        DetectionItem(
            rect: const Rect.fromLTWH(10, 30, 40, 60), label: 'person'),
        // Left-half, place to the right
        DetectionItem(
            rect: const Rect.fromLTWH(5, -10, 30, 20),
            label: '0'), // numeric -> hardhat
        // Right-half, place to the left
        DetectionItem(
            rect: const Rect.fromLTWH(150, -10, 190, 30), label: 'vehicle'),
        // General right-of-box fallback
        DetectionItem(rect: const Rect.fromLTWH(5, -5, 15, 10), label: 'vest'),
        // Inside-box fallback (large near right edge)
        DetectionItem(
            rect: const Rect.fromLTWH(180, -5, 199, 5), label: 'machinery'),
        // Unknown label -> default colour
        DetectionItem(
            rect: const Rect.fromLTWH(0, 0, 5, 5), label: 'unknown_label'),
        // Cone should skip box drawing entirely
        DetectionItem(rect: const Rect.fromLTWH(20, 20, 40, 40), label: '6'),
      ];

      // Execute draw against a standard canvas
      OverlayPainter.drawOverlays(
        canvas: canvas,
        size: size,
        conePolygons: cones,
        polePolygons: poles,
        detectionItems: detections,
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 200,
        originalHeight: 100,
      );

      // Finish the picture to ensure no exceptions
      final ui.Picture picture = recorder.endRecording();
      expect(picture, isA<ui.Picture>());

      // Additional targeted canvases to hit general left/right and final fallback branches
      // 1) General left-of fallback: left-half, no right space, but has left space
      final ui.PictureRecorder rec2 = ui.PictureRecorder();
      final Canvas canvas2 = Canvas(rec2);
      const Size size2 = Size(220, 100);
      OverlayPainter.drawOverlays(
        canvas: canvas2,
        size: size2,
        conePolygons: const <List<Offset>>[],
        polePolygons: const <List<Offset>>[],
        detectionItems: <DetectionItem>[
          // Centre < width/2, top negative (no above), right space insufficient, left space sufficient
          DetectionItem(
              rect: const Rect.fromLTWH(130, -5, 149, 10),
              label: 'utility_pole'),
        ],
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 220,
        originalHeight: 100,
      );
      rec2.endRecording();

      // 2) General right-of fallback: right-half, no left space, but has right space
      final ui.PictureRecorder rec3 = ui.PictureRecorder();
      final Canvas canvas3 = Canvas(rec3);
      const Size size3 = Size(300, 100);
      OverlayPainter.drawOverlays(
        canvas: canvas3,
        size: size3,
        conePolygons: const <List<Offset>>[],
        polePolygons: const <List<Offset>>[],
        detectionItems: <DetectionItem>[
          // Centre >= width/2, top negative (no above), left space insufficient, right space sufficient
          DetectionItem(
              rect: const Rect.fromLTWH(50, -5, 180, 10),
              label: 'utility_pole'),
        ],
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 300,
        originalHeight: 100,
      );
      rec3.endRecording();

      // 3) Final inside-box fallback: tiny canvas, long label, no side space
      final ui.PictureRecorder rec4 = ui.PictureRecorder();
      final Canvas canvas4 = Canvas(rec4);
      const Size size4 = Size(60, 30);
      OverlayPainter.drawOverlays(
        canvas: canvas4,
        size: size4,
        conePolygons: const <List<Offset>>[],
        polePolygons: const <List<Offset>>[],
        detectionItems: <DetectionItem>[
          DetectionItem(
              rect: const Rect.fromLTWH(10, -5, 50, 10), label: 'utility_pole'),
        ],
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 60,
        originalHeight: 30,
      );
      rec4.endRecording();
    });
  });

  group('OverlayPainter.shouldRepaint', () {
    testWidgets('returns false for identical inputs and true when any differ',
        (WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
          _wrapWithLocalizations(Builder(builder: (BuildContext context) {
        ctx = context;
        return const SizedBox.shrink();
      })));

      final List<List<Offset>> cones1 = <List<Offset>>[
        <Offset>[const Offset(0, 0), const Offset(1, 0), const Offset(0, 1)],
      ];
      final List<List<Offset>> poles1 = <List<Offset>>[
        <Offset>[const Offset(2, 2), const Offset(3, 2), const Offset(3, 3)],
      ];
      final List<DetectionItem> dets1 = <DetectionItem>[
        DetectionItem(rect: const Rect.fromLTWH(1, 1, 2, 2), label: 'person'),
      ];

      final OverlayPainter a = OverlayPainter(
        conePolygons: cones1,
        polePolygons: poles1,
        detectionItems: dets1,
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 100,
        originalHeight: 100,
      );
      final OverlayPainter bSame = OverlayPainter(
        conePolygons: cones1,
        polePolygons: poles1,
        detectionItems: dets1,
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 100,
        originalHeight: 100,
      );

      expect(a.shouldRepaint(bSame), isFalse);

      final OverlayPainter bCones = OverlayPainter(
        conePolygons: <List<Offset>>[
          <Offset>[const Offset(9, 9), const Offset(10, 9), const Offset(9, 10)]
        ],
        polePolygons: poles1,
        detectionItems: dets1,
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 100,
        originalHeight: 100,
      );
      expect(a.shouldRepaint(bCones), isTrue);

      final OverlayPainter bPoles = OverlayPainter(
        conePolygons: cones1,
        polePolygons: <List<Offset>>[
          <Offset>[const Offset(5, 5), const Offset(6, 5), const Offset(6, 6)]
        ],
        detectionItems: dets1,
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 100,
        originalHeight: 100,
      );
      expect(a.shouldRepaint(bPoles), isTrue);

      final OverlayPainter bDets = OverlayPainter(
        conePolygons: cones1,
        polePolygons: poles1,
        detectionItems: <DetectionItem>[
          DetectionItem(rect: const Rect.fromLTWH(2, 2, 3, 3), label: 'vehicle')
        ],
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 100,
        originalHeight: 100,
      );
      expect(a.shouldRepaint(bDets), isTrue);

      final OverlayPainter bWidth = OverlayPainter(
        conePolygons: cones1,
        polePolygons: poles1,
        detectionItems: dets1,
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 200,
        originalHeight: 100,
      );
      expect(a.shouldRepaint(bWidth), isTrue);

      final OverlayPainter bHeight = OverlayPainter(
        conePolygons: cones1,
        polePolygons: poles1,
        detectionItems: dets1,
        localizations: AppLocalizations.of(ctx)!,
        originalWidth: 100,
        originalHeight: 200,
      );
      expect(a.shouldRepaint(bHeight), isTrue);
    });

    testWidgets('returns true when oldDelegate is not OverlayPainter',
        (WidgetTester tester) async {
      late OverlayPainter a;
      await tester.pumpWidget(
          _wrapWithLocalizations(Builder(builder: (BuildContext context) {
        a = OverlayPainter(
          conePolygons: const <List<Offset>>[],
          polePolygons: const <List<Offset>>[],
          detectionItems: const <DetectionItem>[],
          localizations: AppLocalizations.of(context)!,
          originalWidth: 100,
          originalHeight: 100,
        );
        return const SizedBox.shrink();
      })));
      final CustomPainter other = _OtherPainter();
      expect(a.shouldRepaint(other), isTrue);
    });
  });

  group('OverlayPainter.paint', () {
    testWidgets('invokes drawOverlays via CustomPaint without throwing',
        (WidgetTester tester) async {
      late BuildContext ctx;
      final List<List<Offset>> cones = <List<Offset>>[
        <Offset>[const Offset(0, 0), const Offset(10, 0), const Offset(5, 10)],
      ];
      final List<List<Offset>> poles = <List<Offset>>[
        <Offset>[
          const Offset(10, 10),
          const Offset(20, 10),
          const Offset(20, 20)
        ],
      ];
      final List<DetectionItem> dets = <DetectionItem>[
        DetectionItem(
            rect: const Rect.fromLTWH(10, 20, 30, 40), label: 'person'),
      ];

      await tester.pumpWidget(
          _wrapWithLocalizations(Builder(builder: (BuildContext context) {
        ctx = context;
        return Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: CustomPaint(
              painter: OverlayPainter(
                conePolygons: cones,
                polePolygons: poles,
                detectionItems: dets,
                localizations: AppLocalizations.of(ctx)!,
                originalWidth: 200,
                originalHeight: 100,
              ),
            ),
          ),
        );
      })));

      expect(
        find.byWidgetPredicate(
          (Widget w) => w is CustomPaint && w.painter is OverlayPainter,
        ),
        findsOneWidget,
      );
    });
  });

  group('DetectionOverlayWidget', () {
    testWidgets('renders with overlays and toggles showOverlays',
        (WidgetTester tester) async {
      final Uint8List img1 = await _makePng(colour: Colors.white);

      Widget buildUnderTest({required bool show}) {
        return _wrapWithLocalizations(Builder(builder: (BuildContext context) {
          return DetectionOverlayWidget(
            rawBytes: img1,
            originalWidth: 2,
            originalHeight: 2,
            conePolygons: <List<Offset>>[
              <Offset>[
                const Offset(0, 0),
                const Offset(1, 0),
                const Offset(0.5, 1)
              ],
            ],
            polePolygons: const <List<Offset>>[],
            detectionItems: <DetectionItem>[
              DetectionItem(
                  rect: const Rect.fromLTWH(0.2, 0.2, 1.0, 1.5),
                  label: 'person'),
            ],
            showOverlays: show,
          );
        }));
      }

      await tester.pumpWidget(buildUnderTest(show: true));
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is CustomPaint && w.painter is OverlayPainter,
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(buildUnderTest(show: false));
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is CustomPaint && w.painter is OverlayPainter,
        ),
        findsNothing,
      );
    });

    testWidgets(
        'didUpdateWidget triggers image transition on rawBytes change (including in-flight fade builder)',
        (WidgetTester tester) async {
      final Uint8List img1 = await _makePng(colour: Colors.white);
      // Make a minimally different byte list by appending a trailing 0 (PNG decoders ignore trailing data)
      final Uint8List img2 = Uint8List.fromList(<int>[...img1, 0]);

      Widget buildWithBytes(Uint8List bytes) {
        return _wrapWithLocalizations(Builder(builder: (BuildContext context) {
          return DetectionOverlayWidget(
            rawBytes: bytes,
            originalWidth: 2,
            originalHeight: 2,
            conePolygons: const <List<Offset>>[],
            polePolygons: const <List<Offset>>[],
            detectionItems: const <DetectionItem>[],
            showOverlays: true,
          );
        }));
      }

      await tester.pumpWidget(buildWithBytes(img1));
      await tester.pump();

      // Update with different bytes -> triggers _updateImage via didUpdateWidget
      await tester.pumpWidget(buildWithBytes(img2));
      // Pump briefly while fade is in-flight to exercise the AnimatedBuilder branch
      await tester.pump(const Duration(milliseconds: 10));
      // Advance animation beyond 150ms to let transition finish
      await tester.pump(const Duration(milliseconds: 160));

      // If no exceptions occurred, transition path executed
      expect(tester.takeException(), isNull);
    });
  });

  group('DetectionOverlayWidget lifecycle', () {
    testWidgets('disposes cleanly when removed from the tree',
        (WidgetTester tester) async {
      final Uint8List img = await _makePng();

      await tester.pumpWidget(
          _wrapWithLocalizations(Builder(builder: (BuildContext context) {
        return DetectionOverlayWidget(
          rawBytes: img,
          originalWidth: 2,
          originalHeight: 2,
          conePolygons: const <List<Offset>>[],
          polePolygons: const <List<Offset>>[],
          detectionItems: const <DetectionItem>[],
          showOverlays: true,
        );
      })));

      await tester.pump(const Duration(milliseconds: 10));
      // Remove widget
      await tester.pumpWidget(_wrapWithLocalizations(const SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.takeException(), isNull);
    });
  });
}

class _OtherPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
