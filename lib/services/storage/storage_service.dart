// Platform-conditional storage service facade
import 'storage_service_web.dart'
    if (dart.library.io) 'storage_service_io.dart';

abstract class StorageService {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> deleteAll();
}

final StorageService storageService = createStorageService();
