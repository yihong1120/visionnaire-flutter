import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_draft.dart';
import 'document_draft_attachment_store.dart';
import 'file_manage_api_service.dart';

typedef DocumentDraftRemoteLoader = Future<DocumentDraft?> Function(String key);
typedef DocumentDraftRemoteSaver = Future<void> Function(DocumentDraft draft);
typedef DocumentDraftRemoteDeleter = Future<void> Function(String key);

class DocumentDraftService {
  const DocumentDraftService._();

  static const String _prefix = 'visionnaire.document_draft.v1.';
  static const Duration defaultTtl = Duration(days: 30);
  static const List<String> fileBoundDraftTypes = <String>[
    'file_edit',
    'photo_doc',
    'audit_fix',
  ];
  static final Random _draftIdRandom = Random();

  static String buildKey({
    required String draftType,
    required int? userId,
    int? fileId,
    int? siteId,
    String? scope,
  }) {
    final parts = <String>[
      draftType,
      'user_${userId ?? 'guest'}',
      if (fileId != null) 'file_$fileId',
      if (fileId == null && siteId != null) 'site_$siteId',
      if (fileId == null && siteId == null) scope ?? 'new',
    ];
    return parts.join(':');
  }

  static List<String> fileDraftKeys({
    required int? userId,
    required int fileId,
  }) {
    return fileBoundDraftTypes
        .map(
          (draftType) => buildKey(
            draftType: draftType,
            userId: userId,
            fileId: fileId,
          ),
        )
        .toList(growable: false);
  }

  static Future<void> deleteFileDrafts({
    required int? userId,
    required int fileId,
    DocumentDraftRemoteDeleter? remoteDeleter,
    bool waitForRemote = false,
  }) async {
    final keys = <String>{
      ...fileDraftKeys(userId: userId, fileId: fileId),
      ...await _localFileDraftKeys(fileId),
    };

    for (final key in keys) {
      await delete(
        key,
        remoteDeleter: remoteDeleter,
        waitForRemote: waitForRemote,
      );
    }
  }

