import 'package:shared_preferences/shared_preferences.dart';

import 'storage_service.dart';

class WebPrefsStorageService implements StorageService {
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String?> read(String key) async {
    final p = await _getPrefs();
    return p.getString('secure_$key');
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) return;
    final p = await _getPrefs();
    await p.setString('secure_$key', value);
  }

  @override
  Future<void> deleteAll() async {
    final p = await _getPrefs();
    final keys = p.getKeys().where((k) => k.startsWith('secure_')).toList();
    for (final k in keys) {
      await p.remove(k);
    }
  }
}

StorageService createStorageService() => WebPrefsStorageService();
