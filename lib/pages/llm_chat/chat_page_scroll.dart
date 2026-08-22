part of 'chat_page.dart';

mixin _ChatPageScroll on _ChatPageStateBase {
  @override
  void _scrollToBottom({bool force = false}) {
    if (_hasPendingScrollToBottom || _isAnimatingToBottom) return;
    if (!force && !_shouldAutoScrollToBottom()) return;

    _hasPendingScrollToBottom = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _hasPendingScrollToBottom = false;
      if (!mounted || !_scroll.hasClients) return;
      if (_isAnimatingToBottom) return;
      if (!force && !_shouldAutoScrollToBottom()) return;

      _jumpToBottom();

      if (!force) {
        _markAtBottom();
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (mounted && _scroll.hasClients) {
        _jumpToBottom();
        _markAtBottom();
      }
    });
  }

  @override
  Future<void> _animateToBottom() {
    if (!_scroll.hasClients) return Future.value();

    if (mounted) {
      setState(() {
        _isAnimatingToBottom = true;
        _showScrollToBottom = false;
      });
    }

    Future<void> run() async {
      try {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        final desired =
            _isPhoneLayout ? pos.minScrollExtent : pos.maxScrollExtent;
        final target = desired.clamp(pos.minScrollExtent, pos.maxScrollExtent);

        if ((pos.pixels - target).abs() <= 1.0) return;

        await pos.animateTo(
          target,
          duration: AppMotion.maybeZero(context, AppMotion.scroll),
          curve: AppMotion.enterCurve,
        );

        if (_scroll.hasClients) {
          final p2 = _scroll.position;
          final desired2 =
              _isPhoneLayout ? p2.minScrollExtent : p2.maxScrollExtent;
          final target2 =
              desired2.clamp(p2.minScrollExtent, p2.maxScrollExtent);
          if ((p2.pixels - target2).abs() > 1.0) {
            p2.jumpTo(target2);
          }
        }
      } catch (_) {
        // Ignore transient scroll/extent changes during rebuilds.
      } finally {
        if (mounted) {
          setState(() {
            _isAnimatingToBottom = false;
            _isAtBottom = true;
            _showScrollToBottom = false;
          });
        }
      }
    }

    return run();
  }

  void _onScroll() {
    if (_isAnimatingToBottom) return;
    final pos = _scroll.position;
    final atBottom =
        _distanceFromBottom(pos) <= _ChatPageStateBase._scrollBottomThreshold;
    final newShow = !atBottom;
    if (_showScrollToBottom == newShow && _isAtBottom == atBottom) return;
    setState(() {
      _showScrollToBottom = newShow;
      _isAtBottom = atBottom;
    });
  }

  @override
  void _handleInputTap() {
    if (!_isPhoneLayout) return;
    if (!_inputFocusNode.hasFocus) {
      _inputFocusNode.requestFocus();
    }
  }

  @override
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_isAutoScrollingToBottom || _isAnimatingToBottom) return false;
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is UserScrollNotification) {
      _lastUserScrollAt = DateTime.now();
    }
    return false;
  }

  bool _shouldAutoScrollToBottom() {
    if (!_scroll.hasClients) return true;

    final pos = _scroll.position;
    if (_distanceFromBottom(pos) >
        _ChatPageStateBase._autoScrollBottomThreshold) {
      return false;
    }

    final lastUserScrollAt = _lastUserScrollAt;
    if (lastUserScrollAt == null) return true;

    final recentlyScrolled = DateTime.now().difference(lastUserScrollAt) <
        _ChatPageStateBase._userScrollSettleDuration;
    return !recentlyScrolled || _distanceFromBottom(pos) <= 1.0;
  }

  double _distanceFromBottom(ScrollPosition pos) {
    return _isPhoneLayout
        ? (pos.pixels - pos.minScrollExtent).abs()
        : (pos.maxScrollExtent - pos.pixels).abs();
  }

  double _bottomTarget(ScrollPosition pos) {
    final desired = _isPhoneLayout ? pos.minScrollExtent : pos.maxScrollExtent;
    return desired.clamp(pos.minScrollExtent, pos.maxScrollExtent);
  }

  void _jumpToBottom() {
    final pos = _scroll.position;
    final target = _bottomTarget(pos);
    if ((pos.pixels - target).abs() <= 0.5) return;

    _isAutoScrollingToBottom = true;
    try {
      _scroll.jumpTo(target);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isAutoScrollingToBottom = false;
      });
    }
  }

  void _markAtBottom() {
    if (!mounted) return;
    setState(() {
      _isAtBottom = true;
      _showScrollToBottom = false;
    });
  }
}
