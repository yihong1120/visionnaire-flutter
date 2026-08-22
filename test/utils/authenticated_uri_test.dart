import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/utils/authenticated_uri.dart';

void main() {
  const String baseValue = 'https://api.example.test:8443/hazard/api/chat';

  test('resolves relative authenticated URLs on the configured origin', () {
    final Uri resolved = AuthenticatedUri.parseAndResolve(
      '/bff/chat/documents/dl/source.pdf',
      Uri.parse(baseValue),
    );

    expect(resolved.toString(),
        'https://api.example.test:8443/bff/chat/documents/dl/source.pdf');
  });

  test('accepts an absolute authenticated URL only on the same origin', () {
    final Uri base = Uri.parse('https://api.example.test/hazard/api/chat');
    final Uri resolved = AuthenticatedUri.parseAndResolve(
      'https://api.example.test:443/hazard/api/chat/attachments/1',
      base,
    );

    expect(resolved.host, base.host);
    expect(resolved.port, 443);
  });

  test('rejects cross-origin and credential-bearing authenticated URLs', () {
    final Uri base = Uri.parse(baseValue);

    expect(
      () => AuthenticatedUri.parseAndResolve(
        'https://attacker.example/collect',
        base,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AuthenticatedUri.parseAndResolve(
        'https://api.example.test/collect',
        base,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AuthenticatedUri.parseAndResolve(
        'https://user:password@api.example.test:8443/collect',
        base,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () =>
          AuthenticatedUri.parseAndResolve('//attacker.example/collect', base),
      throwsA(isA<FormatException>()),
    );
  });

  test('retains the chat attachment base-path contract for relative paths', () {
    final Uri resolved = AuthenticatedUri.resolvePathRelativeToBase(
      '/attachments/1?download=false',
      Uri.parse(baseValue),
    );

    expect(resolved.toString(),
        'https://api.example.test:8443/hazard/api/chat/attachments/1?download=false');
  });
}
