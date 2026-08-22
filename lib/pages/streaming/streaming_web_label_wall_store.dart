part of 'streaming_web_label_page.dart';

class _NaturalSortPart {
  final String text;
  final int? number;

  const _NaturalSortPart.text(this.text) : number = null;

  const _NaturalSortPart.number(this.text, this.number);
}

typedef _WallStreamStore = WallStreamStore;

class WallStreamStore {
  List<Map<String, dynamic>> streams = const <Map<String, dynamic>>[];

  final Map<String, String> _preparedKeys = <String, String>{};
  final Map<String, Map<String, dynamic>> _preparedCache =
      <String, Map<String, dynamic>>{};
  final Map<String, int> _indexBySlotKey = <String, int>{};
  final Map<String, int> _firstIndexByStreamId = <String, int>{};
  final Map<String, int> _firstIndexByLookupValue = <String, int>{};
  Set<String> _streamIds = const <String>{};

  Iterable<String> get streamIds => _streamIds;

  void clearPreparedCache() {
    _preparedKeys.clear();
    _preparedCache.clear();
  }

  void clearStreams() {
    streams = const <Map<String, dynamic>>[];
    _rebuildIndexes();
  }

  void replaceStreams(List<Map<String, dynamic>> nextStreams) {
    streams = List<Map<String, dynamic>>.unmodifiable(nextStreams);
    _rebuildIndexes();
  }

  void replaceAt(int index, Map<String, dynamic> stream) {
    if (index < 0 || index >= streams.length) return;
    final nextStreams = List<Map<String, dynamic>>.of(streams);
    nextStreams[index] = stream;
    replaceStreams(nextStreams);
  }

  List<Map<String, dynamic>> sortedSlots(
    String label,
    Iterable<Map<String, dynamic>> source,
  ) {
    final slots = source.map((stream) {
      final next = Map<String, dynamic>.from(stream);
      next.remove('_wall_playback_session_id');
      next.remove('_wall_profile');
      next['_wall_overlay_pending'] ??= false;
      next['_wall_overlay_ready'] ??= false;
      return next;
    }).toList();

    slots.sort(compareStreams);
    for (var index = 0; index < slots.length; index += 1) {
      final stream = slots[index];
      stream['_wall_slot_index'] = index;
      stream['_wall_slot_key'] =
          slotKeyFor(label, stream, fallbackIndex: index);
    }
    prunePreparedCache(label, slots);
    return slots;
  }

  bool mergePrepared(List<Map<String, dynamic>> preparedStreams) {
    if (preparedStreams.isEmpty || streams.isEmpty) return false;

    final nextStreams = List<Map<String, dynamic>>.of(streams);
    var changed = false;
    for (final prepared in preparedStreams) {
      final index = indexForPreparedStream(prepared);
      if (index == null || index < 0 || index >= nextStreams.length) continue;
      nextStreams[index] = prepared;
      changed = true;
    }
    if (!changed) return false;

    replaceStreams(nextStreams);
    return true;
  }

  int? indexForPreparedStream(Map<String, dynamic> stream) {
    final slotKey = slotKeyOf(stream);
    if (slotKey.isNotEmpty) {
      final index = _indexBySlotKey[slotKey];
      if (index != null) return index;
    }

    final streamId = streamIdOf(stream);
    if (streamId.isNotEmpty) {
      return _firstIndexByStreamId[streamId];
    }
    return null;
  }

  int? indexForStreamId(String streamId) {
    final normalized = streamId.trim();
    if (normalized.isEmpty) return null;
    return _firstIndexByStreamId[normalized];
  }

  Map<String, dynamic>? findByCameraName(String cameraName) {
    final normalized = cameraName.trim();
    if (normalized.isEmpty) return null;
    final index = _firstIndexByLookupValue[normalized];
    if (index == null || index < 0 || index >= streams.length) return null;
    return streams[index];
  }

  Map<String, dynamic>? findBySlotKey(String slotKey) {
    final normalized = slotKey.trim();
    if (normalized.isEmpty) return null;
    final index = _indexBySlotKey[normalized];
    if (index == null || index < 0 || index >= streams.length) return null;
    return streams[index];
  }

  void prunePreparedCache(
    String label,
    Iterable<Map<String, dynamic>> activeStreams,
  ) {
    final activeIds = activeStreams
        .map((stream) => cacheId(label, stream))
        .where((id) => id.isNotEmpty)
        .toSet();
    _preparedKeys.removeWhere((id, _) => !activeIds.contains(id));
    _preparedCache.removeWhere((id, _) => !activeIds.contains(id));
  }

  Map<String, dynamic>? cachedPrepared(String cacheId, String cacheKey) {
    if (cacheId.isEmpty || cacheKey.isEmpty) return null;
    if (_preparedKeys[cacheId] != cacheKey) return null;
    return _preparedCache[cacheId];
  }

