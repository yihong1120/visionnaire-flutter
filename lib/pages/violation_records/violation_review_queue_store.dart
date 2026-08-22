class ViolationReviewQueueStore {
  ViolationReviewQueueStore._();

  static List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  static void setItems(List<dynamic> items) {
    _items = items
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .where((Map<String, dynamic> item) => _recordId(item).isNotEmpty)
        .toList(growable: false);
  }

  static void updateStatus(String recordId, String reviewStatus) {
    for (int index = 0; index < _items.length; index++) {
      if (_recordId(_items[index]) == recordId) {
        _items[index] = <String, dynamic>{
          ..._items[index],
          'review_status': reviewStatus,
        };
        return;
      }
    }
  }

  static Map<String, dynamic>? findById(String recordId) {
    for (final Map<String, dynamic> item in _items) {
      if (_recordId(item) == recordId) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  static String? nextPendingIdAfter(String currentId) {
    if (_items.isEmpty) return null;
    final int currentIndex = _items.indexWhere(
      (Map<String, dynamic> item) => _recordId(item) == currentId,
    );
    final int startIndex = currentIndex < 0 ? 0 : currentIndex + 1;
    for (int index = startIndex; index < _items.length; index++) {
      if (_isPendingReview(_items[index])) {
        return _recordId(_items[index]);
      }
    }
    for (int index = 0; index < startIndex && index < _items.length; index++) {
      if (_isPendingReview(_items[index])) {
        return _recordId(_items[index]);
      }
    }
    return null;
  }

  static bool _isPendingReview(Map<String, dynamic> item) {
    final String status =
        (item['review_status'] ?? item['reviewStatus'] ?? '').toString();
    return status == 'pending';
  }

  static String _recordId(Map<String, dynamic> item) {
    return (item['id'] ?? item['record_id'] ?? item['recordId'] ?? '')
        .toString();
  }
}
