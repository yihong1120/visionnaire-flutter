part of 'chat_page.dart';

mixin _ChatPageActions on _ChatPageStateBase {
  Future<void> _loadHistory() async {
    if (_actualChatId == null) return;

    setState(() {
      _error = null;
      _isLoadingHistory = true;
    });
    try {
      final messages = await AuthUtils.withAuthRetry(
        context,
        (token) => _api.getChatHistory(token, _actualChatId!),
        notLoggedInMessage: AppLocalizations.of(context)!.notLoggedIn,
      );
      setState(() {
        _messages = messages;
        _isLoadingHistory = false;
      });
      _scrollToBottom(force: true);
    } catch (e) {
      setState(() {
        _error =
            '${AppLocalizations.of(context)!.failedToLoadHistoryAfterRefresh}: $e';
        _isLoadingHistory = false;
      });
    }
  }

  /// Returns true if [id] corresponds to a real backend message ID.
  /// Local optimistic messages are tagged with `'_isLocal': true`.
  bool _isBackendMessage(int id) {
    final msg = _messages.where((m) => m['id'] == id).firstOrNull;
    if (msg == null) return false;
    return msg['_isLocal'] != true;
  }

  /// Create a new room then navigate to it (handles the case where
  /// [_actualChatId] is null when the user first sends a message).
  Future<void> _createAndNavigate() async {
    final local = AppLocalizations.of(context)!;
    final q = _controller.text.trim();

    if (q.isEmpty) {
      setState(() => _error = local.chatMessageCannotBeEmpty);
      return;
    }

    try {
      setState(() {
        _isBusy = true;
        _error = null;
      });

      final room = await AuthUtils.withAuthRetry(
        context,
        (token) => _api.createRoom(token),
        notLoggedInMessage: local.notLoggedIn,
      );

      final newChatId = room['id'] as int;
      final newChatTitle = room['title'] as String? ?? 'New Chat';

      if (!mounted) return;

      widget.onMessageSent?.call(newChatId, newChatTitle, pendingQuestion: q);

      if (!widget.isEmbedded) {
        pushReplacementAppPage<void, void>(
          context,
          builder: (_) => ChatPage(
            chatId: newChatId,
            title: newChatTitle,
            isEmbedded: false,
            pendingQuestion: q,
            onMessageSent: widget.onMessageSent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = '${local.failedToAskAfterRefresh}: $e';
      });
    }
  }

  // ─────────────────────────────── send new message ───────────────────────

  Future<void> _send() async {
    final local = AppLocalizations.of(context)!;
    final q = _controller.text.trim();

    if (q.isEmpty && _draftAttachments.isEmpty) {
      setState(() => _error = local.chatMessageCannotBeEmpty);
      return;
    }

    final attachmentIds = _draftAttachments.map((e) => e.id).toList();
    final draftsReference = List<ChatAttachment>.from(_draftAttachments);
    final questionText = q.isEmpty ? '請描述這張圖片' : q;

    // Add optimistic messages tagged as local so edit/regenerate
    // won't mistake them for backend IDs.
    final localUserTs = DateTime.now().millisecondsSinceEpoch;
    final localAsstTs = localUserTs + 1;

    setState(() {
      _isBusy = true;
      _runState = 'running';
      _error = null;
      _streamingAnswer = '';
      _messages.add({
        'id': localUserTs,
        'role': 'user',
        'content': questionText,
        '_isLocal': true,
        'attachments': draftsReference
            .map((att) => {
                  'id': att.id,
                  'original_name': att.originalName,
                  'content_type': att.contentType,
                  'preview_url': att.previewUrl,
                  'preview_kind': att.previewKind,
                })
            .toList(),
      });
      _messages.add({
        'id': localAsstTs,
        'role': 'assistant',
        'content': '',
        '_isLocal': true,
        'sources': [],
        'stream_status': null,
      });
      _draftAttachments.clear();
    });

    _controller.clear();
    _scrollToBottom(force: true);

    _streamClient = http.Client();
    final clientRef = _streamClient;

    try {
      if (_actualChatId == null) {
        throw Exception('Chat ID is required to send message');
      }

      // POST /chats/{chat_id}/stream — new message
      await AuthUtils.withAuthRetry(
        context,
        (token) async {
          await for (final event in _api.streamMessage(
            chatId: _actualChatId!,
            token: token,
            text: questionText,
            attachmentIds: attachmentIds,
            client: clientRef,
          )) {
            await _handleStreamEvent(event);
          }
        },
        notLoggedInMessage: local.notLoggedIn,
      );

      if (_actualChatId != null) {
        widget.onMessageSent?.call(null, null);
      }
    } catch (e) {
      if (!_isCancelling) {
        setState(() {
          _error = '${local.failedToAskAfterRefresh}: $e';
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.removeLast();
          }
        });
      }
    } finally {
      setState(() {
        _isBusy = false;
        _runState = null;
        _streamClient = null;
        _streamingAnswer = null;
        _isCancelling = false;
      });
      // Reload to replace optimistic local messages with backend data + real IDs.
      if (_actualChatId != null && mounted) {
        await _loadHistory();
      }
    }
  }

  // ─────────────────────────────── edit ───────────────────────────────────

  @override
  void _startEdit(int id, String text, List<dynamic>? attachments) {
    // Extract backend injected attachment text markers to restore filenames
    final embeddedNames = RegExp(
            r'\[(?:document|image|file|video|audio):\s*([^\]]+)\]',
            caseSensitive: false)
        .allMatches(text)
        .map((m) => m.group(1)?.trim())
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toList();

    // Remove backend injected attachment text markers if they accidentally leak into edit box
    final cleanText = text
        .replaceAll(
            RegExp(r'\s*\[(?:document|image|file|video|audio):\s*[^\]]+\]',
                caseSensitive: false),
            '')
        .trim();

    setState(() {
      _editingId = id;
      _editCtl.text = cleanText;
      _editingAttachments.clear();

      if (attachments != null) {
        for (int i = 0; i < attachments.length; i++) {
          final att = attachments[i];
          if (att is Map<String, dynamic>) {
            final attMap = Map<String, dynamic>.from(att);
            if (i < embeddedNames.length &&
                (attMap['original_name'] == null ||
                    (attMap['original_name'] as String).isEmpty) &&
                (attMap['filename'] == null ||
                    (attMap['filename'] as String).isEmpty) &&
                (attMap['name'] == null ||
                    (attMap['name'] as String).isEmpty)) {
              attMap['original_name'] = embeddedNames[i];
            }
            _editingAttachments.add(ChatEditingAttachment.fromServer(attMap));
          }
        }
      }
    });
  }

  @override
  void _cancelEdit() => setState(() {
        _editingId = null;
        _editingAttachments.clear();
      });

  @override
  Future<void> _confirmEdit(int qId) async {
    final local = AppLocalizations.of(context)!;
    final newQ = _editCtl.text.trim();
    if (newQ.isEmpty && _editingAttachments.isEmpty) {
      setState(() => _error = local.chatMessageCannotBeEmpty);
      return;
    }

    // Only use the edit endpoint if qId is a real backend message ID.
    final useEditEndpoint = _isBackendMessage(qId);

    setState(() {
      _isBusy = true;
      _runState = 'running';
      _error = null;
      _streamingAnswer = '';
    });

    final attachmentIds = _editingAttachments
        .where((att) => att.id != null)
        .map((att) => att.id!)
        .toList();
    final editDraftsRef = List<ChatEditingAttachment>.from(_editingAttachments);

    final qIndex = _messages.indexWhere((m) => m['id'] == qId);
    if (qIndex != -1) {
      final localUserTs = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _messages.removeRange(qIndex, _messages.length);
        _messages.add({
          'id': localUserTs,
          'role': 'user',
          'content': newQ,
          '_isLocal': true,
          'attachments': editDraftsRef
              .map((att) => {
                    'id': att.id,
                    'original_name': att.name,
                    'content_type': att.mime,
                    'preview_url': att.previewUrl,
                  })
              .toList(),
        });
        _messages.add({
          'id': localUserTs + 1,
          'role': 'assistant',
          'content': '',
          '_isLocal': true,
          'sources': [],
          'stream_status': null,
        });
      });
    }

    _cancelEdit();
    _scrollToBottom(force: true);

    _streamClient = http.Client();
    final clientRef = _streamClient;

    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) async {
          final stream = useEditEndpoint
              // POST /chat/rooms/{chat_id}/messages/{msg_id}/stream — edit existing
              ? _api.streamEditMessage(
                  chatId: _actualChatId!,
                  msgId: qId,
                  token: token,
                  text: newQ,
                  attachmentIds: attachmentIds,
                  client: clientRef,
                )
              // Fallback: treat as a new message if no real backend ID
              : _api.streamMessage(
                  chatId: _actualChatId!,
                  token: token,
                  text: newQ,
                  attachmentIds: attachmentIds,
                  client: clientRef,
                );
          await for (final event in stream) {
            await _handleStreamEvent(event);
          }
        },
        notLoggedInMessage: local.notLoggedIn,
      );
    } catch (e) {
      if (!_isCancelling) {
        setState(() {
          _error = '${local.editFailedAfterRefresh}: $e';
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.removeLast();
          }
        });
      }
    } finally {
      setState(() {
        _isBusy = false;
        _runState = null;
        _streamClient = null;
        _streamingAnswer = null;
        _isCancelling = false;
      });
      if (_actualChatId != null && mounted) {
        await _loadHistory();
      }
    }
  }

  // ─────────────────────────────── regenerate ─────────────────────────────

  @override
  Future<void> _regenerate(int qId) async {
    // qId must be a real backend message ID — regenerate requires the backend
    // to know which message to replace.  If it's a local temp ID (shouldn't
    // normally happen since history is reloaded after every send), skip.
    if (!_isBackendMessage(qId)) {
      await _loadHistory();
      return;
    }

    final qMsg = _messages.firstWhere(
      (m) => m['id'] == qId && m['role'] == 'user',
      orElse: () => {},
    );
    final qText = (qMsg['content'] as String? ?? '').trim();
    if (qText.isEmpty) return;

    setState(() {
      _isBusy = true;
      _runState = 'running';
      _error = null;
      _streamingAnswer = '';
    });

    final qIndex = _messages.indexWhere((m) => m['id'] == qId);
    if (qIndex != -1) {
      setState(() {
        if (qIndex + 1 < _messages.length) {
          _messages.removeRange(qIndex + 1, _messages.length);
        }
        _messages.add({
          'id': DateTime.now().millisecondsSinceEpoch,
          'role': 'assistant',
          'content': '',
          '_isLocal': true,
          'sources': [],
          'stream_status': null,
        });
      });
    }

    _scrollToBottom(force: true);

    _streamClient = http.Client();
    final clientRef = _streamClient;

    try {
      // POST /chats/{chat_id}/messages/{msg_id}/stream with same text = regenerate
      await AuthUtils.withAuthRetry(
        context,
        (token) async {
          await for (final event in _api.streamEditMessage(
            chatId: _actualChatId!,
            msgId: qId,
            token: token,
            text: qText,
            client: clientRef,
          )) {
            await _handleStreamEvent(event);
          }
        },
        notLoggedInMessage: AppLocalizations.of(context)!.notLoggedIn,
      );
    } catch (e) {
      if (!_isCancelling) {
        setState(() {
          _error =
              '${AppLocalizations.of(context)!.regenerateFailedAfterRefresh}: $e';
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.removeLast();
          }
        });
      }
    } finally {
      setState(() {
        _isBusy = false;
        _runState = null;
        _streamClient = null;
        _streamingAnswer = null;
        _isCancelling = false;
      });
      if (_actualChatId != null && mounted) {
        await _loadHistory();
      }
    }
  }

  // ─────────────────────────────── remove ─────────────────────────────────

  @override
  Future<void> _remove(int msgId) async {
    if (_actualChatId == null) return;
    // Only attempt server-side delete for real backend IDs.
    if (_isBackendMessage(msgId)) {
      setState(() => _isBusy = true);
      try {
        await AuthUtils.withAuthRetry(
          context,
          (token) => _api.deleteMessage(token, _actualChatId!, msgId),
          notLoggedInMessage: AppLocalizations.of(context)!.notLoggedIn,
        );
      } catch (e) {
        setState(() => _error =
            '${AppLocalizations.of(context)!.removeFailedAfterRefresh}: $e');
      } finally {
        setState(() => _isBusy = false);
      }
    }
    await _loadHistory();
  }
}