  void savePrepared(
    String cacheId,
    String cacheKey,
    Map<String, dynamic> stream,
  ) {
    if (cacheId.isEmpty || cacheKey.isEmpty) return;
    _preparedKeys[cacheId] = cacheKey;
    _preparedCache[cacheId] = stream;
  }

  void savePreparedValue(String cacheId, Map<String, dynamic> stream) {
    if (cacheId.isEmpty) return;
    _preparedCache[cacheId] = stream;
  }

  void _rebuildIndexes() {
    _indexBySlotKey.clear();
    _firstIndexByStreamId.clear();
    _firstIndexByLookupValue.clear();
    final streamIds = <String>{};

    for (var index = 0; index < streams.length; index += 1) {
      final stream = streams[index];
      final slotKey = slotKeyOf(stream);
      if (slotKey.isNotEmpty) {
        _indexBySlotKey[slotKey] = index;
      }

      final streamId = streamIdOf(stream);
      if (streamId.isNotEmpty) {
        streamIds.add(streamId);
        _firstIndexByStreamId.putIfAbsent(streamId, () => index);
      }

      for (final lookupValue in lookupValues(stream)) {
        _firstIndexByLookupValue.putIfAbsent(lookupValue, () => index);
      }
    }
    _streamIds = streamIds;
  }

  static String streamName(Map<String, dynamic> stream) {
    // Media-session scope must use StreamConfig.stream_name when available.
    final name = stream['stream_name'] ?? stream['key'] ?? stream['name'];
    final streamId = stream['stream_id'];
    return (name ?? streamId ?? '').toString();
  }

  static String streamIdOf(Map<String, dynamic> stream) =>
      (stream['stream_id'] ?? '').toString();

  static String slotKeyOf(Map<String, dynamic> stream) =>
      (stream['_wall_slot_key'] ?? '').toString();

  static int? slotIndexOf(Map<String, dynamic> stream) {
    final value = stream['_wall_slot_index'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  static String cacheId(String label, Map<String, dynamic> stream) {
    final slotKey = slotKeyOf(stream);
    if (slotKey.isNotEmpty) return slotKey;
    return slotKeyFor(label, stream);
  }

  static String slotKeyFor(
    String label,
    Map<String, dynamic> stream, {
    int? fallbackIndex,
  }) {
    final slotPrefix = fallbackIndex == null
        ? label
        : '$label|slot:${fallbackIndex.toString().padLeft(3, '0')}';
    final streamId = streamIdOf(stream);
    if (streamId.isNotEmpty) return '$slotPrefix|stream:$streamId';
    final mediaPath = stream['media_path']?.toString().trim() ?? '';
    if (mediaPath.isNotEmpty) return '$slotPrefix|media:$mediaPath';
    final name = streamName(stream);
    if (name.isNotEmpty) return '$slotPrefix|name:$name';
    if (fallbackIndex != null) return slotPrefix;
    return '';
  }

  static int? streamOrder(Map<String, dynamic> stream) {
    for (final key in const <String>[
      'display_order',
      'sort_order',
      'order',
      'position',
      'index',
    ]) {
      final value = stream[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString().trim() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static int compareStreams(Map<String, dynamic> a, Map<String, dynamic> b) {
    final orderA = streamOrder(a);
    final orderB = streamOrder(b);
    if (orderA != null && orderB != null && orderA != orderB) {
      return orderA.compareTo(orderB);
    }
    if (orderA != null && orderB == null) return -1;
    if (orderA == null && orderB != null) return 1;

    final nameComparison = naturalCompare(streamName(a), streamName(b));
    if (nameComparison != 0) return nameComparison;
    return naturalCompare(streamIdOf(a), streamIdOf(b));
  }

  static int naturalCompare(String left, String right) {
    final leftParts = _naturalSortParts(left);
    final rightParts = _naturalSortParts(right);
    final length = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < length; i += 1) {
      final a = leftParts[i];
      final b = rightParts[i];
      if (a.number != null && b.number != null) {
        final comparison = a.number!.compareTo(b.number!);
        if (comparison != 0) return comparison;
        final digitLengthComparison = a.text.length.compareTo(b.text.length);
        if (digitLengthComparison != 0) return digitLengthComparison;
        continue;
      }
      final comparison = a.text.compareTo(b.text);
      if (comparison != 0) return comparison;
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  static List<_NaturalSortPart> _naturalSortParts(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <_NaturalSortPart>[_NaturalSortPart.text('')];
    }

    final matches = RegExp(r'\d+|\D+').allMatches(normalized);
    return matches.map((match) {
      final text = match.group(0) ?? '';
      final number = int.tryParse(text);
      return number == null
          ? _NaturalSortPart.text(text)
          : _NaturalSortPart.number(text, number);
    }).toList(growable: false);
  }

  static Set<String> lookupValues(Map<String, dynamic> stream) {
    return <Object?>[
      stream['key'],
      stream['stream_name'],
      stream['name'],
      stream['stream_id'],
      stream['media_path'],
    ]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
