import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/config/hcaptcha_config.dart';
import 'package:visionnaire/services/hcaptcha_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'plugins.kjxbyz.com/hcaptcha_flutter_plugin',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> nativeCalls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    HCaptchaConfig.debugIsConfigured = true;
    HCaptchaConfig.debugSiteKey = 'test-hcaptcha-site-key';
    HCaptchaService.debugTokenResolver = null;
    nativeCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return call.method == 'show' ? 'test-response-token' : null;
    });
  });

  tearDown(() async {
    await HCaptchaService.cancelActiveChallenge();
    messenger.setMockMethodCallHandler(channel, null);
    HCaptchaService.debugTokenResolver = null;
    HCaptchaConfig.debugIsConfigured = null;
    HCaptchaConfig.debugSiteKey = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test('show returns its token through one direct method-channel future',
      () async {
    final token = await HCaptchaService.requestToken(
      locale: const Locale('zh', 'TW'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(token, 'test-response-token');
    expect(nativeCalls.map((call) => call.method), <String>['show', 'dismiss']);
    expect(
      nativeCalls.first.arguments,
      <String, String>{
        'siteKey': HCaptchaConfig.normalizedSiteKey,
        'language': 'zh-TW',
      },
    );
    expect(HCaptchaService.isChallengeActive, isFalse);
  });

  test('concurrent callers share one native challenge', () async {
    final showCompleter = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      if (call.method == 'show') return showCompleter.future;
      return null;
    });

    final first = HCaptchaService.requestToken(
      locale: const Locale('en', 'GB'),
    );
    final second = HCaptchaService.requestToken(
      locale: const Locale('en', 'GB'),
    );
    expect(identical(first, second), isTrue);

    await Future<void>.delayed(Duration.zero);
    expect(
      nativeCalls.where((call) => call.method == 'show'),
      hasLength(1),
    );

    showCompleter.complete('shared-response-token');
    expect(await first, 'shared-response-token');
    expect(await second, 'shared-response-token');
  });

  test('cancelling completes show with an error and permits a new request',
      () async {
    Completer<Object?>? pendingShow;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      if (call.method == 'show') {
        pendingShow = Completer<Object?>();
        return pendingShow!.future;
      }
      if (call.method == 'dismiss' &&
          pendingShow != null &&
          !pendingShow!.isCompleted) {
        pendingShow!.completeError(
          PlatformException(
            code: 'challenge_cancelled',
            message: 'hCaptcha challenge was cancelled.',
          ),
        );
      }
      return null;
    });

    for (var attempt = 1; attempt <= 2; attempt++) {
      final request = HCaptchaService.requestToken(
        locale: const Locale('zh', 'TW'),
      );
      final expectation = expectLater(
        request,
        throwsA(
          isA<HCaptchaException>().having(
            (error) => error.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        nativeCalls.where((call) => call.method == 'show'),
        hasLength(attempt),
      );
      expect(HCaptchaService.isChallengeActive, isTrue);

      await HCaptchaService.cancelActiveChallenge();
      await expectation;
      await Future<void>.delayed(Duration.zero);

      expect(HCaptchaService.isChallengeActive, isFalse);
    }
  });

  test('an invalid native response becomes a typed hCaptcha failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return null;
    });

    await expectLater(
      HCaptchaService.requestToken(locale: const Locale('en')),
      throwsA(
        isA<HCaptchaException>().having(
          (error) => error.message,
          'message',
          contains('empty token'),
        ),
      ),
    );
  });
}
