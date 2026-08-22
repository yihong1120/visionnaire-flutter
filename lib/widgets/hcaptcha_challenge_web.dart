import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@visibleForTesting
String? hCaptchaNonEmptyStringFromJs(JSAny? value) {
  if (value == null || !value.isA<JSString>()) return null;
  final string = (value as JSString).toDart.trim();
  return string.isEmpty ? null : string;
}

class HCaptchaChallenge extends StatefulWidget {
  const HCaptchaChallenge({
    super.key,
    required this.siteKey,
    required this.onTokenChanged,
    this.onError,
    this.resetCounter = 0,
  });

  final String siteKey;
  final ValueChanged<String?> onTokenChanged;
  final ValueChanged<String?>? onError;
  final int resetCounter;

  @override
  State<HCaptchaChallenge> createState() => _HCaptchaChallengeState();
}

class _HCaptchaChallengeState extends State<HCaptchaChallenge> {
  static const double _normalWidgetWidth = 303;
  static const double _normalWidgetHeight = 78;

  late final String _elementId;
  late final String _viewType;
  JSAny? _widgetId;
  JSExportedDartFunction? _tokenCallback;
  JSExportedDartFunction? _expiredCallback;
  JSExportedDartFunction? _errorCallback;

  @override
  void initState() {
    super.initState();

    final int uniqueId = DateTime.now().microsecondsSinceEpoch;
    _elementId = 'visionnaire-hcaptcha-$uniqueId';
    _viewType = 'visionnaire-hcaptcha-view-$uniqueId';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final web.HTMLDivElement container = web.HTMLDivElement()
        ..id = _elementId
        ..style.width = '${_normalWidgetWidth}px'
        ..style.height = '${_normalWidgetHeight}px'
        ..style.minHeight = '${_normalWidgetHeight}px'
        ..style.display = 'flex'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.overflow = 'hidden';
      return container;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  @override
  void didUpdateWidget(covariant HCaptchaChallenge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteKey != widget.siteKey ||
        oldWidget.resetCounter != widget.resetCounter) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _render(reset: true));
    }
  }

  @override
  void dispose() {
    _remove();
    _tokenCallback = null;
    _expiredCallback = null;
    _errorCallback = null;
    super.dispose();
  }

  Future<void> _render({bool reset = false}) async {
    final String siteKey = widget.siteKey.trim();
    if (!mounted || siteKey.isEmpty) return;

    try {
      await _HCaptchaWebApi.ensureLoaded();
      if (!mounted) return;
      if (reset) {
        widget.onTokenChanged(null);
        _reset();
      }
      _renderWidget(siteKey);
    } catch (_) {
      if (mounted) _reportError('hcaptcha_load_timeout');
    }
  }

  void _renderWidget(String siteKey) {
    final web.Element? container = web.document.getElementById(_elementId);
    if (container == null) {
      _reportError('hcaptcha_container_not_found');
      return;
    }

    final JSObject? api = _HCaptchaWebApi.api;
    if (!_HCaptchaWebApi.canRender(api)) {
      _reportError('hcaptcha_not_ready');
      return;
    }

    _remove();
    _tokenCallback = ((JSAny? rawToken) {
      final String? token = hCaptchaNonEmptyStringFromJs(rawToken);
      if (token == null) {
        _reportError('invalid_hcaptcha_response_token');
        return;
      }
      widget.onTokenChanged(token);
    }).toJS;
    _expiredCallback = (() {
      widget.onTokenChanged(null);
      _reset();
    }).toJS;
    _errorCallback = ((JSAny? rawCode) {
      widget.onTokenChanged(null);
      widget.onError?.call(
        hCaptchaNonEmptyStringFromJs(rawCode) ?? 'hcaptcha_error',
      );
    }).toJS;

    final JSObject options = JSObject()
      ..setProperty('sitekey'.toJS, siteKey.toJS)
      ..setProperty('size'.toJS, 'normal'.toJS)
      ..setProperty('callback'.toJS, _tokenCallback)
      ..setProperty('expired-callback'.toJS, _expiredCallback)
      ..setProperty('error-callback'.toJS, _errorCallback);

    try {
      _widgetId = api!.callMethod<JSAny?>(
        'render'.toJS,
        container,
        options,
      );
    } catch (_) {
      _reportError('hcaptcha_render_error');
    }
  }

  void _reset() {
    final JSObject? api = _HCaptchaWebApi.api;
    final JSAny? widgetId = _widgetId;
    if (api == null || widgetId == null) return;

    try {
      api.callMethod<JSAny?>('reset'.toJS, widgetId);
    } catch (_) {
      _remove();
    }
  }

  void _remove() {
    final JSObject? api = _HCaptchaWebApi.api;
    final JSAny? widgetId = _widgetId;
    _widgetId = null;

    if (api != null && widgetId != null) {
      try {
        if (_HCaptchaWebApi.hasMethod(api, 'remove')) {
          api.callMethod<JSAny?>('remove'.toJS, widgetId);
        } else if (_HCaptchaWebApi.hasMethod(api, 'reset')) {
          api.callMethod<JSAny?>('reset'.toJS, widgetId);
        }
      } catch (_) {}
    }

    final web.Element? container = web.document.getElementById(_elementId);
    container?.innerHTML = ''.toJS;
  }

  void _reportError(String code) {
    widget.onTokenChanged(null);
    widget.onError?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _normalWidgetHeight,
      width: _normalWidgetWidth,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

class _HCaptchaWebApi {
  _HCaptchaWebApi._();

  static const String _scriptId = 'visionnaire-hcaptcha-api';
  static const String _scriptUrl =
      'https://js.hcaptcha.com/1/api.js?render=explicit';
  static const Duration _loadTimeout = Duration(seconds: 15);
  static const Duration _checkInterval = Duration(milliseconds: 100);

  static Future<void>? _loadFuture;

  static JSObject? get api {
    final JSAny? value = web.window.getProperty<JSAny?>('hcaptcha'.toJS);
    if (value == null || !value.isA<JSObject>()) return null;
    return value as JSObject;
  }

  static bool canRender(JSObject? api) {
    return api != null && hasMethod(api, 'render');
  }

  static bool hasMethod(JSObject api, String name) {
    final JSAny? method = api.getProperty<JSAny?>(name.toJS);
    return method != null && method.isA<JSFunction>();
  }

  static Future<void> ensureLoaded() {
    if (canRender(api)) return Future<void>.value();

    final Future<void>? existing = _loadFuture;
    if (existing != null) return existing;

    final Future<void> loadFuture = _loadScript().catchError(
      (Object error, StackTrace stackTrace) {
        _loadFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _loadFuture = loadFuture;
    return loadFuture;
  }

  static Future<void> _loadScript() {
    final Completer<void> completer = Completer<void>();
    final DateTime deadline = DateTime.now().add(_loadTimeout);

    if (web.document.getElementById(_scriptId) == null) {
      final web.HTMLScriptElement script = web.HTMLScriptElement()
        ..id = _scriptId
        ..src = _scriptUrl
        ..async = true
        ..defer = true;

      final web.Node? target = web.document.head ?? web.document.body;
      if (target == null) {
        completer.completeError(StateError('Document is not ready.'));
      } else {
        target.appendChild(script);
      }
    }

    void checkReady() {
      if (completer.isCompleted) return;
      if (canRender(api)) {
        completer.complete();
        return;
      }
      if (!DateTime.now().isBefore(deadline)) {
        completer.completeError(StateError('hCaptcha script load timed out.'));
        return;
      }
      Timer(_checkInterval, checkReady);
    }

    checkReady();
    return completer.future;
  }
}
