import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionnaire/models/document_draft.dart';
import 'package:visionnaire/services/document_draft_remote_store.dart';
import 'package:visionnaire/services/document_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathProviderChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return 'applicationDocumentsPath';
        }
        return null;
      },
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('buildKey scopes drafts by type, user, and file', () {
    expect(
      DocumentDraftService.buildKey(
        draftType: 'file_edit',
        userId: 7,
        fileId: 42,
      ),
      'file_edit:user_7:file_42',
    );
  });

  test('buildCreateKey creates backend-compatible client draft keys', () {
    expect(
      DocumentDraftService.buildCreateKey(
        draftType: 'photo_doc',
        clientDraftId: 'client_abc-123',
      ),
      'photo_doc:create:client_abc-123',
    );
    expect(
      DocumentDraftService.buildCreateKey(
        draftType: 'audit_fix',
        clientDraftId: 'bad id:/123',
      ),
      'audit_fix:create:bad-id-123',
    );
  });

  test('save and load returns the latest draft payload', () async {
    const String key = 'photo_doc:user_1:new';

    await DocumentDraftService.save(
      key: key,
      type: 'photo_doc',
      payload: <String, dynamic>{
        'project_name': 'Visionnaire',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'description': 'before'},
        ],
      },
    );

    final draft = await DocumentDraftService.load(key);

    expect(draft, isNotNull);
    expect(draft!.key, key);
    expect(draft.type, 'photo_doc');
    expect(draft.payload['project_name'], 'Visionnaire');
  });

  test('delete removes draft metadata', () async {
    const String key = 'audit_fix:user_2:file_3';

    await DocumentDraftService.save(
      key: key,
      type: 'audit_fix',
      payload: <String, dynamic>{'audit_date': '2026/06/19'},
    );
    await DocumentDraftService.delete(key);

    expect(await DocumentDraftService.load(key), isNull);
  });

  test('fileDraftKeys includes all file-bound draft types', () {
    expect(
      DocumentDraftService.fileDraftKeys(userId: 2, fileId: 3),
      <String>[
        'file_edit:user_2:file_3',
        'photo_doc:user_2:file_3',
        'audit_fix:user_2:file_3',
      ],
    );
  });

  test('deleteFileDrafts removes every local file draft', () async {
    final keys = DocumentDraftService.fileDraftKeys(userId: 2, fileId: 3);
    for (final key in keys) {
      await DocumentDraftService.save(
        key: key,
        type: key.split(':').first,
        payload: <String, dynamic>{'value': key},
      );
    }

    await DocumentDraftService.deleteFileDrafts(userId: 2, fileId: 3);

    for (final key in keys) {
      expect(await DocumentDraftService.load(key), isNull);
    }
  });

  test('deleteFileDrafts also removes local file drafts from older user keys',
      () async {
    const String oldKey = 'photo_doc:user_99:file_3';
    await DocumentDraftService.save(
      key: oldKey,
      type: 'photo_doc',
      payload: <String, dynamic>{'value': 'old'},
    );

    await DocumentDraftService.deleteFileDrafts(userId: 2, fileId: 3);

    expect(await DocumentDraftService.load(oldKey), isNull);
  });

  test('deleteFileDrafts attempts remote deletion for every file draft',
      () async {
    final deleted = <String>[];

    await DocumentDraftService.deleteFileDrafts(
      userId: 2,
      fileId: 3,
      remoteDeleter: (key) async => deleted.add(key),
      waitForRemote: true,
    );

    expect(
      deleted,
      <String>[
        'file_edit:user_2:file_3',
        'photo_doc:user_2:file_3',
        'audit_fix:user_2:file_3',
      ],
    );
  });

  test('load prefers newer remote draft and refreshes local cache', () async {
    const String key = 'file_edit:user_3:file_9';
    final DateTime now = DateTime.now().toUtc();

    await DocumentDraftService.save(
      key: key,
      type: 'file_edit',
      payload: <String, dynamic>{
        'text_fields': <String, dynamic>{'1': 'local'},
      },
    );

    final remoteDraft = DocumentDraft(
      key: key,
      type: 'file_edit',
      payload: <String, dynamic>{
        'text_fields': <String, dynamic>{'1': 'remote'},
      },
      updatedAt: now.add(const Duration(minutes: 5)),
      expiresAt: now.add(const Duration(days: 30)),
    );

    final loaded = await DocumentDraftService.load(
      key,
      remoteLoader: (_) async => remoteDraft,
    );

    expect(
      (loaded!.payload['text_fields'] as Map<String, dynamic>)['1'],
      'remote',
    );

    final cached = await DocumentDraftService.load(key);
    expect(
      (cached!.payload['text_fields'] as Map<String, dynamic>)['1'],
      'remote',
    );
  });

  test('expired drafts are removed when loaded', () async {
    const String key = 'file_edit:user_9:file_8';

    await DocumentDraftService.save(
      key: key,
      type: 'file_edit',
      payload: <String, dynamic>{'text_fields': <String, dynamic>{}},
      ttl: const Duration(milliseconds: -1),
    );

    expect(await DocumentDraftService.load(key), isNull);
  });

  test('autosaver removes stale draft when payload becomes empty', () async {
    const String key = 'photo_doc:user_3:new';

    await DocumentDraftService.save(
      key: key,
      type: 'photo_doc',
      payload: <String, dynamic>{'project_name': 'old'},
    );

    final autosaver = DocumentDraftAutosaver(
      type: 'photo_doc',
      keyProvider: () => key,
      payloadProvider: () => null,
    );

    await autosaver.saveIfChanged(force: true);

    expect(await DocumentDraftService.load(key), isNull);
  });

  test('autosaver triggers remote saver after local save', () async {
    const String key = 'photo_doc:user_3:new';
    final completer = Completer<DocumentDraft>();

    final autosaver = DocumentDraftAutosaver(
      type: 'photo_doc',
      keyProvider: () => key,
      payloadProvider: () => <String, dynamic>{'project_name': 'remote'},
      remoteSaver: (draft) async => completer.complete(draft),
    );

    await autosaver.saveIfChanged(force: true);

    final remoteDraft = await completer.future.timeout(
      const Duration(seconds: 1),
    );
    expect(remoteDraft.key, key);
    expect(remoteDraft.payload['project_name'], 'remote');
    expect((await DocumentDraftService.load(key))?.payload['project_name'],
        'remote');
  });

  test('autosaver delete wins over an in-flight save', () async {
    const String key = 'file_edit:user_1:file_639';
    final Completer<void> allowPayload = Completer<void>();

    final autosaver = DocumentDraftAutosaver(
      type: 'file_edit',
      keyProvider: () => key,
      payloadProvider: () async {
        await allowPayload.future;
        return <String, dynamic>{
          'text_fields': <String, dynamic>{'1': 'stale'},
        };
      },
    );

    final Future<void> saveFuture = autosaver.saveIfChanged(force: true);
    await autosaver.delete(waitForRemote: true);
    allowPayload.complete();
    await saveFuture;

    expect(await DocumentDraftService.load(key), isNull);
  });

  test('autosaver delete wins over an in-flight remote save', () async {
    const String key = 'file_edit:user_1:file_640';
    final Map<String, DocumentDraft> remoteDrafts = <String, DocumentDraft>{};
    final Completer<void> remoteSaveStarted = Completer<void>();
    final Completer<void> allowRemoteSave = Completer<void>();

    final autosaver = DocumentDraftAutosaver(
      type: 'file_edit',
      keyProvider: () => key,
      payloadProvider: () => <String, dynamic>{
        'text_fields': <String, dynamic>{'1': 'stale'},
      },
      remoteSaver: (DocumentDraft draft) async {
        if (!remoteSaveStarted.isCompleted) {
          remoteSaveStarted.complete();
        }
        await allowRemoteSave.future;
        remoteDrafts[draft.key] = draft;
      },
      remoteDeleter: (String draftKey) async {
        remoteDrafts.remove(draftKey);
      },
    );

    final Future<void> saveFuture = autosaver.saveIfChanged(force: true);
    await remoteSaveStarted.future;
    await autosaver.delete(waitForRemote: true);
    allowRemoteSave.complete();
    await saveFuture;

    expect(await DocumentDraftService.load(key), isNull);
    expect(remoteDrafts, isNot(contains(key)));
  });

  test('autosaver reruns when a save is requested during remote save',
      () async {
    const String key = 'file_edit:user_1:file_641';
    final Map<String, DocumentDraft> remoteDrafts = <String, DocumentDraft>{};
    final Completer<void> firstRemoteSaveStarted = Completer<void>();
    final Completer<void> allowFirstRemoteSave = Completer<void>();
    final Completer<void> secondRemoteSaveCompleted = Completer<void>();
    String value = 'first';
    int remoteSaveCount = 0;

    final autosaver = DocumentDraftAutosaver(
      type: 'file_edit',
      keyProvider: () => key,
      payloadProvider: () => <String, dynamic>{
        'text_fields': <String, dynamic>{'1': value},
      },
      remoteSaver: (DocumentDraft draft) async {
        remoteSaveCount += 1;
        if (remoteSaveCount == 1) {
          firstRemoteSaveStarted.complete();
          await allowFirstRemoteSave.future;
        }
        remoteDrafts[draft.key] = draft;
        if (remoteSaveCount == 2 && !secondRemoteSaveCompleted.isCompleted) {
          secondRemoteSaveCompleted.complete();
        }
      },
    );

    final Future<void> firstSave = autosaver.saveIfChanged(force: true);
    await firstRemoteSaveStarted.future;
    value = 'second';
    await autosaver.saveIfChanged(force: true);
    allowFirstRemoteSave.complete();
    await firstSave;
    await secondRemoteSaveCompleted.future.timeout(
      const Duration(seconds: 1),
    );

    expect(remoteSaveCount, 2);
    expect(
      (remoteDrafts[key]!.payload['text_fields'] as Map<String, dynamic>)['1'],
      'second',
    );
    expect(
      ((await DocumentDraftService.load(key))!.payload['text_fields']
          as Map<String, dynamic>)['1'],
      'second',
    );
  });

  group('remote draft support', () {
    test('syncs backend-supported document draft types', () {
      expect(
        isRemoteDocumentDraftSupported(
          draftKey: 'file_edit:user_1:file_638',
        ),
        isTrue,
      );
      expect(
        isRemoteDocumentDraftSupported(
          draftKey: 'photo_doc:user_1:site_2',
        ),
        isTrue,
      );
      expect(
        isRemoteDocumentDraftSupported(
          draftType: 'audit_fix',
          draftKey: 'audit_fix:user_1:new',
        ),
        isTrue,
      );
      expect(
        isRemoteDocumentDraftSupported(
          draftType: 'unknown',
          draftKey: 'unknown:user_1:new',
        ),
        isFalse,
      );
    });
  });
}
