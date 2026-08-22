import 'package:flutter/foundation.dart';

import '../services/api_config_service.dart';

/// Exposes the already-resolved deployment routes to widgets that need them.
///
/// Route selection itself belongs to [ApiConfigService]. This notifier only
/// owns the small loading state needed by the application shell.
class ApiConfigProvider extends ChangeNotifier {
  Map<String, String> _apiUrls = const <String, String>{};
  bool _isLoading = false;

  Map<String, String> get apiUrls => _apiUrls;
  bool get isLoading => _isLoading;

  Future<void> initialize() => reload();

  Future<void> reload() async {
    _isLoading = true;
    notifyListeners();
    try {
      _apiUrls = await ApiConfigService.getAllApiUrls();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String getApiUrl(String serviceKey) {
    final String? url = _apiUrls[serviceKey];
    if (url == null) {
      throw StateError(
          'API configuration has not been loaded for $serviceKey.');
    }
    return url;
  }
}
