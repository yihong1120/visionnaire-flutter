part of 'chat_page.dart';

mixin _ChatPageStreaming on _ChatPageStateBase {
  @override
  Future<void> _handleStreamEvent(Map<String, dynamic> event) async {
    if (!mounted) return;

    final type = event['type'] as String?;

    switch (type) {
      case 'token':
        final content = event['content'] as String? ?? '';
        setState(() {
          _streamingAnswer = (_streamingAnswer ?? '') + content;
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.last['content'] = _streamingAnswer;
          }
        });
        if (!_showScrollToBottom && !_isAnimatingToBottom) {
          _scrollToBottom();
        }
        break;

      case 'done':
        // History reload is handled by the finally block in _send/_confirmEdit/_regenerate
        // so that it always runs whether streaming finished normally or was cancelled.
        setState(() {
          _runState = null;
          _streamingAnswer = null;
        });
        break;

      case 'error':
        final errorMessage = event['message'] as String? ?? 'Unknown error';
        setState(() {
          _error = errorMessage;
          _runState = null;
          _streamingAnswer = null;
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.removeLast();
          }
        });
        break;
    }
  }

  @override
  Future<void> _cancelStream() async {
    _isCancelling = true;
    _streamClient?.close();
    // State cleanup and history reload will happen in the _send/_confirmEdit
    // finally blocks once the stream terminates.
  }
}
