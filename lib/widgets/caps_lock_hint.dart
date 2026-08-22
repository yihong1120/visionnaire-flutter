import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CapsLockHint extends StatefulWidget {
  const CapsLockHint({
    super.key,
    required this.focusNode,
    this.iconOnly = false,
  });

  final FocusNode focusNode;
  final bool iconOnly;

  @override
  State<CapsLockHint> createState() => _CapsLockHintState();
}

class _CapsLockHintState extends State<CapsLockHint> {
  bool _capsLockOn = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    if (!_supportsCapsLockHint) return;
    _capsLockOn = _currentCapsLockState();
    HardwareKeyboard.instance.addHandler(_handleKeyboardEvent);
    widget.focusNode.addListener(_update);
    _isListening = true;
  }

  @override
  void didUpdateWidget(covariant CapsLockHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isListening) return;
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode.removeListener(_update);
    widget.focusNode.addListener(_update);
    _update();
  }

  @override
  void dispose() {
    if (_isListening) {
      HardwareKeyboard.instance.removeHandler(_handleKeyboardEvent);
      widget.focusNode.removeListener(_update);
    }
    super.dispose();
  }

  bool _handleKeyboardEvent(KeyEvent event) {
    _update();
    return false;
  }

  void _update() {
    final bool next = _currentCapsLockState();
    if (next == _capsLockOn) return;
    setState(() => _capsLockOn = next);
  }

  bool _currentCapsLockState() {
    return HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock);
  }

  bool get _supportsCapsLockHint {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsCapsLockHint) {
      return const SizedBox.shrink();
    }

    final bool showHint = _capsLockOn && widget.focusNode.hasFocus;
    if (widget.iconOnly && !showHint) {
      return const SizedBox(width: 32, height: 48);
    }

    if (!showHint) {
      return const SizedBox.shrink();
    }

    final ColorScheme cs = Theme.of(context).colorScheme;
    final String message = _CapsLockCopy.of(context);
    if (widget.iconOnly) {
      return SizedBox(
        width: 32,
        height: 48,
        child: Tooltip(
          message: message,
          child: Icon(
            Icons.keyboard_capslock,
            size: 20,
            color: cs.tertiary,
            semanticLabel: message,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.keyboard_capslock, size: 16, color: cs.tertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapsLockCopy {
  static String of(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'zh':
        return 'Caps Lock 已開啟，密碼大小寫可能不正確。';
      case 'fr':
        return 'Verr. maj. est activé, la casse du mot de passe peut être incorrecte.';
      case 'ja':
        return 'Caps Lock がオンです。パスワードの大文字小文字に注意してください。';
      default:
        return 'Caps Lock is on. Password capitalization may be incorrect.';
    }
  }
}
