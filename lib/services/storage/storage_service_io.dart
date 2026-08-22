import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage_service.dart';

class SecureStorageService implements StorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) return;
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

StorageService createStorageService() => SecureStorageService();
