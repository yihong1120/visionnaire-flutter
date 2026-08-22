import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/services/social_auth_service.dart';

void main() {
  test('Google credentials require a non-empty ID token', () {
    expect(
      () => GoogleSocialAuthCredential(idToken: '  '),
      throwsArgumentError,
    );

    final credential = GoogleSocialAuthCredential(idToken: ' token ');
    expect(credential.idToken, 'token');
    expect(credential.provider, SocialAuthProviderType.google);
  });

  test('Apple credentials require a non-empty authorization code', () {
    expect(
      () => AppleSocialAuthCredential(authorizationCode: ''),
      throwsArgumentError,
    );

    final credential = AppleSocialAuthCredential(
      authorizationCode: ' authorization-code ',
      identityToken: 'identity-token',
    );
    expect(credential.authorizationCode, 'authorization-code');
    expect(credential.provider, SocialAuthProviderType.apple);
  });
}
