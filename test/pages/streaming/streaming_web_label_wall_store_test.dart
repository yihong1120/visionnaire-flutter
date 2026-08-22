import 'package:flutter_test/flutter_test.dart';
import 'package:visionnaire/pages/streaming/streaming_web_label_page.dart';

void main() {
  test('WallStreamStore prefers StreamConfig.stream_name for camera scope', () {
    expect(
      WallStreamStore.streamName(<String, dynamic>{
        'key': 'display-key',
        'stream_name': 'backend-stream-name',
      }),
      'backend-stream-name',
    );
  });

  group('WallStreamStore', () {
    test('sorts streams naturally and assigns fixed slot identities', () {
      final store = WallStreamStore();

      final slots = store.sortedSlots('site-a', <Map<String, dynamic>>[
        {
          'key': 'Cam 11',
          'stream_id': 'id-11',
          'media_path': 'media-11',
        },
        {
          'key': 'Cam 2',
          'stream_id': 'id-2',
          'media_path': 'media-2',
        },
        {
          'key': 'Cam 1',
          'stream_id': 'id-1',
          'media_path': 'media-1',
        },
      ]);

      expect(slots.map(WallStreamStore.streamName), <String>[
        'Cam 1',
        'Cam 2',
        'Cam 11',
      ]);
      expect(slots.map(WallStreamStore.slotIndexOf), <int?>[0, 1, 2]);
      expect(
        slots.map(WallStreamStore.slotKeyOf).toSet(),
        hasLength(slots.length),
      );
      expect(WallStreamStore.slotKeyOf(slots.first), contains('slot:000'));
      expect(WallStreamStore.slotKeyOf(slots[1]), contains('slot:001'));
    });

    test('merges prepared streams back into their original slots', () {
      final store = WallStreamStore();
      final slots = store.sortedSlots('site-a', <Map<String, dynamic>>[
        {'key': 'Cam 1', 'stream_id': 'id-1'},
        {'key': 'Cam 2', 'stream_id': 'id-2'},
        {'key': 'Cam 3', 'stream_id': 'id-3'},
      ]);
      store.replaceStreams(slots);

      final preparedCam3 = Map<String, dynamic>.from(slots[2])
        ..['_wall_playback_uri'] = 'https://example.test/cam3.m3u8';
      final preparedCam1 = Map<String, dynamic>.from(slots[0])
        ..['_wall_playback_uri'] = 'https://example.test/cam1.m3u8';

      final changed = store.mergePrepared(<Map<String, dynamic>>[
        preparedCam3,
        preparedCam1,
      ]);

      expect(changed, isTrue);
      expect(store.streams[0]['_wall_playback_uri'], endsWith('cam1.m3u8'));
      expect(store.streams[1]['_wall_playback_uri'], isNull);
      expect(store.streams[2]['_wall_playback_uri'], endsWith('cam3.m3u8'));
    });

    test('does not collapse duplicate stream ids into one visual cell', () {
      final store = WallStreamStore();
      final slots = store.sortedSlots('site-a', <Map<String, dynamic>>[
        {
          'key': 'Cam 1',
          'stream_id': 'duplicated-id',
          'media_path': 'media-1',
        },
        {
          'key': 'Cam 2',
          'stream_id': 'duplicated-id',
          'media_path': 'media-2',
        },
      ]);
      store.replaceStreams(slots);

      final preparedCam2 = Map<String, dynamic>.from(slots[1])
        ..['_wall_playback_uri'] = 'https://example.test/cam2.m3u8';

      expect(store.mergePrepared(<Map<String, dynamic>>[preparedCam2]), isTrue);
      expect(store.streams[0]['_wall_playback_uri'], isNull);
      expect(store.streams[1]['_wall_playback_uri'], endsWith('cam2.m3u8'));
    });

    test('finds streams by fixed slot key', () {
      final store = WallStreamStore();
      final slots = store.sortedSlots('site-a', <Map<String, dynamic>>[
        {'key': 'Cam 1', 'stream_id': 'id-1'},
      ]);
      store.replaceStreams(slots);

      final slotKey = WallStreamStore.slotKeyOf(slots.first);
      expect(store.findBySlotKey(slotKey)?['key'], 'Cam 1');
      expect(store.findBySlotKey('missing'), isNull);
    });
  });
}