  static Future<Set<String>> _localFileDraftKeys(int fileId) async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = 'file_$fileId';
    final keys = <String>{};
    for (final storageKey in prefs.getKeys()) {
      if (!storageKey.startsWith(_prefix)) continue;
      final key = storageKey.substring(_prefix.length);
      final parts = key.split(':');
      if (parts.isEmpty || !fileBoundDraftTypes.contains(parts.first)) {
        continue;
      }
      if (parts.contains(suffix)) {
        keys.add(key);
      }
    }
    return keys;
  }

  static String createClientDraftId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final randomPart = _draftIdRandom.nextInt(0x3fffffff).toRadixString(36);
    return '$timestamp-$randomPart';
  }

  static String buildCreateKey({
    required String draftType,
    required String clientDraftId,
  }) {
    final String safeId = clientDraftId
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (safeId.isEmpty) {
      throw ArgumentError.value(
        clientDraftId,
        'clientDraftId',
        'client draft id must not be empty',
      );
    }
    return '$draftType:create:$safeId';
  }

  static Future<DocumentDraft?> load(
    String key, {
    DocumentDraftRemoteLoader? remoteLoader,
  }) async {
    final localDraft = await _loadLocal(key);
    final remoteDraft = await _loadRemoteBestEffort(key, remoteLoader);
    if (remoteDraft == null) return localDraft;

    if (remoteDraft.isExpired) {
      await delete(key);
      return localDraft;
    }

    if (localDraft == null ||
        remoteDraft.updatedAt.isAfter(localDraft.updatedAt)) {
      await _saveDraftLocally(remoteDraft);
      return remoteDraft;
    }
    return localDraft;
  }

  static Future<DocumentDraft?> _loadLocal(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final draft = DocumentDraft.fromJson(Map<String, dynamic>.from(decoded));
      if (draft == null) return null;
      if (draft.isExpired) {
        await delete(key);
        return null;
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  static Future<DocumentDraft?> _loadRemoteBestEffort(
    String key,
    DocumentDraftRemoteLoader? remoteLoader,
  ) async {
    if (remoteLoader == null) return null;
    try {
      return await remoteLoader(key);
    } catch (error, stackTrace) {
      _debugRemoteDraftFailure('load', error, stackTrace);
      return null;
    }
  }

  static Future<bool> save({
    required String key,
    required String type,
    required Map<String, dynamic> payload,
    Duration ttl = defaultTtl,
    DocumentDraftRemoteSaver? remoteSaver,
    bool waitForRemote = false,
  }) async {
    final now = DateTime.now().toUtc();
    final draft = DocumentDraft(
      key: key,
      type: type,
      payload: payload,
      updatedAt: now,
      expiresAt: now.add(ttl),
    );
    final saved = await _saveDraftLocally(draft);
    if (remoteSaver != null) {
      final Future<void> remoteSave = _saveRemoteBestEffort(
        remoteSaver,
        draft,
      );
      if (waitForRemote) {
        await remoteSave;
      } else {
        unawaited(remoteSave);
      }
    }
    return saved;
  }

  static Future<bool> _saveDraftLocally(DocumentDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString('$_prefix${draft.key}', jsonEncode(draft.toJson()));
  }

  static Future<void> _saveRemoteBestEffort(
    DocumentDraftRemoteSaver remoteSaver,
    DocumentDraft draft,
  ) async {
    try {
      await remoteSaver(draft);
    } catch (error, stackTrace) {
      _debugRemoteDraftFailure('save', error, stackTrace);
    }
  }

  static Future<void> delete(
    String key, {
    DocumentDraftRemoteDeleter? remoteDeleter,
    bool waitForRemote = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
    try {
      await DocumentDraftAttachmentStore.deleteDraftAttachments(key);
    } catch (error, stackTrace) {
      debugPrint('Document draft attachment cleanup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (remoteDeleter != null) {
      final Future<void> remoteDelete =
          _deleteRemoteBestEffort(remoteDeleter, key);
      if (waitForRemote) {
        await remoteDelete;
      } else {
        unawaited(remoteDelete);
      }
    }
  }

  static Future<void> _deleteRemoteBestEffort(
    DocumentDraftRemoteDeleter remoteDeleter,
    String key,
  ) async {
    try {
      await remoteDeleter(key);
    } catch (error, stackTrace) {
      _debugRemoteDraftFailure('delete', error, stackTrace);
    }
  }

  static void _debugRemoteDraftFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is FileManageApiException &&
        (error.statusCode == 404 || error.statusCode == 405)) {
      debugPrint(
        'Document draft remote $operation skipped: ${error.message}',
      );
      return;
    }

    debugPrint('Document draft remote $operation failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  static Future<void> deleteExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(_prefix));
    for (final storageKey in keys) {
      final raw = prefs.getString(storageKey);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final draft =
            DocumentDraft.fromJson(Map<String, dynamic>.from(decoded));
        if (draft != null && draft.isExpired) {
          await delete(draft.key);
        }
      } catch (_) {
        await prefs.remove(storageKey);
      }
    }
  }
}

class DocumentDraftAutosaver {
  DocumentDraftAutosaver({
    required this.type,
    required this.keyProvider,
    required this.payloadProvider,
    this.remoteLoader,
    this.remoteSaver,
    this.remoteDeleter,
    Duration debounce = const Duration(seconds: 2),
    Duration minSaveInterval = const Duration(seconds: 10),
  })  : _debounce = debounce,
        _minSaveInterval = minSaveInterval;

  final String type;
  final FutureOr<String> Function() keyProvider;
  final FutureOr<Map<String, dynamic>?> Function() payloadProvider;
  final DocumentDraftRemoteLoader? remoteLoader;
  final DocumentDraftRemoteSaver? remoteSaver;
  final DocumentDraftRemoteDeleter? remoteDeleter;
  final Duration _debounce;
  final Duration _minSaveInterval;

  Timer? _timer;
  String? _lastSerializedPayload;
  DateTime? _lastSavedAt;
  bool _saving = false;
  bool _saveAgainRequested = false;
  int _deleteGeneration = 0;

  void schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      unawaited(saveIfChanged());
    });
  }

  Future<void> saveIfChanged({bool force = false}) async {
    if (_saving) {
      _saveAgainRequested = true;
      return;
    }
    final int generation = _deleteGeneration;
    final now = DateTime.now();
    final lastSavedAt = _lastSavedAt;
    if (!force &&
        lastSavedAt != null &&
        now.difference(lastSavedAt) < _minSaveInterval) {
      _timer?.cancel();
      _timer = Timer(_minSaveInterval - now.difference(lastSavedAt), () {
        unawaited(saveIfChanged());
      });
      return;
    }

    _saving = true;
    try {
      final payload = await payloadProvider();
      if (generation != _deleteGeneration) return;

      if (payload == null || payload.isEmpty) {
        final key = await keyProvider();
        if (generation != _deleteGeneration) return;
        await DocumentDraftService.delete(
          key,
          remoteDeleter: remoteDeleter,
        );
        _lastSerializedPayload = null;
        _lastSavedAt = DateTime.now();
        return;
      }
      final serialized = jsonEncode(payload);
      if (!force && serialized == _lastSerializedPayload) return;

      final key = await keyProvider();
      if (generation != _deleteGeneration) return;
      await DocumentDraftService.save(
        key: key,
        type: type,
        payload: payload,
        remoteSaver: remoteSaver,
        waitForRemote: true,
      );
      if (generation != _deleteGeneration) {
        await DocumentDraftService.delete(
          key,
          remoteDeleter: remoteDeleter,
          waitForRemote: true,
        );
        _lastSerializedPayload = null;
        _lastSavedAt = null;
        return;
      }
      _lastSerializedPayload = serialized;
      _lastSavedAt = DateTime.now();
    } catch (error, stackTrace) {
      debugPrint('Document draft autosave failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _saving = false;
      final bool shouldSaveAgain =
          _saveAgainRequested && generation == _deleteGeneration;
      _saveAgainRequested = false;
      if (shouldSaveAgain) {
        unawaited(saveIfChanged(force: true));
      }
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await saveIfChanged(force: true);
  }

  Future<void> delete({bool waitForRemote = false}) async {
    _deleteGeneration += 1;
    _saveAgainRequested = false;
    _timer?.cancel();
    _timer = null;
    final key = await keyProvider();
    await DocumentDraftService.delete(
      key,
      remoteDeleter: remoteDeleter,
      waitForRemote: waitForRemote,
    );
    _lastSerializedPayload = null;
    _lastSavedAt = null;
  }

  Future<DocumentDraft?> load() async {
    final key = await keyProvider();
    return DocumentDraftService.load(
      key,
      remoteLoader: remoteLoader,
    );
  }

  void dispose() {
    _timer?.cancel();
  }
}
