String inferImageMime(String name) {
  final ext = name.toLowerCase().split('.').last;
  return {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'webp': 'image/webp',
        'gif': 'image/gif',
        'bmp': 'image/bmp'
      }[ext] ??
      'image/*';
}
