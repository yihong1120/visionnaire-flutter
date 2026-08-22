import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/violation_image_cache.dart';

import '../test_support/deployment_profile_test_support.dart';

void main() {
  setUp(() {
    installEnrollmentDeploymentProfile(debug: true);
  });

  tearDown(() {
    ViolationImageCache.clear();
    ViolationImageCache.debugLoader = null;
    resetDeploymentProfile();
  });

  test('an evicted failure cannot remove a newer request for the same URL',
      () async {
    final Completer<ViolationImageData> first = Completer<ViolationImageData>();
    final Completer<ViolationImageData> second =
        Completer<ViolationImageData>();
    final Completer<void> firstStarted = Completer<void>();
    final Completer<void> secondStarted = Completer<void>();
    int requestCount = 0;

    ViolationImageCache.debugLoader = ({
      required String url,
      required String token,
      required Duration timeout,
    }) {
      requestCount += 1;
      if (requestCount == 1) {
        firstStarted.complete();
        return first.future;
      }
      secondStarted.complete();
      return second.future;
    };

    const String url = 'https://api.test.example/violation.jpg';
    final Future<ViolationImageData> firstRequest =
        ViolationImageCache.fetch(url: url, token: 'token');
    await firstStarted.future;
    ViolationImageCache.evict(url);
    final Future<ViolationImageData> secondRequest =
        ViolationImageCache.fetch(url: url, token: 'token');
    await secondStarted.future;

    first.completeError(StateError('stale request failed'));
    await expectLater(firstRequest, throwsStateError);

    final Future<ViolationImageData> cachedRequest =
        ViolationImageCache.fetch(url: url, token: 'token');
    expect(identical(cachedRequest, secondRequest), isTrue);
    expect(requestCount, 2);

    second.complete(
      ViolationImageData(
        url: url,
        rawBytes: Uint8List.fromList(<int>[1, 2, 3]),
        width: 1,
        height: 1,
      ),
    );
    await secondRequest;
  });

  test('rejects a cross-origin native image before a bearer request is made',
      () async {
    int requestCount = 0;
    final List<String> tokens = <String>[];
    ViolationImageCache.debugLoader = ({
      required String url,
      required String token,
      required Duration timeout,
    }) async {
      requestCount += 1;
      tokens.add(token);
      return ViolationImageData(
        url: url,
        rawBytes: Uint8List.fromList(<int>[1]),
        width: 1,
        height: 1,
      );
    };

    await expectLater(
      ViolationImageCache.fetch(
        url: 'https://attacker.example/violation.jpg',
        token: 'native-bearer-token',
      ),
      throwsA(isA<FormatException>()),
    );

    expect(requestCount, 0);
    expect(tokens, isEmpty);
  });

  test('accepts only an absolute image URL on the browser BFF origin', () {
    final Uri bffPage = Uri.parse('https://app.example.test/login');

    expect(
      ViolationImageCache.isAbsoluteImageUriOnOrigin(
        'https://app.example.test/violation.jpg',
        bffPage,
      ),
      isTrue,
    );
    expect(
      ViolationImageCache.isAbsoluteImageUriOnOrigin(
        'https://app.example.test:443/violation.jpg',
        bffPage,
      ),
      isTrue,
    );
    expect(
      ViolationImageCache.isAbsoluteImageUriOnOrigin(
        'https://attacker.example/violation.jpg',
        bffPage,
      ),
      isFalse,
    );
    expect(
      ViolationImageCache.isAbsoluteImageUriOnOrigin(
        '/violation.jpg',
        bffPage,
      ),
      isFalse,
    );
    expect(
      ViolationImageCache.isAbsoluteImageUriOnOrigin(
        'https://user@app.example.test/violation.jpg',
        bffPage,
      ),
      isFalse,
    );
  });
}
