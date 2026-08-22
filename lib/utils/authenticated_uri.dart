/// Validates URLs before a request can carry application authentication.
///
/// A backend response may contain an external URL, but that URL is not
/// authority to send the user's bearer token or BFF CSRF header elsewhere.
/// Relative references are resolved against [base]; absolute references must
/// have the same scheme, host, and effective port as [base].
abstract final class AuthenticatedUri {
  static Uri parseAndResolve(String value, Uri base) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Authenticated request URL is missing');
    }
    return resolve(Uri.parse(trimmed), base);
  }

  static Uri resolve(Uri reference, Uri base) {
    if (!isTrusted(reference, base)) {
      throw const FormatException(
        'Authenticated request URL must use the configured API origin',
      );
    }
    return isRelativeReference(reference)
        ? base.resolveUri(reference)
        : reference;
  }

  /// Resolves a relative path beneath [base]'s path instead of its directory.
  ///
  /// Chat attachment responses historically use `/attachment` to mean
  /// `<chat-base>/attachment`; retain that route contract while applying the
  /// same origin validation to absolute references.
  static Uri resolvePathRelativeToBase(String value, Uri base) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Authenticated request URL is missing');
    }

    final Uri reference = Uri.parse(trimmed);
    if (!isRelativeReference(reference)) return resolve(reference, base);

    final String basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final String relativePath =
        reference.path.startsWith('/') ? reference.path : '/${reference.path}';
    final String path = relativePath.startsWith(basePath)
        ? relativePath
        : '$basePath$relativePath';
    return base.replace(
      path: path,
      query: reference.hasQuery ? reference.query : null,
      fragment: reference.hasFragment ? reference.fragment : null,
    );
  }

  static bool isTrusted(Uri reference, Uri base) {
    if (reference.userInfo.isNotEmpty) return false;
    if (isRelativeReference(reference)) return true;
    return reference.hasScheme &&
        reference.hasAuthority &&
        isSameOrigin(reference, base);
  }

  static bool isRelativeReference(Uri uri) =>
      !uri.hasScheme && !uri.hasAuthority;

  static bool isSameOrigin(Uri first, Uri second) {
    return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
        first.host.toLowerCase() == second.host.toLowerCase() &&
        _effectivePort(first) == _effectivePort(second);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return switch (uri.scheme.toLowerCase()) {
      'http' => 80,
      'https' => 443,
      _ => 0,
    };
  }
}
