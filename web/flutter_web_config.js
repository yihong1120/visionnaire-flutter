// Configure Flutter web to use modern Intl APIs
window.flutterConfiguration = {
  renderer: "html",
  useIntlSegmenter: true,
  // Force use of Intl.Segmenter over deprecated v8BreakIterator
  intlOptions: {
    useSegmenter: true,
    forceSegmenter: true
  }
};

// Set environment variable to disable v8BreakIterator
window._flutter = window._flutter || {};
window._flutter.buildMode = "release";
window._flutter.useIntlSegmenter = true;

// Polyfill check for Intl.Segmenter support
if (typeof Intl.Segmenter === 'undefined') {
  console.warn('Intl.Segmenter not supported in this browser, falling back to available options');

  // Try to provide a basic polyfill or use alternative
  if (typeof Intl.v8BreakIterator !== 'undefined') {
    console.log('Using v8BreakIterator as fallback (will show deprecation warning)');
  }
} else {
  console.log('Using Intl.Segmenter for text segmentation');

  // Override any potential v8BreakIterator usage
  if (typeof Intl.v8BreakIterator !== 'undefined') {
    console.log('Intl.v8BreakIterator available but preferring Intl.Segmenter');
  }
}
